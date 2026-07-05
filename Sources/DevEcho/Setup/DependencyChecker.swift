import Foundation

/// Dependency checker for setup wizard
/// Checks Ollama, model caches, and AWS CLI
struct DependencyChecker {
    // MARK: - Ollama

    /// Check if Ollama is installed
    /// - Returns: Tuple of (installed, version)
    func checkOllamaInstalled() -> (installed: Bool, version: String?) {
        guard ShellExecutor.commandExists("ollama") else {
            return (false, nil)
        }

        do {
            let output = try ShellExecutor.run("ollama", arguments: ["--version"])
            // Output format: "ollama version is 0.12.0" or "ollama version 0.3.0"
            var version = output.replacingOccurrences(of: "ollama version is ", with: "")
            version = version.replacingOccurrences(of: "ollama version ", with: "")
            return (true, version)
        } catch {
            return (true, nil)
        }
    }

    /// Check if Ollama service is running
    /// - Returns: true if running
    func checkOllamaRunning() -> Bool {
        // Check if ollama serve is responding
        let exitCode = ShellExecutor.execute("curl", arguments: [
            "-s", "-o", "/dev/null", "-w", "%{http_code}",
            "http://localhost:11434/api/tags"
        ])
        return exitCode == 0
    }

    /// Check if specific Ollama model is installed
    /// - Parameter name: Model name (e.g., "llama3.2:3b")
    /// - Returns: true if model exists
    func checkOllamaModel(_ name: String) -> Bool {
        do {
            let output = try ShellExecutor.run("ollama", arguments: ["list"])
            return output.contains(name)
        } catch {
            return false
        }
    }

    /// Get list of installed Ollama models
    /// - Returns: Array of model names
    func listOllamaModels() -> [String] {
        do {
            let output = try ShellExecutor.run("ollama", arguments: ["list"])
            var models: [String] = []
            for line in output.split(separator: "\n").dropFirst() { // Skip header
                if let name = line.split(separator: " ").first {
                    models.append(String(name))
                }
            }
            return models
        } catch {
            return []
        }
    }

    /// Start Ollama service via brew services
    /// - Throws: ShellError if failed
    func startOllamaService() throws {
        // First try to start via ollama serve in background
        let exitCode = ShellExecutor.execute("ollama", arguments: ["serve"])
        if exitCode != 0 {
            // Try brew services as fallback
            _ = try ShellExecutor.run("brew", arguments: ["services", "start", "ollama"])
        }
    }

    /// Pull an Ollama model
    /// - Parameter name: Model name to pull
    /// - Returns: Exit code (0 = success)
    func pullOllamaModel(_ name: String) -> Int32 {
        return ShellExecutor.executeInteractive("ollama", arguments: ["pull", name])
    }

    // MARK: - Model Cache (Hugging Face)

    /// Base path for Hugging Face cache
    private var huggingFaceCache: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.cache/huggingface/hub"
    }

    /// Check if MLX-Whisper model is cached
    /// - Returns: true if cached
    func checkWhisperCached() -> Bool {
        let cachePath = huggingFaceCache
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(atPath: cachePath) else {
            return false
        }

        // Look for mlx-community--whisper-* directory
        return contents.contains { $0.hasPrefix("models--mlx-community--whisper") }
    }

    /// Get Whisper model cache path if exists
    /// - Returns: Path to cached model or nil
    func getWhisperCachePath() -> String? {
        let cachePath = huggingFaceCache
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(atPath: cachePath) else {
            return nil
        }

        if let dir = contents.first(where: { $0.hasPrefix("models--mlx-community--whisper") }) {
            return "\(cachePath)/\(dir)"
        }
        return nil
    }

    /// Check if TTS model (Qwen3-TTS) is cached
    /// - Returns: true if cached
    func checkTTSCached() -> Bool {
        let cachePath = huggingFaceCache
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(atPath: cachePath) else {
            return false
        }

        // Look for mlx-community--Qwen3-TTS-* directory
        return contents.contains { $0.hasPrefix("models--mlx-community--Qwen3-TTS") }
    }

    /// Get TTS model cache path if exists
    /// - Returns: Path to cached model or nil
    func getTTSCachePath() -> String? {
        let cachePath = huggingFaceCache
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(atPath: cachePath) else {
            return nil
        }

        if let dir = contents.first(where: { $0.hasPrefix("models--mlx-community--Qwen3-TTS") }) {
            return "\(cachePath)/\(dir)"
        }
        return nil
    }

    // MARK: - AWS

    /// Check if AWS CLI is installed
    /// - Returns: Tuple of (installed, version)
    func checkAWSCLI() -> (installed: Bool, version: String?) {
        guard ShellExecutor.commandExists("aws") else {
            return (false, nil)
        }

        do {
            let output = try ShellExecutor.run("aws", arguments: ["--version"])
            // Output format: "aws-cli/2.x.x Python/3.x.x ..."
            if let version = output.split(separator: " ").first {
                let versionStr = version.replacingOccurrences(of: "aws-cli/", with: "")
                return (true, versionStr)
            }
            return (true, nil)
        } catch {
            return (true, nil)
        }
    }

    /// Check if AWS credentials are configured
    /// - Returns: true if valid credentials exist
    func checkAWSCredentials() -> Bool {
        let exitCode = ShellExecutor.execute("aws", arguments: ["sts", "get-caller-identity"])
        return exitCode == 0
    }

    /// Get AWS account info if credentials are valid
    /// - Returns: Account ID or nil
    func getAWSAccountId() -> String? {
        do {
            let output = try ShellExecutor.run("aws", arguments: ["sts", "get-caller-identity", "--query", "Account", "--output", "text"])
            return output.isEmpty ? nil : output
        } catch {
            return nil
        }
    }

    /// Get current AWS region
    /// - Returns: Region string or default
    func getAWSRegion() -> String {
        if let region = ProcessInfo.processInfo.environment["AWS_REGION"] {
            return region
        }
        if let region = ProcessInfo.processInfo.environment["AWS_DEFAULT_REGION"] {
            return region
        }
        do {
            let output = try ShellExecutor.run("aws", arguments: ["configure", "get", "region"])
            return output.isEmpty ? "us-west-2" : output
        } catch {
            return "us-west-2"
        }
    }

    // MARK: - Python Backend

    /// Check if Python virtual environment exists
    /// - Returns: true if .venv exists in backend directory
    func checkPythonVenv() -> Bool {
        let fm = FileManager.default
        let backendPath = fm.currentDirectoryPath + "/backend/.venv"
        return fm.fileExists(atPath: backendPath)
    }

    /// Check if required Python packages are installed
    /// - Returns: true if mlx-whisper is installed
    func checkPythonDependencies() -> Bool {
        let exitCode = ShellExecutor.execute("bash", arguments: [
            "-c", "cd backend && source .venv/bin/activate && pip show mlx-whisper > /dev/null 2>&1"
        ])
        return exitCode == 0
    }
}
