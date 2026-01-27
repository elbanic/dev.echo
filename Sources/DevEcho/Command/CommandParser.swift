import Foundation

/// Protocol for parsing user input into commands
protocol CommandParserProtocol {
    func parse(input: String) -> Command
}

/// Parses user input strings into Command enum variants
/// Handles all command variants with proper parameter extraction
struct CommandParser: CommandParserProtocol {
    
    /// Parse user input into a Command
    /// - Parameter input: Raw user input string
    /// - Returns: Parsed Command enum variant
    func parse(input: String) -> Command {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Must start with /
        guard trimmed.hasPrefix("/") else {
            return .unknown(input: input)
        }
        
        // Split into command and arguments
        let components = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let commandPart = components.first else {
            return .unknown(input: input)
        }
        
        let command = String(commandPart).lowercased()
        let arguments = components.count > 1 ? String(components[1]) : nil
        
        switch command {
        // Command Mode commands
        case "/new":
            return .new
            
        case "/managekb":
            return .managekb
            
        case "/quit":
            return .quit
            
        // Transcribing Mode commands
        case "/chat":
            guard let content = arguments, !content.isEmpty else {
                return .unknown(input: input)
            }
            return .chat(content: content)
            
        case "/quick":
            guard let content = arguments, !content.isEmpty else {
                return .unknown(input: input)
            }
            return .quick(content: content)
            
        case "/stop":
            return .stop
            
        case "/save":
            return .save
            
        case "/mic":
            // Parse optional on/off argument
            if let arg = arguments?.lowercased() {
                if arg == "on" {
                    return .mic(enable: true)
                } else if arg == "off" {
                    return .mic(enable: false)
                }
            }
            return .mic(enable: nil)  // Toggle mode
            
        // KB Management Mode commands
        case "/list":
            return .list
            
        case "/more":
            // /more uses continuation token from previous list
            // Token is managed by the application, not passed as argument
            return .listMore(token: "")  // Empty token signals "use stored token"
            
        case "/remove":
            guard let name = arguments, !name.isEmpty else {
                return .unknown(input: input)
            }
            return .remove(name: name.trimmingCharacters(in: .whitespaces))
            
        case "/update":
            guard let args = arguments else {
                return .unknown(input: input)
            }
            let parsed = parsePathAndName(args)
            guard let fromPath = parsed.path, let name = parsed.name else {
                return .unknown(input: input)
            }
            return .update(fromPath: fromPath, name: name)
            
        case "/add":
            guard let args = arguments else {
                return .unknown(input: input)
            }
            let parsed = parsePathAndName(args)
            guard let fromPath = parsed.path, let name = parsed.name else {
                return .unknown(input: input)
            }
            return .add(fromPath: fromPath, name: name)
            
        case "/sync":
            return .sync
            
        default:
            return .unknown(input: input)
        }
    }
    
    /// Parse arguments for commands that take {from_path} {name}
    /// Handles quoted paths with spaces
    /// - Parameter args: The argument string after the command
    /// - Returns: Tuple with optional path and name
    private func parsePathAndName(_ args: String) -> (path: String?, name: String?) {
        let trimmed = args.trimmingCharacters(in: .whitespaces)
        
        // Handle quoted path (e.g., "/path/with spaces/file.md" name)
        if trimmed.hasPrefix("\"") {
            guard let endQuote = trimmed.dropFirst().firstIndex(of: "\"") else {
                return (nil, nil)
            }
            let pathEndIndex = trimmed.index(after: endQuote)
            let path = String(trimmed[trimmed.index(after: trimmed.startIndex)..<endQuote])
            
            let remaining = trimmed[pathEndIndex...].trimmingCharacters(in: .whitespaces)
            guard !remaining.isEmpty else {
                return (nil, nil)
            }
            return (path, remaining)
        }
        
        // Handle unquoted path (split by space)
        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else {
            return (nil, nil)
        }
        
        return (String(parts[0]), String(parts[1]))
    }
}
