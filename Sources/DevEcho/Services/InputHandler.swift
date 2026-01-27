import Foundation

/// Terminal input handler
/// Manages raw mode input and special key handling
final class InputHandler {
    /// Callback for debug toggle (Ctrl+B)
    var onDebugToggle: (() -> Void)?
    
    /// Current input buffer (for display restoration)
    private(set) var currentInput: String = ""
    
    /// Read input from terminal in raw mode
    /// Returns the input string, or special control sequences
    /// - "\u{11}" for Ctrl+Q (quit)
    /// - "\u{03}" for Ctrl+C/Ctrl+D (interrupt)
    func readInput() -> String {
        currentInput = ""
        
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
            
            // Backspace
            if char == 127 || char == 8 {
                if !currentInput.isEmpty {
                    currentInput.removeLast()
                    print("\u{001B}[1D \u{001B}[1D", terminator: "")
                    fflush(stdout)
                }
                continue
            }
            
            // Regular printable character
            if char >= 32 && char < 127 {
                let c = Character(UnicodeScalar(UInt8(char)))
                currentInput.append(c)
                print(String(c), terminator: "")
                fflush(stdout)
            }
        }
    }
    
    /// Get current input for prompt restoration
    func getCurrentInput() -> String {
        return currentInput
    }
}
