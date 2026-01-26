import Foundation

/// Application operational modes
enum ApplicationMode: Equatable {
    case command              // Default mode - select which mode to enter
    case transcribing         // Audio capture and transcription active
    case knowledgeBaseManagement  // Managing KB documents
    
    var displayName: String {
        switch self {
        case .command:
            return "Command Mode"
        case .transcribing:
            return "Transcribing Mode"
        case .knowledgeBaseManagement:
            return "KB Management Mode"
        }
    }
    
    var exitHint: String {
        switch self {
        case .command:
            return "ctrl+q to exit"
        case .transcribing:
            return "/quit to return · ctrl+q to exit"
        case .knowledgeBaseManagement:
            return "/quit to return · ctrl+q to exit"
        }
    }
    
    /// Commands valid in this mode
    var validCommands: Set<CommandType> {
        switch self {
        case .command:
            return [.new, .managekb, .quit]
        case .transcribing:
            return [.chat, .quick, .stop, .save, .mic, .quit]
        case .knowledgeBaseManagement:
            return [.list, .add, .update, .remove, .quit]
        }
    }
    
    /// Check if a command is valid in this mode
    func isValidCommand(_ command: Command) -> Bool {
        return validCommands.contains(command.commandType)
    }
    
    /// Get available commands help text for this mode
    var availableCommandsHelp: String {
        switch self {
        case .command:
            return """
            /new      - Start transcribing (audio capture)
            /managekb - Enter knowledge base management
            /quit     - Exit application
            """
        case .transcribing:
            return """
            /chat {message}  - Query remote LLM with context
            /quick {message} - Query local LLM (Ollama)
            /stop            - Stop audio capture
            /save            - Save transcript to file
            /quit            - Return to command mode
            """
        case .knowledgeBaseManagement:
            return """
            /list                    - List all documents
            /add {path} {name}       - Add document from path
            /update {path} {name}    - Update existing document
            /remove {name}           - Remove document
            /quit                    - Return to command mode
            """
        }
    }
    
    /// Compact single-line command hints for inline display
    var compactCommandsHelp: String {
        switch self {
        case .command:
            return "/new  /managekb  /quit"
        case .transcribing:
            return "/chat {msg}  /quick {msg}  /stop  /save  /quit"
        case .knowledgeBaseManagement:
            return "/list  /add {path} {name}  /update {path} {name}  /remove {name}  /quit"
        }
    }
}

// MARK: - Command Type for Validation

/// Command type identifier for mode validation
enum CommandType: Hashable {
    case new, managekb, quit
    case chat, quick, stop, save, mic
    case list, add, update, remove
    case unknown
}

extension Command {
    /// Get the command type for mode validation
    var commandType: CommandType {
        switch self {
        case .new: return .new
        case .managekb: return .managekb
        case .quit: return .quit
        case .chat: return .chat
        case .quick: return .quick
        case .stop: return .stop
        case .save: return .save
        case .mic: return .mic
        case .list: return .list
        case .add: return .add
        case .update: return .update
        case .remove: return .remove
        case .unknown: return .unknown
        }
    }
}

// MARK: - Mode State Machine

/// Result of a mode transition attempt
enum ModeTransitionResult: Equatable {
    case success(newMode: ApplicationMode)
    case invalidCommand(reason: String)
    case noTransition
}

/// State machine for application mode transitions
/// Validates: Requirements 2.1, 2.2, 3.7, 4.6
struct ApplicationModeStateMachine {
    private(set) var currentMode: ApplicationMode
    
    init(initialMode: ApplicationMode = .command) {
        self.currentMode = initialMode
    }
    
    /// Attempt to transition based on a command
    /// Returns the result of the transition attempt
    mutating func transition(with command: Command) -> ModeTransitionResult {
        // Handle unknown commands
        if case .unknown(let input) = command {
            return .invalidCommand(reason: "Unknown command: \(input)")
        }
        
        // Validate command is allowed in current mode
        guard currentMode.isValidCommand(command) else {
            return .invalidCommand(
                reason: "Command '\(command)' not available in \(currentMode.displayName)"
            )
        }
        
        // Process mode-changing commands
        switch (currentMode, command) {
        // Command Mode transitions
        case (.command, .new):
            currentMode = .transcribing
            return .success(newMode: .transcribing)
            
        case (.command, .managekb):
            currentMode = .knowledgeBaseManagement
            return .success(newMode: .knowledgeBaseManagement)
            
        // Transcribing Mode → Command Mode (Requirement 3.7)
        case (.transcribing, .quit):
            currentMode = .command
            return .success(newMode: .command)
            
        // KB Management Mode → Command Mode (Requirement 4.6)
        case (.knowledgeBaseManagement, .quit):
            currentMode = .command
            return .success(newMode: .command)
            
        // Command Mode quit exits app (handled separately)
        case (.command, .quit):
            return .noTransition
            
        // All other valid commands don't change mode
        default:
            return .noTransition
        }
    }
    
    /// Check if a command would be valid without executing it
    func canExecute(_ command: Command) -> Bool {
        if case .unknown = command {
            return false
        }
        return currentMode.isValidCommand(command)
    }
    
    /// Get the target mode for a mode-changing command, if any
    func targetMode(for command: Command) -> ApplicationMode? {
        switch (currentMode, command) {
        case (.command, .new):
            return .transcribing
        case (.command, .managekb):
            return .knowledgeBaseManagement
        case (.transcribing, .quit), (.knowledgeBaseManagement, .quit):
            return .command
        default:
            return nil
        }
    }
}
