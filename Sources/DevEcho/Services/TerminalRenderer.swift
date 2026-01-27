import Foundation

/// Terminal rendering utilities
/// Handles display width calculation, text wrapping, and status line building
final class TerminalRenderer {
    private(set) var terminalWidth: Int = 80
    private(set) var terminalHeight: Int = 24
    
    init() {
        updateSize()
    }
    
    /// Update terminal dimensions
    func updateSize() {
        var ws = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0 {
            terminalWidth = Int(ws.ws_col)
            terminalHeight = Int(ws.ws_row)
        }
    }
    
    /// Calculate display width accounting for emoji (2 columns each)
    func displayWidth(_ str: String) -> Int {
        var width = 0
        for scalar in str.unicodeScalars {
            // Emoji and wide characters take 2 columns
            if scalar.value > 0x1F00 || (scalar.value >= 0x2600 && scalar.value <= 0x27BF) ||
               (scalar.value >= 0x1F300 && scalar.value <= 0x1F9FF) {
                width += 2
            } else {
                width += 1
            }
        }
        return width
    }
    
    /// Truncate string to fit display width
    func truncateToWidth(_ str: String, maxWidth: Int) -> String {
        var width = 0
        var result = ""
        for char in str {
            var charWidth = 0
            for scalar in char.unicodeScalars {
                if scalar.value > 0x1F00 || (scalar.value >= 0x2600 && scalar.value <= 0x27BF) ||
                   (scalar.value >= 0x1F300 && scalar.value <= 0x1F9FF) {
                    charWidth = 2
                } else {
                    charWidth = max(charWidth, 1)
                }
            }
            if width + charWidth + 3 > maxWidth {  // Leave room for "..."
                return result + "..."
            }
            width += charWidth
            result.append(char)
        }
        return result
    }
    
    /// Wrap string into multiple lines to fit display width
    func wrapToWidth(_ str: String, maxWidth: Int) -> [String] {
        var lines: [String] = []
        var currentLine = ""
        var currentWidth = 0
        
        for char in str {
            var charWidth = 0
            for scalar in char.unicodeScalars {
                if scalar.value > 0x1F00 || (scalar.value >= 0x2600 && scalar.value <= 0x27BF) ||
                   (scalar.value >= 0x1F300 && scalar.value <= 0x1F9FF) {
                    charWidth = 2
                } else {
                    charWidth = max(charWidth, 1)
                }
            }
            
            if currentWidth + charWidth > maxWidth {
                lines.append(currentLine)
                currentLine = String(char)
                currentWidth = charWidth
            } else {
                currentLine.append(char)
                currentWidth += charWidth
            }
        }
        
        if !currentLine.isEmpty {
            lines.append(currentLine)
        }
        
        return lines
    }
    
    /// Print content with optional right alignment, wrapping if needed
    func printWrapped(_ content: String, maxWidth: Int, rightAlign: Bool) {
        let contentWidth = displayWidth(content)
        
        if contentWidth <= maxWidth {
            // Fits on one line
            if rightAlign {
                let padding = max(0, terminalWidth - contentWidth)
                print(String(repeating: " ", count: padding) + content)
            } else {
                print(content)
            }
        } else {
            // Need to wrap
            let lines = wrapToWidth(content, maxWidth: maxWidth)
            for line in lines {
                if rightAlign {
                    let lineWidth = displayWidth(line)
                    let padding = max(0, terminalWidth - lineWidth)
                    print(String(repeating: " ", count: padding) + line)
                } else {
                    print(line)
                }
            }
        }
    }
    
    /// Build separator line
    var separator: String {
        String(repeating: "─", count: terminalWidth)
    }
    
    /// Clear screen and move cursor to home
    func clearScreen() {
        print("\u{001B}[2J\u{001B}[H", terminator: "")
        fflush(stdout)
    }
    
    /// Clear current line
    func clearLine() {
        print("\r\u{001B}[K", terminator: "")
        fflush(stdout)
    }
    
    /// Move cursor up one line and clear
    func clearPreviousLine() {
        print("\u{001B}[A\u{001B}[K", terminator: "")
    }
    
    /// Build the status line with mode, audio status, and available commands
    func buildStatusLine(mode: ApplicationMode, audioStatus: CaptureStatus, micStatus: CaptureStatus) -> String {
        let modeIcon = mode == .transcribing ? "🎙️" : (mode == .knowledgeBaseManagement ? "📚" : "🤖")
        let modeName = mode.displayName.replacingOccurrences(of: " Mode", with: "")
        
        if mode == .transcribing {
            let audioStatusText = audioStatus == .active ? "🔊ON" : "🔊OFF"
            let micStatusText = micStatus == .active ? "🎤ON" : "🎤OFF"
            return "\(modeIcon) \(modeName) │ \(audioStatusText) \(micStatusText) │ /chat /quick /mic /stop /save /quit"
        } else if mode == .knowledgeBaseManagement {
            return "\(modeIcon) \(modeName) │ /list /add /update /remove /sync /quit"
        } else {
            return "\(modeIcon) \(modeName) │ /new /managekb /quit"
        }
    }
}
