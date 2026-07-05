import Foundation

/// CSI escape sequence types parsed from bytes following ESC [
enum CSISequence: Equatable {
    case arrowUp
    case arrowDown
    case arrowRight
    case arrowLeft
    case optionArrowLeft    // ESC[1;3D (Option+Left)
    case optionArrowRight   // ESC[1;3C (Option+Right)
    case cmdArrowLeft       // ESC[1;9D (Cmd+Left) - same as home
    case cmdArrowRight      // ESC[1;9C (Cmd+Right) - same as end
    case home
    case end
    case delete
    case pasteStart     // ESC[200~
    case pasteEnd       // ESC[201~
    case shiftEnter     // ESC[13;2u (kitty keyboard protocol)
    case unknown([UInt8])
}

/// Terminal input handler
/// Manages raw mode input and special key handling
final class InputHandler {
    /// ANSI escape sequence to enable bracketed paste mode
    static let bracketedPasteEnable: String = "\u{001B}[?2004h"

    /// ANSI escape sequence to disable bracketed paste mode
    static let bracketedPasteDisable: String = "\u{001B}[?2004l"

    /// Callback for debug toggle (Ctrl+B)
    var onDebugToggle: (() -> Void)?

    /// Callback to get available commands for current mode
    var getAvailableCommands: (() -> [String])?

    /// Current input buffer (for display restoration)
    private(set) var currentInput: String = ""

    /// Cursor position within currentInput (0 = start, count = end)
    private var cursorPosition: Int = 0

    /// Whether bracketed paste mode is currently active
    private(set) var isPasteMode: Bool = false

    /// Whether the current input contains newlines (multi-line)
    var isMultiLine: Bool {
        return currentInput.contains("\n")
    }
    
    /// Command history
    private var commandHistory: [String] = []
    private var historyIndex: Int = 0
    private var tempInput: String = ""  // Stores current input when browsing history
    private let maxHistorySize = 100
    
    /// Tab completion state
    private var completionMatches: [String] = []
    private var completionIndex: Int = 0
    private var lastCompletionPrefix: String = ""
    
    /// Read input from terminal in raw mode
    /// Returns the input string, or special control sequences
    /// - "\u{11}" for Ctrl+Q (quit)
    /// - "\u{03}" for Ctrl+C/Ctrl+D (interrupt)
    func readInput() -> String {
        currentInput = ""
        cursorPosition = 0
        isPasteMode = false
        historyIndex = commandHistory.count
        tempInput = ""
        resetCompletion()

        // Enable bracketed paste mode
        print(InputHandler.bracketedPasteEnable, terminator: "")
        fflush(stdout)

        // Set terminal to raw mode
        var oldTermios = termios()
        tcgetattr(STDIN_FILENO, &oldTermios)
        var newTermios = oldTermios
        newTermios.c_lflag &= ~UInt(ICANON | ECHO)
        tcsetattr(STDIN_FILENO, TCSANOW, &newTermios)

        defer {
            print(InputHandler.bracketedPasteDisable, terminator: "")
            fflush(stdout)
            tcsetattr(STDIN_FILENO, TCSANOW, &oldTermios)
        }

        while true {
            let char = getchar()

            // EOF - treat as Ctrl+D (interrupt)
            if char == -1 {
                return "\u{03}"
            }

            // Enter - submit input or insert newline in paste mode
            if char == 10 || char == 13 {
                if isPasteMode {
                    // In paste mode, enter inserts a newline
                    insertCharacter("\n")
                    print("", terminator: "")  // continuation prompt
                    fflush(stdout)
                    continue
                }
                print("")  // Move to next line
                resetCompletion()
                // Add to history if non-empty, single-line, and different from last
                if !currentInput.isEmpty && !currentInput.contains("\n") {
                    if commandHistory.isEmpty || commandHistory.last != currentInput {
                        commandHistory.append(currentInput)
                        if commandHistory.count > maxHistorySize {
                            commandHistory.removeFirst()
                        }
                    }
                }
                return currentInput
            }

            // Ctrl+Q - Graceful exit
            if char == 17 {
                return "\u{11}"
            }

            // Ctrl+C or Ctrl+D
            if char == 3 || char == 4 {
                return "\u{03}"
            }

            // Ctrl+B - Toggle debug mode
            if char == 2 {
                onDebugToggle?()
                continue
            }

            // Ctrl+U - Clear current input
            if char == 21 {
                // For multi-line input, move cursor up for each extra line,
                // then clear from cursor to end of screen
                let extraLines = InputHandler.lineCount(of: currentInput) - 1
                if extraLines > 0 {
                    print("\u{001B}[\(extraLines)A", terminator: "")
                }
                clearCurrentInput()
                print("\r\u{001B}[J", terminator: "")
                fflush(stdout)
                continue
            }

            // Tab - Auto-complete
            if char == 9 {
                handleTabCompletion()
                continue
            }

            // Escape sequence (arrow keys, etc.)
            if char == 27 {
                let next1 = getchar()
                if next1 == -1 { return "\u{03}" }  // EOF
                if next1 == 91 {  // '['
                    // Read CSI bytes until final byte (0x40-0x7E), max 16 bytes to avoid
                    // infinite loops on malformed terminal data
                    var csiBytes: [UInt8] = []
                    while csiBytes.count < 16 {
                        let b = getchar()
                        if b == -1 { return "\u{03}" }  // EOF
                        csiBytes.append(UInt8(b))
                        // Final byte is in range 0x40-0x7E (@ through ~)
                        if b >= 0x40 && b <= 0x7E {
                            break
                        }
                    }
                    let seq = InputHandler.parseCSISequence(csiBytes)
                    handleCSIAction(seq)
                } else if next1 == 98 {  // 'b' - ESC b: word left (Option+Left alternative)
                    handleWordLeft()
                } else if next1 == 102 {  // 'f' - ESC f: word right (Option+Right alternative)
                    handleWordRight()
                } else if next1 == 27 {
                    // Two consecutive ESC bytes — disambiguate double-ESC vs ESC + escape sequence
                    let followingByte: UInt8?
                    if InputHandler.hasPendingInput(timeoutMs: 50) {
                        let peek = getchar()
                        if peek == -1 { return "\u{03}" }
                        followingByte = UInt8(peek)
                    } else {
                        followingByte = nil
                    }

                    if InputHandler.isDoubleEscape(followingByte: followingByte) {
                        // Genuine double-ESC: push back peeked byte (if any) and clear input
                        if let fb = followingByte {
                            ungetc(Int32(fb), stdin)
                        }
                        performDoubleEscapeClear()
                    } else {
                        // Second ESC starts a CSI sequence (followingByte == 91, already consumed)
                        var csiBytes: [UInt8] = []
                        while csiBytes.count < 16 {
                            let b = getchar()
                            if b == -1 { return "\u{03}" }
                            csiBytes.append(UInt8(b))
                            if b >= 0x40 && b <= 0x7E { break }
                        }
                        let seq = InputHandler.parseCSISequence(csiBytes)
                        handleCSIAction(seq)
                    }
                }
                continue
            }

            // Backspace
            if char == 127 || char == 8 {
                handleBackspace()
                continue
            }

            // UTF-8 multi-byte characters
            if char > 127 {
                let startByte = UInt8(char)
                if let byteLen = InputHandler.utf8ByteLength(startByte: startByte), byteLen > 1 {
                    var bytes: [UInt8] = [startByte]
                    var eofEncountered = false
                    for _ in 1..<byteLen {
                        let continuation = getchar()
                        if continuation == -1 { eofEncountered = true; break }
                        bytes.append(UInt8(continuation))
                    }
                    if eofEncountered { return "\u{03}" }
                    if let scalar = String(bytes: bytes, encoding: .utf8) {
                        for c in scalar {
                            insertCharacter(c)
                        }
                    }
                }
                resetCompletion()
                continue
            }

            // Regular printable character
            if char >= 32 && char < 127 {
                let c = Character(UnicodeScalar(UInt8(char)))
                insertCharacter(c)
                resetCompletion()
            }
        }
    }
    
    // MARK: - CSI Sequence Dispatch

    private func handleCSIAction(_ seq: CSISequence) {
        switch seq {
        case .arrowUp:
            handleHistoryUp()
        case .arrowDown:
            handleHistoryDown()
        case .arrowRight:
            handleCursorRight()
        case .arrowLeft:
            handleCursorLeft()
        case .optionArrowLeft:
            handleWordLeft()
        case .optionArrowRight:
            handleWordRight()
        case .cmdArrowLeft:
            // Same as home: move to beginning of line
            handleLineStart()
        case .cmdArrowRight:
            // Same as end: move to end of line
            handleLineEnd()
        case .home:
            handleLineStart()
        case .end:
            handleLineEnd()
        case .delete:
            if cursorPosition < currentInput.count {
                let removeIndex = currentInput.index(currentInput.startIndex, offsetBy: cursorPosition)
                currentInput.remove(at: removeIndex)
                let remaining = String(currentInput[currentInput.index(currentInput.startIndex, offsetBy: cursorPosition)...])
                print(remaining + " ", terminator: "")
                let moveBack = remaining.count + 1
                if moveBack > 0 {
                    print("\u{001B}[\(moveBack)D", terminator: "")
                }
                fflush(stdout)
            }
        case .pasteStart:
            isPasteMode = true
        case .pasteEnd:
            isPasteMode = false
        case .shiftEnter:
            insertCharacter("\n")
            print("", terminator: "")
            fflush(stdout)
        case .unknown:
            break
        }
    }

    // MARK: - Cursor Movement

    private func handleCursorLeft() {
        guard cursorPosition > 0 else { return }
        cursorPosition -= 1
        print("\u{001B}[1D", terminator: "")
        fflush(stdout)
    }

    private func handleCursorRight() {
        guard cursorPosition < currentInput.count else { return }
        cursorPosition += 1
        print("\u{001B}[1C", terminator: "")
        fflush(stdout)
    }

    /// Move cursor to start of current line (Home / Cmd+Left)
    private func handleLineStart() {
        var moved = 0
        while cursorPosition > 0 {
            let idx = currentInput.index(currentInput.startIndex, offsetBy: cursorPosition - 1)
            if currentInput[idx] == "\n" { break }
            cursorPosition -= 1
            moved += 1
        }
        if moved > 0 {
            print("\u{001B}[\(moved)D", terminator: "")
            fflush(stdout)
        }
    }

    /// Move cursor to end of current line (End / Cmd+Right)
    private func handleLineEnd() {
        var moved = 0
        while cursorPosition < currentInput.count {
            let idx = currentInput.index(currentInput.startIndex, offsetBy: cursorPosition)
            if currentInput[idx] == "\n" { break }
            cursorPosition += 1
            moved += 1
        }
        if moved > 0 {
            print("\u{001B}[\(moved)C", terminator: "")
            fflush(stdout)
        }
    }

    // MARK: - Word Movement

    /// Characters that define word boundaries (non-word characters)
    private static let wordBoundaryChars = CharacterSet.alphanumerics.inverted

    /// Check if a character is a word character (alphanumeric)
    private func isWordCharacter(_ c: Character) -> Bool {
        return c.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
    }

    /// Move cursor to the beginning of the previous word (Option+Left / ESC b)
    private func handleWordLeft() {
        guard cursorPosition > 0 else { return }

        let chars = Array(currentInput)
        var newPos = cursorPosition

        // Step 1: Skip any non-word characters (spaces, punctuation) to the left
        while newPos > 0 && !isWordCharacter(chars[newPos - 1]) {
            newPos -= 1
        }

        // Step 2: Move through word characters until we hit the start of the word
        while newPos > 0 && isWordCharacter(chars[newPos - 1]) {
            newPos -= 1
        }

        let moved = cursorPosition - newPos
        if moved > 0 {
            cursorPosition = newPos
            print("\u{001B}[\(moved)D", terminator: "")
            fflush(stdout)
        }
    }

    /// Move cursor to the end of the next word (Option+Right / ESC f)
    private func handleWordRight() {
        guard cursorPosition < currentInput.count else { return }

        let chars = Array(currentInput)
        var newPos = cursorPosition

        // Step 1: Skip any non-word characters (spaces, punctuation) to the right
        while newPos < chars.count && !isWordCharacter(chars[newPos]) {
            newPos += 1
        }

        // Step 2: Move through word characters until we hit the end of the word
        while newPos < chars.count && isWordCharacter(chars[newPos]) {
            newPos += 1
        }

        let moved = newPos - cursorPosition
        if moved > 0 {
            cursorPosition = newPos
            print("\u{001B}[\(moved)C", terminator: "")
            fflush(stdout)
        }
    }
    
    private func insertCharacter(_ c: Character) {
        let index = currentInput.index(currentInput.startIndex, offsetBy: cursorPosition)
        currentInput.insert(c, at: index)
        cursorPosition += 1
        
        // Redraw from cursor position
        let remaining = String(currentInput[index...])
        print(remaining, terminator: "")
        
        // Move cursor back to correct position
        let moveBack = remaining.count - 1
        if moveBack > 0 {
            print("\u{001B}[\(moveBack)D", terminator: "")
        }
        fflush(stdout)
    }
    
    private func handleBackspace() {
        guard cursorPosition > 0 else { return }
        
        let removeIndex = currentInput.index(currentInput.startIndex, offsetBy: cursorPosition - 1)
        currentInput.remove(at: removeIndex)
        cursorPosition -= 1
        
        // Move cursor left, redraw remaining text, clear extra char
        print("\u{001B}[1D", terminator: "")
        let remaining = String(currentInput[currentInput.index(currentInput.startIndex, offsetBy: cursorPosition)...])
        print(remaining + " ", terminator: "")
        
        // Move cursor back to correct position
        let moveBack = remaining.count + 1
        print("\u{001B}[\(moveBack)D", terminator: "")
        fflush(stdout)
        resetCompletion()
    }
    
    // MARK: - Command History
    
    private func handleHistoryUp() {
        guard !commandHistory.isEmpty else { return }
        
        // Save current input when starting to browse history
        if historyIndex == commandHistory.count {
            tempInput = currentInput
        }
        
        guard historyIndex > 0 else { return }
        historyIndex -= 1
        replaceCurrentInput(with: commandHistory[historyIndex])
    }
    
    private func handleHistoryDown() {
        guard historyIndex < commandHistory.count else { return }
        
        historyIndex += 1
        if historyIndex == commandHistory.count {
            // Restore the original input
            replaceCurrentInput(with: tempInput)
        } else {
            replaceCurrentInput(with: commandHistory[historyIndex])
        }
    }
    
    private func replaceCurrentInput(with newInput: String) {
        // Clear current line
        if cursorPosition < currentInput.count {
            // Move cursor to end first
            let moveRight = currentInput.count - cursorPosition
            print("\u{001B}[\(moveRight)C", terminator: "")
        }
        // Clear entire input
        if !currentInput.isEmpty {
            print(String(repeating: "\u{001B}[1D \u{001B}[1D", count: currentInput.count), terminator: "")
        }
        
        // Set new input and display
        currentInput = newInput
        cursorPosition = newInput.count
        print(newInput, terminator: "")
        fflush(stdout)
    }
    
    /// Get current input for prompt restoration
    func getCurrentInput() -> String {
        return currentInput
    }
    
    /// Get the prompt string with cursor position for async restoration
    /// Returns the input text and moves cursor back to correct position
    func getPromptWithCursor() -> String {
        let moveBack = currentInput.count - cursorPosition
        if moveBack > 0 {
            return currentInput + "\u{001B}[\(moveBack)D"
        }
        return currentInput
    }
    
    /// Get current cursor position
    func getCursorPosition() -> Int {
        return cursorPosition
    }
    
    // MARK: - Tab Completion
    
    private func resetCompletion() {
        completionMatches = []
        completionIndex = 0
        lastCompletionPrefix = ""
    }
    
    private func handleTabCompletion() {
        guard currentInput.hasPrefix("/") else { return }
        
        // If we're already cycling through completions, use the original prefix
        // Otherwise, use current input as the new prefix
        let isNewCompletion = completionMatches.isEmpty || !completionMatches.contains(currentInput)
        
        if isNewCompletion {
            lastCompletionPrefix = currentInput
            completionIndex = 0
            
            let commands = getAvailableCommands?() ?? []
            completionMatches = commands.filter { $0.hasPrefix(lastCompletionPrefix) }
            
            // If no matches with current prefix, try just the slash
            if completionMatches.isEmpty && lastCompletionPrefix == "/" {
                completionMatches = commands
            }
        }
        
        guard !completionMatches.isEmpty else { return }
        
        // Get current completion
        let completion = completionMatches[completionIndex]
        
        // Replace current input with completion
        replaceCurrentInput(with: completion)
        
        // Move to next match for next tab press
        completionIndex = (completionIndex + 1) % completionMatches.count
    }

    // MARK: - CSI Sequence Parsing

    /// Parse bytes following ESC [ into a CSISequence
    static func parseCSISequence(_ bytes: [UInt8]) -> CSISequence {
        guard !bytes.isEmpty else {
            return .unknown([])
        }

        // Single byte sequences (final byte is the only byte)
        if bytes.count == 1 {
            switch bytes[0] {
            case 65: return .arrowUp      // A
            case 66: return .arrowDown    // B
            case 67: return .arrowRight   // C
            case 68: return .arrowLeft    // D
            case 72: return .home         // H
            case 70: return .end          // F
            default: return .unknown(bytes)
            }
        }

        // Convert bytes to string for multi-byte matching
        let str = String(bytes.map { Character(UnicodeScalar($0)) })

        // Delete: 3~ (bytes [51, 126])
        if str == "3~" { return .delete }

        // Bracketed paste start: 200~ (bytes [50, 48, 48, 126])
        if str == "200~" { return .pasteStart }

        // Bracketed paste end: 201~ (bytes [50, 48, 49, 126])
        if str == "201~" { return .pasteEnd }

        // Shift+Enter (kitty keyboard protocol): 13;2u
        if str == "13;2u" { return .shiftEnter }

        // Option+Arrow (modifier 3): 1;3D (left), 1;3C (right)
        if str == "1;3D" { return .optionArrowLeft }
        if str == "1;3C" { return .optionArrowRight }

        // Cmd+Arrow (modifier 9): 1;9D (left), 1;9C (right)
        if str == "1;9D" { return .cmdArrowLeft }
        if str == "1;9C" { return .cmdArrowRight }

        return .unknown(bytes)
    }

    // MARK: - UTF-8 Byte Length Detection

    /// Return the expected byte length for a UTF-8 character given its start byte.
    /// Returns nil for invalid start bytes (continuation bytes, overlong, out-of-range).
    static func utf8ByteLength(startByte: UInt8) -> Int? {
        switch startByte {
        case 0x00...0x7F:
            return 1
        case 0x80...0xBF:
            // Continuation bytes - not valid start bytes
            return nil
        case 0xC0...0xC1:
            // Overlong encodings
            return nil
        case 0xC2...0xDF:
            return 2
        case 0xE0...0xEF:
            return 3
        case 0xF0...0xF4:
            return 4
        default:
            // 0xF5-0xFF are invalid in UTF-8
            return nil
        }
    }

    // MARK: - Multi-line Text Utilities

    /// Count the number of lines in the given text.
    /// An empty string has 1 line. Each newline adds one more line.
    static func lineCount(of text: String) -> Int {
        if text.isEmpty { return 1 }
        // Number of lines = number of newlines + 1
        let newlineCount = text.filter { $0 == "\n" }.count
        return newlineCount + 1
    }

    /// Return the text of the line containing the cursor at the given position.
    /// Position is a character offset (0-based) into the text.
    /// When the cursor is on a newline character, it belongs to the line ending at that newline.
    static func currentLineText(in text: String, at cursorPosition: Int) -> String {
        if text.isEmpty { return "" }

        let chars = Array(text)
        let clampedPos = min(cursorPosition, chars.count)

        // When the cursor is on a newline, the line ends at that newline.
        // The line starts after the previous newline (or at 0).
        if clampedPos < chars.count && chars[clampedPos] == "\n" {
            // Search backward from clampedPos to find line start
            var lineStart = clampedPos
            while lineStart > 0 && chars[lineStart - 1] != "\n" {
                lineStart -= 1
            }
            return String(chars[lineStart..<clampedPos])
        }

        // For non-newline positions (or past end), find the surrounding line boundaries.
        // Determine effective position for scanning (handle cursor-past-end)
        let scanPos = clampedPos == chars.count ? max(clampedPos - 1, 0) : clampedPos

        // Walk backward to find line start
        var lineStart = scanPos
        while lineStart > 0 && chars[lineStart - 1] != "\n" {
            lineStart -= 1
        }

        // Walk forward to find line end
        var lineEnd = scanPos
        while lineEnd < chars.count && chars[lineEnd] != "\n" {
            lineEnd += 1
        }

        return String(chars[lineStart..<lineEnd])
    }

    /// Check if the given position is at a newline boundary.
    /// Returns true if the character at position is a newline, or the character
    /// immediately before position is a newline.
    static func isAtNewlineBoundary(in text: String, at position: Int) -> Bool {
        let chars = Array(text)
        guard !chars.isEmpty else { return false }

        // Check if character at position is a newline
        if position < chars.count && chars[position] == "\n" {
            return true
        }

        // Check if character just before position is a newline
        if position > 0 && position <= chars.count && chars[position - 1] == "\n" {
            return true
        }

        return false
    }

    /// Return the last line of the input text (text after the last newline).
    static func lastLineOfInput(_ text: String) -> String {
        if let lastNewline = text.lastIndex(of: "\n") {
            return String(text[text.index(after: lastNewline)...])
        }
        return text
    }

    // MARK: - Input Buffer State Management

    /// Clear the current input buffer and reset cursor position
    func clearCurrentInput() {
        currentInput = ""
        cursorPosition = 0
    }

    /// Set the input buffer to the given text and move cursor to end (for testing)
    func setInputForTesting(_ text: String) {
        currentInput = text
        cursorPosition = text.count
    }

    // MARK: - Double-ESC Input Clear

    /// Determine if two consecutive ESC bytes represent a genuine double-ESC gesture.
    ///
    /// After reading two ESC bytes (27, 27), we peek at the next byte to distinguish:
    /// - `nil` (no pending bytes): genuine double-ESC
    /// - `91` (`[`): second ESC starts a CSI sequence (e.g., ESC + arrow key) — NOT double-ESC
    /// - anything else: genuine double-ESC
    static func isDoubleEscape(followingByte: UInt8?) -> Bool {
        guard let byte = followingByte else {
            return true
        }
        return byte != 91  // 91 == ASCII '['
    }

    /// Check if stdin has pending bytes available within the given timeout.
    ///
    /// Uses POSIX `poll()` for non-blocking check. This distinguishes bare ESC
    /// keypresses from escape sequences (whose bytes arrive virtually instantly).
    static func hasPendingInput(timeoutMs: Int32) -> Bool {
        var pfd = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        let result = poll(&pfd, 1, timeoutMs)
        return result > 0
    }

    /// Clear input in response to a double-ESC gesture.
    ///
    /// Resets the input buffer and cursor, then redraws the prompt line
    /// including the "❯ " indicator.
    func performDoubleEscapeClear() {
        let extraLines = InputHandler.lineCount(of: currentInput) - 1
        if extraLines > 0 {
            print("\u{001B}[\(extraLines)A", terminator: "")
        }
        clearCurrentInput()
        print("\r\u{001B}[J❯ ", terminator: "")
        fflush(stdout)
    }
}
