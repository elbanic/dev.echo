import Foundation

/// Header component displaying logo, version, model info, and current directory
struct HeaderView {
    let appName: String = "dev.echo"
    let version: String
    let modelInfo: String
    let currentDirectory: String
    
    init(
        version: String = "1.0.0",
        modelInfo: String = "MLX-Whisper · Ollama/Llama",
        currentDirectory: String? = nil
    ) {
        self.version = version
        self.modelInfo = modelInfo
        self.currentDirectory = currentDirectory ?? FileManager.default.currentDirectoryPath
    }
    
    /// Render the header as a string
    /// - Parameter width: Terminal width for formatting
    /// - Returns: Formatted header string
    func render(width: Int = 90) -> String {
        let logo = """
        ▐▛███▜▌   \(appName) v\(version)
        ▝▜█████▛▘  \(modelInfo)
          ▘▘ ▝▝    \(shortenPath(currentDirectory, maxLength: width - 15))
        """
        return logo
    }
    
    /// Shorten path if too long
    private func shortenPath(_ path: String, maxLength: Int) -> String {
        if path.count <= maxLength {
            return path
        }
        
        // Try to show ~/... format
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var displayPath = path
        if path.hasPrefix(home) {
            displayPath = "~" + path.dropFirst(home.count)
        }
        
        if displayPath.count <= maxLength {
            return displayPath
        }
        
        // Truncate with ellipsis
        let start = displayPath.prefix(10)
        let end = displayPath.suffix(maxLength - 13)
        return "\(start)...\(end)"
    }
}
