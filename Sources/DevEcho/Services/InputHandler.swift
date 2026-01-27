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
            
            // Backspace
            if char == 127 || char == 8 {
                if !currentInput.isEmpty {
                    currentInput.removeLast()
                    print("\u{001B}[1D \u{001B}[1D", terminator: "")
                    fflush(stdout)
                    resetCompletion()
                }
                continue
            }
            
            // Regular printable character
            if char >= 32 && char < 127 {
                let c = Character(UnicodeScalar(UInt8(char)))
                currentInput.append(c)
                print(String(c), terminator: "")
                fflush(stdout)
                resetCompletion()
            }
        }
    }
    
    /// Get current input for prompt restoration
    func getCurrentInput() -> String {
        return currentInput
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
        
        // Clear current input from display
        let clearCount = currentInput.count
        print(String(repeating: "\u{001B}[1D \u{001B}[1D", count: clearCount), terminator: "")
        
        // Update input and display
        currentInput = completion
        print(completion, terminator: "")
        fflush(stdout)
        
        // Move to next match for next tab press
        completionIndex = (completionIndex + 1) % completionMatches.count
    }
}
