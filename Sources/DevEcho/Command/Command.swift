import Foundation

/// All available commands in dev.echo CLI
/// Supports Command Mode, Transcribing Mode, and KB Management Mode operations
enum Command: Equatable {
    // Command Mode
    case new                                    // /new - Start transcribing
    case managekb                               // /managekb - Enter KB management mode
    case quit                                   // /quit - Exit application or return to command mode
    
    // Transcribing Mode
    case chat(content: String)                  // /chat {contents} - Query remote LLM
    case quick(content: String)                 // /quick {contents} - Query local LLM
    case stop                                   // /stop - Stop audio capture
    case save                                   // /save - Save transcript
    case mic                                    // /mic - Toggle microphone capture
    
    // KB Management Mode
    case list                                   // /list - List KB documents
    case remove(name: String)                   // /remove {name} - Remove document
    case update(fromPath: String, name: String) // /update {from_path} {name} - Update document
    case add(fromPath: String, name: String)    // /add {from_path} {name} - Add document
    
    // Error case
    case unknown(input: String)                 // Unrecognized command
}

extension Command: CustomStringConvertible {
    var description: String {
        switch self {
        case .new:
            return "/new"
        case .managekb:
            return "/managekb"
        case .quit:
            return "/quit"
        case .chat(let content):
            return "/chat \(content)"
        case .quick(let content):
            return "/quick \(content)"
        case .stop:
            return "/stop"
        case .save:
            return "/save"
        case .mic:
            return "/mic"
        case .list:
            return "/list"
        case .remove(let name):
            return "/remove \(name)"
        case .update(let fromPath, let name):
            return "/update \(fromPath) \(name)"
        case .add(let fromPath, let name):
            return "/add \(fromPath) \(name)"
        case .unknown(let input):
            return "unknown: \(input)"
        }
    }
}
