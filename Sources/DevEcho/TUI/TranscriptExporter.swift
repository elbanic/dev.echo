import Foundation

/// Result of a transcript export operation
enum TranscriptExportResult {
    case success(path: String)
    case failure(TranscriptExportError)
}

/// Errors that can occur during transcript export
enum TranscriptExportError: Error, CustomStringConvertible {
    case emptyTranscript
    case invalidPath(String)
    case permissionDenied(String)
    case diskFull
    case writeFailure(underlying: Error)
    
    var description: String {
        switch self {
        case .emptyTranscript:
            return "Cannot save empty transcript"
        case .invalidPath(let path):
            return "Invalid save path: \(path)"
        case .permissionDenied(let path):
            return "Permission denied: \(path)"
        case .diskFull:
            return "Disk is full, cannot save transcript"
        case .writeFailure(let error):
            return "Failed to write transcript: \(error.localizedDescription)"
        }
    }
}

/// Handles exporting transcripts to markdown files
struct TranscriptExporter {
    
    /// Default filename generator based on timestamp
    static func generateDefaultFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        return "transcript_\(timestamp).md"
    }
    
    /// Export transcript to a markdown file at the specified path
    /// - Parameters:
    ///   - transcript: The transcript to export
    ///   - path: The file path to save to
    /// - Returns: Result indicating success or failure
    static func export(_ transcript: Transcript, to path: String) -> TranscriptExportResult {
        // Check if transcript is empty
        guard !transcript.isEmpty else {
            return .failure(.emptyTranscript)
        }
        
        // Expand tilde in path
        let expandedPath = NSString(string: path).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)
        
        // Validate path
        let directory = url.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        
        if !FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            return .failure(.invalidPath(directory.path))
        }
        
        if !isDirectory.boolValue {
            return .failure(.invalidPath(directory.path))
        }
        
        // Check write permission
        if !FileManager.default.isWritableFile(atPath: directory.path) {
            return .failure(.permissionDenied(directory.path))
        }
        
        // Generate markdown content
        let markdown = transcript.toMarkdown()
        
        // Write to file
        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            return .success(path: expandedPath)
        } catch let error as NSError {
            if error.domain == NSCocoaErrorDomain && error.code == NSFileWriteOutOfSpaceError {
                return .failure(.diskFull)
            }
            return .failure(.writeFailure(underlying: error))
        }
    }
    
    /// Export transcript to the user's Documents directory with auto-generated filename
    /// - Parameter transcript: The transcript to export
    /// - Returns: Result indicating success or failure
    static func exportToDocuments(_ transcript: Transcript) -> TranscriptExportResult {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return .failure(.invalidPath("Documents directory not found"))
        }
        
        let filename = generateDefaultFilename()
        let fullPath = documentsPath.appendingPathComponent(filename).path
        
        return export(transcript, to: fullPath)
    }
    
    /// Export transcript to the current working directory with auto-generated filename
    /// - Parameter transcript: The transcript to export
    /// - Returns: Result indicating success or failure
    static func exportToCurrentDirectory(_ transcript: Transcript) -> TranscriptExportResult {
        let currentPath = FileManager.default.currentDirectoryPath
        let filename = generateDefaultFilename()
        let fullPath = (currentPath as NSString).appendingPathComponent(filename)
        
        return export(transcript, to: fullPath)
    }
}
