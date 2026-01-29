import Foundation

/// Terminal input handler
/// Manages raw mode input and special key handling
final class InputHandler {
    /// Callback for debug toggle (Ctrl+B)
    var onDebugToggle: (() -> Void)?
    
    /// Callback to get available commands for current mode
    var getAvailableCommands: (() -> [String])?
    
    /// Current input buffer (for display restoration)
    private(set) var currentInput: String = ""
    
    /// Cursor position within currentInput (0 = start, count = end)
    private var cursorPosition: Int = 0
    
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
        historyIndex = commandHistory.count
        tempInput = ""
        resetCompletion()
        
        // Set terminal to raw mode
        var oldTermios = termios()
        tcgetattr(STDIN_FILENO, &oldTermios)
        var newTermios = oldTermios
        newTermios.c_lflag &= ~UInt(ICANON | ECHO)
        tcsetattr(STDIN_FILENO, TCSANOW, &newTermios)
        
        defer {
            tcsetattr(STDIN_FILENO, TCSANOW, &oldTermios)
        }
        
        while true {
            let char = getchar()
            
            // Enter - submit input
            if char == 10 || char == 13 {
                print("")  // Move to next line
                resetCompletion()
                // Add to history if non-empty and different from last
                if !currentInput.isEmpty {
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
            
            // Tab - Auto-complete
            if char == 9 {
                handleTabCompletion()
                continue
            }
            
            // Escape sequence (arrow keys, etc.)
            if char == 27 {
                let next1 = getchar()
                if next1 == 91 {  // '['
                    let next2 = getchar()
                    switch next2 {
                    case 65:  // Up arrow
                        handleHistoryUp()
                    case 66:  // Down arrow
                        handleHistoryDown()
                    case 67:  // Right arrow
                        handleCursorRight()
                    case 68:  // Left arrow
                        handleCursorLeft()
                    default:
                        break
                    }
                }
                continue
            }
            
            // Backspace
            if char == 127 || char == 8 {
                handleBackspace()
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
}
