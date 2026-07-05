import Foundation

/// Main setup wizard orchestrator
struct SetupWizard {
    let useDefault: Bool
    let skipCloud: Bool

    private let checker = DependencyChecker()
    private let configManager = ConfigManager()
    private var config = DevEchoConfig()

    // Default model name
    private let defaultOllamaModel = "llama3.2:3b"

    init(useDefault: Bool = false, skipCloud: Bool = false) {
        self.useDefault = useDefault
        self.skipCloud = skipCloud
    }

    /// Run the setup wizard
    mutating func run() {
        showWelcome()

        // Step 1: Ollama
        SetupProgress.showStep(1, total: 5, name: "Ollama")
        checkOllama()

        // Step 2: LLM Model
        SetupProgress.showStep(2, total: 5, name: "LLM Model")
        checkOllamaModel()

        // Step 3: MLX-Whisper
        SetupProgress.showStep(3, total: 5, name: "MLX-Whisper Model")
        checkWhisperModel()

        // Step 4: TTS Model
        SetupProgress.showStep(4, total: 5, name: "TTS Model (Qwen3-TTS)")
        checkTTSModel()

        // Step 5: AWS (optional)
        SetupProgress.showStep(5, total: 5, name: "AWS Cloud Features")
        if skipCloud {
            SetupProgress.showSkipped("Skipped (--skip-cloud)")
        } else {
            configureAWS()
        }

        // Save configuration
        saveConfiguration()

        // Show summary
        showSummary()
    }

    // MARK: - Welcome

    private func showWelcome() {
        print("""

        \u{001B}[1m🎙️  dev.echo Setup v1.0.0\u{001B}[0m

        This wizard will help you set up dev.echo for first-time use.
        It will check and configure the following dependencies:

          1. Ollama (local LLM server)
          2. LLM Model (llama3.2:3b)
          3. MLX-Whisper (speech-to-text)
          4. TTS Model (text-to-speech)
          5. AWS Cloud Features (optional)

        """)

        if useDefault {
            SetupProgress.showInfo("Running with --default (auto-accepting all defaults)")
        }

        if !useDefault {
            if !SetupPrompt.askYesNo("Continue with setup?", default: true) {
                print("\nSetup cancelled.\n")
                Darwin.exit(0)
            }
        }
    }

    // MARK: - Ollama Check

    private mutating func checkOllama() {
        let (installed, version) = checker.checkOllamaInstalled()

        if !installed {
            SetupProgress.showFailure("Ollama not installed")
            SetupProgress.showInfo("Install with: brew install ollama")
            SetupProgress.showInfo("Or download from: https://ollama.ai")

            if !useDefault && SetupPrompt.askYesNo("Install Ollama now via Homebrew?", default: true) {
                let exitCode = ShellExecutor.executeInteractive("brew", arguments: ["install", "ollama"])
                if exitCode == 0 {
                    SetupProgress.showSuccess("Ollama installed successfully")
                } else {
                    SetupProgress.showFailure("Failed to install Ollama")
                    return
                }
            } else {
                return
            }
        } else {
            SetupProgress.showSuccess("Ollama installed (v\(version ?? "unknown"))")
        }

        // Check if running
        let running = checker.checkOllamaRunning()
        if !running {
            SetupProgress.showWarning("Ollama service not running")

            if useDefault || SetupPrompt.askYesNo("Start Ollama service?", default: true) {
                SetupProgress.showProgress("Starting Ollama")

                // Start ollama serve in background
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["ollama", "serve"]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                    // Wait a moment for service to start
                    Thread.sleep(forTimeInterval: 2)

                    if checker.checkOllamaRunning() {
                        SetupProgress.showSuccess("Ollama service started")
                    } else {
                        SetupProgress.showWarning("Ollama may still be starting...")
                    }
                } catch {
                    SetupProgress.showFailure("Failed to start Ollama: \(error.localizedDescription)")
                }
            }
        } else {
            SetupProgress.showSuccess("Ollama running")
        }
    }

    // MARK: - Ollama Model

    private mutating func checkOllamaModel() {
        let hasModel = checker.checkOllamaModel(defaultOllamaModel)

        if hasModel {
            SetupProgress.showSuccess("Model \(defaultOllamaModel) installed")
            config.ollama.model = defaultOllamaModel
        } else {
            SetupProgress.showFailure("Model \(defaultOllamaModel) not found")

            let shouldDownload = useDefault || SetupPrompt.askYesNo(
                "Download \(defaultOllamaModel)? (~2GB)",
                default: true
            )

            if shouldDownload {
                print("")
                let exitCode = checker.pullOllamaModel(defaultOllamaModel)
                print("")

                if exitCode == 0 {
                    SetupProgress.showSuccess("Model \(defaultOllamaModel) installed")
                    config.ollama.model = defaultOllamaModel
                } else {
                    SetupProgress.showFailure("Failed to download model")

                    // Show available models as fallback
                    let available = checker.listOllamaModels()
                    if !available.isEmpty {
                        SetupProgress.showInfo("Available models: \(available.joined(separator: ", "))")
                        if let first = available.first {
                            config.ollama.model = first
                        }
                    }
                }
            } else {
                // Check for any existing model
                let available = checker.listOllamaModels()
                if let first = available.first {
                    SetupProgress.showInfo("Using existing model: \(first)")
                    config.ollama.model = first
                }
            }
        }
    }

    // MARK: - Whisper Model

    private mutating func checkWhisperModel() {
        let cached = checker.checkWhisperCached()

        if cached {
            SetupProgress.showSuccess("Model cached at ~/.cache/huggingface/...")
            config.models.whisperCached = true
        } else {
            SetupProgress.showWarning("Not cached")
            SetupProgress.showInfo("Model will be downloaded on first run (~300MB)")
            SetupProgress.showInfo("Requires Python backend: cd backend && pip install -e .")
            config.models.whisperCached = false
        }
    }

    // MARK: - TTS Model

    private mutating func checkTTSModel() {
        let cached = checker.checkTTSCached()

        if cached {
            SetupProgress.showSuccess("Model cached at ~/.cache/huggingface/...")
            config.models.ttsCached = true
        } else {
            SetupProgress.showWarning("Not cached")
            SetupProgress.showInfo("Model will be downloaded on first use (~1.5GB)")
            SetupProgress.showInfo("Used for /read mode text-to-speech")
            config.models.ttsCached = false
        }
    }

    // MARK: - AWS Configuration

    private mutating func configureAWS() {
        let shouldConfigure = useDefault ? false : SetupPrompt.askYesNo(
            "Configure AWS for cloud features?",
            default: false
        )

        if !shouldConfigure {
            SetupProgress.showSkipped("AWS not configured")
            config.aws = nil
            return
        }

        let wizard = AWSConfigWizard()
        config.aws = wizard.configure()
    }

    // MARK: - Save Configuration

    private mutating func saveConfiguration() {
        config.setupCompleted = Date()

        do {
            try configManager.save(config)
            SetupProgress.showInfo("Configuration saved to \(ConfigManager.configPath)")
        } catch {
            SetupProgress.showFailure("Failed to save configuration: \(error.localizedDescription)")
        }
    }

    // MARK: - Summary

    private func showSummary() {
        SetupProgress.printSeparator()
        print("\n\u{001B}[1mSetup Complete!\u{001B}[0m\n")

        // Ollama
        if checker.checkOllamaInstalled().installed && checker.checkOllamaRunning() {
            SetupProgress.showSuccess("Ollama (\(config.ollama.model))")
        } else {
            SetupProgress.showWarning("Ollama (needs configuration)")
        }

        // Whisper
        if config.models.whisperCached {
            SetupProgress.showSuccess("MLX-Whisper")
        } else {
            SetupProgress.showWarning("MLX-Whisper (will download on first run)")
        }

        // TTS
        if config.models.ttsCached {
            SetupProgress.showSuccess("TTS (Qwen3-TTS)")
        } else {
            SetupProgress.showWarning("TTS (will download on first use)")
        }

        // AWS
        if let aws = config.aws {
            var awsStatus = "AWS Cloud (\(aws.region)"
            if aws.s3Bucket != nil { awsStatus += ", S3" }
            if aws.knowledgeBaseId != nil { awsStatus += ", KB" }
            awsStatus += ")"
            SetupProgress.showSuccess(awsStatus)
        } else {
            SetupProgress.showSkipped("AWS Cloud (not configured)")
        }

        print("""

        \u{001B}[1mNext Steps:\u{001B}[0m

          1. Start the Python backend:
             cd backend && source .venv/bin/activate && python main.py

          2. Run dev.echo:
             devecho

        """)
    }
}
