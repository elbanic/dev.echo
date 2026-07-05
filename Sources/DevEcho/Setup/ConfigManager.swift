import Foundation

// MARK: - Configuration Models

/// Main configuration structure
struct DevEchoConfig: Codable {
    var ollama: OllamaConfig
    var models: ModelsConfig
    var aws: AWSConfig?
    var setupCompleted: Date

    init(
        ollama: OllamaConfig = OllamaConfig(),
        models: ModelsConfig = ModelsConfig(),
        aws: AWSConfig? = nil,
        setupCompleted: Date = Date()
    ) {
        self.ollama = ollama
        self.models = models
        self.aws = aws
        self.setupCompleted = setupCompleted
    }
}

/// Ollama configuration
struct OllamaConfig: Codable {
    var model: String
    var host: String

    init(model: String = "llama3.2:3b", host: String = "http://localhost:11434") {
        self.model = model
        self.host = host
    }
}

/// Model cache configuration
struct ModelsConfig: Codable {
    var whisperCached: Bool
    var ttsCached: Bool
    var whisperModel: String

    init(
        whisperCached: Bool = false,
        ttsCached: Bool = false,
        whisperModel: String = "mlx-community/whisper-small-mlx"
    ) {
        self.whisperCached = whisperCached
        self.ttsCached = ttsCached
        self.whisperModel = whisperModel
    }
}

/// AWS cloud configuration
struct AWSConfig: Codable {
    var region: String
    var s3Bucket: String?
    var knowledgeBaseId: String?

    init(region: String = "us-west-2", s3Bucket: String? = nil, knowledgeBaseId: String? = nil) {
        self.region = region
        self.s3Bucket = s3Bucket
        self.knowledgeBaseId = knowledgeBaseId
    }
}

// MARK: - Config Manager

/// Configuration file manager
struct ConfigManager {
    /// Default config directory
    static var configDirectory: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/devecho"
    }

    /// Default config file path
    static var configPath: String {
        return "\(configDirectory)/config.json"
    }

    /// Check if config file exists
    func configExists() -> Bool {
        return FileManager.default.fileExists(atPath: Self.configPath)
    }

    /// Load configuration from file
    /// - Returns: Config or nil if not found
    func load() -> DevEchoConfig? {
        guard configExists() else { return nil }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: Self.configPath))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(DevEchoConfig.self, from: data)
        } catch {
            return nil
        }
    }

    /// Save configuration to file
    /// - Parameter config: Configuration to save
    /// - Throws: Error on write failure
    func save(_ config: DevEchoConfig) throws {
        let fm = FileManager.default

        // Create config directory if needed
        if !fm.fileExists(atPath: Self.configDirectory) {
            try fm.createDirectory(atPath: Self.configDirectory, withIntermediateDirectories: true)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(config)
        try data.write(to: URL(fileURLWithPath: Self.configPath))
    }

    /// Delete configuration file
    func delete() throws {
        if configExists() {
            try FileManager.default.removeItem(atPath: Self.configPath)
        }
    }

    /// Get config age in days
    func configAge() -> Int? {
        guard let config = load() else { return nil }
        let days = Calendar.current.dateComponents([.day], from: config.setupCompleted, to: Date()).day
        return days
    }
}
