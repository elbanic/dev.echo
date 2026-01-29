import ArgumentParser
import Foundation
import Logging

/// dev.echo - A developer-focused AI partner for real-time audio transcription and context-aware assistance
/// Requirements: 1.1, 1.2 - CLI Application Lifecycle
@main
struct DevEcho: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dev.echo",
        abstract: "A developer-focused AI partner that captures and transcribes audio in real-time",
        version: "1.0.0"
    )
    
    @Flag(name: .long, help: "Enable debug logging")
    var debug = false
    
    func run() throws {
        var logger = Logger(label: "dev.echo")
        logger.logLevel = debug ? .debug : .info
        
        logger.info("dev.echo v1.0.0 starting...")
        
        let app = Application(logger: logger, debug: debug)
        
        // Set up signal handlers for graceful shutdown (Requirement 1.2)
        signal(SIGINT) { _ in
            print("\n\nGoodbye! 👋\n")
            Darwin.exit(0)
        }
        
        app.run()
    }
}

/// Main application class managing the interactive CLI
/// Requirements: 1.1, 1.2, 1.3, 1.4 - CLI Application Lifecycle
final class Application {
    private var logger: Logger
    private let tui: TUIEngine
    private let parser: CommandParser
    private var stateMachine: ApplicationModeStateMachine
    private var isRunning = true
    private var ipcClient: IPCClient
    
    // Extracted services
    private let renderer: TerminalRenderer
    private let inputHandler: InputHandler
    private let kbService: KBService
    private let llmService: LLMService
    
    private var debug: Bool {
        didSet {
            Task { await ipcClient.setDebug(debug) }
            if #available(macOS 13.0, *) {
                if let engine = audioEngine as? AudioCaptureEngine {
                    engine.setDebug(debug)
                }
            }
            logger.logLevel = debug ? .debug : .info
            print(debug ? "\r\u{001B}[K🐛 Debug mode ON" : "\r\u{001B}[K🐛 Debug mode OFF")
        }
    }
    
    // Audio capture engine (macOS 13.0+ only)
    private var audioEngine: Any?
    
    // IPC listening task
    private var ipcListeningTask: Task<Void, Never>?
    
    // Transcript line aggregation
    private var lastTranscriptSource: AudioSource?
    private var lastTranscriptLine: String = ""
    private var lastTranscriptTimestamp: String = ""
    private var lastHeaderTime: Date = Date.distantPast
    private let headerInterval: TimeInterval = 7.0
    
    var currentMode: ApplicationMode {
        stateMachine.currentMode
    }
    
    init(logger: Logger, debug: Bool = false) {
        self.logger = logger
        self.debug = debug
        self.tui = TUIEngine()
        self.parser = CommandParser()
        self.stateMachine = ApplicationModeStateMachine(initialMode: .command)
        self.ipcClient = IPCClient(debug: debug)
        
        // Initialize services
        self.renderer = TerminalRenderer()
        self.inputHandler = InputHandler()
        self.kbService = KBService(ipcClient: ipcClient)
        self.llmService = LLMService(ipcClient: ipcClient)
        
        // Set up debug toggle callback
        inputHandler.onDebugToggle = { [weak self] in
            self?.debug.toggle()
        }
        
        // Set up tab completion callback
        inputHandler.getAvailableCommands = { [weak self] in
            guard let self = self else { return [] }
            return self.currentMode.availableCommands
        }
        
        // Initialize audio engine if available
        if #available(macOS 13.0, *) {
            let engine = AudioCaptureEngine(ipcClient: ipcClient, debug: debug)
            engine.onStatusUpdate = { [weak self] source, status in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    switch source {
                    case .system:
                        self.tui.statusBar.setAudioStatus(status)
                    case .microphone:
                        self.tui.statusBar.setMicStatus(status)
                    }
                    if self.currentMode == .transcribing {
                        let statusIcon = source == .system ? "🔊" : "🎤"
                        let statusText = status == .active ? "ON" : "--"
                        print("\r\u{001B}[K   \(statusIcon) \(statusText)")
                        print("❯ \(self.inputHandler.getPromptWithCursor())", terminator: "")
                        fflush(stdout)
                    }
                }
            }
            engine.onPermissionUpdate = { [weak self] permissions in
                DispatchQueue.main.async {
                    self?.tui.statusBar.setPermissions(
                        screenCapture: permissions.screenCapture,
                        microphone: permissions.microphone
                    )
                }
            }
            self.audioEngine = engine
        }
    }
    
    // MARK: - Main Loop
    
    // Flag to skip status bar in main loop when transitioning to transcribing mode
    private var skipNextStatusBar = false
    
    func run() {
        showWelcome()
        
        while isRunning {
            if !skipNextStatusBar {
                printStatusAndPrompt()
            } else {
                skipNextStatusBar = false
                print("❯ ", terminator: "")
                fflush(stdout)
            }
            
            let input = inputHandler.readInput()
            
            // Handle special keys
            if input == "\u{11}" || input == "\u{03}" || input == "\u{04}" {
                gracefulShutdown()
                continue
            }
            
            if input.isEmpty { continue }
            
            let command = parser.parse(input: input)
            handleCommand(command)
        }
        
        print("\nGoodbye! 👋\n")
    }
    
    private func printStatusAndPrompt() {
        print(renderer.separator)
        
        // Get audio status directly from engine if available
        var audioStatus = tui.statusBar.audioStatus
        var micStatus = tui.statusBar.micStatus
        
        if #available(macOS 13.0, *) {
            if let engine = audioEngine as? AudioCaptureEngine {
                audioStatus = engine.systemAudioStatus
                micStatus = engine.microphoneStatus
            }
        }
        
        let statusLine = renderer.buildStatusLine(
            mode: currentMode,
            audioStatus: audioStatus,
            micStatus: micStatus
        )
        print(statusLine)
        print("❯ ", terminator: "")
        fflush(stdout)
    }
    
    private func gracefulShutdown() {
        print("\n\n⏳ Shutting down...")
        if currentMode == .transcribing { stopAudioCapture() }
        Task { await ipcClient.disconnect() }
        isRunning = false
    }
    
    private func showWelcome() {
        print("""
        
        ▐▛███▜▌   dev.echo v1.0.0
         ▗▗ ▗▗    MLX-Whisper · Ollama/Llama
        ▐█████▌
        
        Welcome to dev.echo! Commands are shown in the status bar below.
        
        """)
    }
    
    // MARK: - Command Handling
    
    private func handleCommand(_ command: Command) {
        let transitionResult = stateMachine.transition(with: command)
        
        switch transitionResult {
        case .invalidCommand(let reason):
            print("❌ \(reason)")
            print("   Available commands: \(currentMode.compactCommandsHelp)")
            return
        case .success(let newMode):
            handleModeTransition(to: newMode, via: command)
            return
        case .noTransition:
            break
        }
        
        switch currentMode {
        case .command:
            executeCommandModeAction(command)
        case .transcribing:
            executeTranscribingModeAction(command)
        case .knowledgeBaseManagement:
            executeKBModeAction(command)
        }
    }
    
    private func handleModeTransition(to newMode: ApplicationMode, via command: Command) {
        switch (command, newMode) {
        case (.new, .transcribing):
            tui.setMode(.transcribing)
            tui.startNewTranscript()
            skipNextStatusBar = true  // Skip status bar in main loop, will print after init
            print("🎙️  Transcribing Mode")
            print("   Type /chat or /quick to query LLM with context")
            print("   Type /stop to pause, /save to export, /quit to return\n")
            // Start audio capture - status bar will be printed after all init messages
            startAudioCapture(showModeHeader: true)
            
        case (.managekb, .knowledgeBaseManagement):
            tui.setMode(.knowledgeBaseManagement)
            print("📚 KB Management Mode")
            print("   Type /list to see documents, /add, /update, /remove to manage")
            print("   Type /quit to return to command mode\n")
            
        case (.quit, .command):
            stopAudioCapture()
            tui.statusBar.setAudioStatus(.inactive)
            tui.statusBar.setMicStatus(.inactive)
            tui.endTranscript()
            tui.setMode(.command)
            print("↩️  Returned to Command Mode\n")
            
        default:
            break
        }
    }
    
    // MARK: - Command Mode Actions
    
    private func executeCommandModeAction(_ command: Command) {
        if case .quit = command {
            isRunning = false
        }
    }
    
    // MARK: - Transcribing Mode Actions
    
    private func executeTranscribingModeAction(_ command: Command) {
        switch command {
        case .chat(let content):
            executeCloudLLMQuery(content: content)
        case .quick(let content):
            executeLLMQuery(type: "quick", content: content)
        case .stop:
            skipNextStatusBar = true
            executeStop()
        case .save:
            print("\n💾 Saving transcript...")
            let result = tui.saveTranscriptToDocuments()
            switch result {
            case .success(let path):
                print("   ✅ Transcript saved to: \(path)\n")
            case .failure(let error):
                print("   ⚠️  \(error.description)\n")
            }
        case .mic(let enable):
            setMicrophoneCapture(enable: enable)
        default:
            break
        }
    }
    
    // MARK: - KB Mode Actions
    
    private func executeKBModeAction(_ command: Command) {
        switch command {
        case .list:
            executeKBList(continuationToken: nil)
        case .listMore:
            if let token = kbService.continuationToken {
                executeKBList(continuationToken: token)
            } else {
                print("\n   ⚠️  No more documents to show. Use /list to start from the beginning.\n")
            }
        case .add(let fromPath, let name):
            executeKBAdd(fromPath: fromPath, name: name)
        case .update(let fromPath, let name):
            executeKBUpdate(fromPath: fromPath, name: name)
        case .remove(let name):
            executeKBRemove(name: name)
        case .sync:
            executeKBSync()
        default:
            break
        }
    }

    // MARK: - Audio Capture
    
    private func startAudioCapture(showModeHeader: Bool = false) {
        if #available(macOS 13.0, *) {
            guard let engine = audioEngine as? AudioCaptureEngine else {
                print("   ⚠️  Audio engine not available")
                return
            }
            
            Task {
                do {
                    do {
                        try await ipcClient.connect()
                        print("\r\u{001B}[K   ✅ Connected to Python backend")
                        fflush(stdout)
                        startIPCListening()
                        await checkKBConnectivity()
                    } catch {
                        print("\r\u{001B}[K   ⚠️  Python backend not running: \(error.localizedDescription)")
                        print("   💡 Start backend with: cd backend && source .venv/bin/activate && python main.py")
                        fflush(stdout)
                    }
                    
                    let permissions = await engine.requestPermissions()
                    if !permissions.screenCapture {
                        print("\r\u{001B}[K   ⚠️  Screen capture permission required for system audio")
                        fflush(stdout)
                    }
                    if !permissions.microphone {
                        print("\r\u{001B}[K   ⚠️  Microphone permission required")
                        fflush(stdout)
                    }
                    
                    try await engine.startCapture()
                    
                    // Update statusBar with engine's actual status
                    self.tui.statusBar.setAudioStatus(engine.systemAudioStatus)
                    self.tui.statusBar.setMicStatus(engine.microphoneStatus)
                    
                    print("\r\u{001B}[K   ✅ Audio capture started")
                    fflush(stdout)
                    
                    // Print status bar after all initialization is complete
                    if showModeHeader {
                        print(self.renderer.separator)
                        let statusLine = self.renderer.buildStatusLine(
                            mode: .transcribing,
                            audioStatus: engine.systemAudioStatus,
                            micStatus: engine.microphoneStatus
                        )
                        print(statusLine)
                    }
                    print("❯ \(self.inputHandler.getPromptWithCursor())", terminator: "")
                    fflush(stdout)
                } catch {
                    print("\r\u{001B}[K   ❌ Failed to start audio capture: \(error.localizedDescription)")
                    print("❯ \(self.inputHandler.getPromptWithCursor())", terminator: "")
                    fflush(stdout)
                }
            }
        } else {
            print("   ⚠️  Audio capture requires macOS 13.0+")
            tui.statusBar.setAudioStatus(.inactive)
            tui.statusBar.setMicStatus(.inactive)
        }
    }
    
    private func checkKBConnectivity() async {
        do {
            let syncStatus = try await kbService.getSyncStatus()
            tui.statusBar.setKBStatus(from: syncStatus)
            print("\r\u{001B}[K   \(syncStatus.statusIcon) KB: \(syncStatus.status) (\(syncStatus.documentCount) documents)")
            print("❯ \(self.inputHandler.getPromptWithCursor())", terminator: "")
            fflush(stdout)
        } catch {
            tui.statusBar.setKBStatus(isConnected: false, status: "UNKNOWN", documentCount: 0)
            logger.debug("KB connectivity check failed: \(error.localizedDescription)")
        }
    }
    
    private func startIPCListening() {
        ipcListeningTask = Task {
            await ipcClient.startListening { [weak self] transcription in
                guard let self = self else { return }
                
                let source = AudioSource(rawValue: transcription.source) ?? .system
                let entry = TranscriptEntry(source: source, text: transcription.text)
                self.tui.appendTranscript(entry: entry)
                
                self.renderer.updateSize()
                
                let icon = source.icon
                let timestamp = self.formatTimestamp(transcription.timestamp)
                let now = Date()
                
                let timeSinceLastHeader = now.timeIntervalSince(self.lastHeaderTime)
                let sourceChanged = source != self.lastTranscriptSource
                let shouldShowHeader = sourceChanged || timeSinceLastHeader >= self.headerInterval
                
                let headerWidth = "\(icon) [\(timestamp)] ".count
                let maxLineWidth = self.renderer.terminalWidth - 2
                
                print("\r\u{001B}[K", terminator: "")
                
                if shouldShowHeader {
                    self.lastTranscriptSource = source
                    self.lastTranscriptTimestamp = timestamp
                    self.lastTranscriptLine = transcription.text
                    self.lastHeaderTime = now
                    
                    let content = "\(icon) [\(timestamp)] \(transcription.text)"
                    self.renderer.printWrapped(content, maxWidth: maxLineWidth, rightAlign: source == .microphone)
                } else {
                    let newText = self.lastTranscriptLine + " " + transcription.text
                    let currentLineLength = headerWidth + self.lastTranscriptLine.count
                    
                    if currentLineLength + transcription.text.count + 1 <= maxLineWidth {
                        self.lastTranscriptLine = newText
                        let content = "\(icon) [\(self.lastTranscriptTimestamp)] \(newText)"
                        print("\u{001B}[A\u{001B}[K", terminator: "")
                        self.renderer.printWrapped(content, maxWidth: maxLineWidth, rightAlign: source == .microphone)
                    } else {
                        self.lastTranscriptLine = transcription.text
                        let indent = String(repeating: " ", count: headerWidth)
                        let content = indent + transcription.text
                        self.renderer.printWrapped(content, maxWidth: maxLineWidth, rightAlign: source == .microphone)
                    }
                }
                
                print("❯ \(self.inputHandler.getPromptWithCursor())", terminator: "")
                fflush(stdout)
            }
        }
    }
    
    private func formatTimestamp(_ timestamp: Double) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
    
    private func stopAudioCapture() {
        ipcListeningTask?.cancel()
        ipcListeningTask = nil
        // Keep IPC connection alive for /chat and /quick commands
        
        if #available(macOS 13.0, *) {
            guard let engine = audioEngine as? AudioCaptureEngine else { return }
            Task { await engine.stopCapture() }
        }
    }
    
    private func executeStop() {
        ipcListeningTask?.cancel()
        ipcListeningTask = nil
        
        if #available(macOS 13.0, *) {
            guard let engine = audioEngine as? AudioCaptureEngine else {
                print("\n⚠️  Audio engine not available")
                printCurrentStatusBar()
                return
            }
            
            Task {
                await engine.stopCapture()
                print("\n⏹️  Audio capture stopped.")
                self.printCurrentStatusBar()
            }
        } else {
            print("\n⏹️  Audio capture stopped.")
            printCurrentStatusBar()
        }
    }
    
    private func setMicrophoneCapture(enable: Bool?) {
        if #available(macOS 13.0, *) {
            guard let engine = audioEngine as? AudioCaptureEngine else {
                print("\n⚠️  Audio engine not available\n")
                return
            }
            
            // Skip status bar in main loop - we'll print it after mic toggle
            skipNextStatusBar = true
            
            Task {
                // Use microphoneStatus (actual capture state) instead of microphoneEnabled
                let currentlyActive = engine.microphoneStatus == .active
                let shouldEnable: Bool
                
                if let enable = enable {
                    shouldEnable = enable
                    if shouldEnable == currentlyActive {
                        let state = shouldEnable ? "enabled" : "disabled"
                        print("\n🎤 Microphone capture already \(state)")
                        self.printCurrentStatusBar()
                        return
                    }
                } else {
                    shouldEnable = !currentlyActive
                }
                
                // Set microphone to desired state
                let enabled = await engine.setMicrophoneEnabled(shouldEnable)
                if enabled {
                    print("\n🎤 Microphone capture enabled")
                } else {
                    print("\n🎤 Microphone capture disabled")
                }
                self.printCurrentStatusBar()
            }
        } else {
            print("\n⚠️  Audio capture requires macOS 13.0+\n")
        }
    }
    
    /// Print current status bar with actual engine status
    private func printCurrentStatusBar() {
        var audioStatus: CaptureStatus = .inactive
        var micStatus: CaptureStatus = .inactive
        
        if #available(macOS 13.0, *) {
            if let engine = audioEngine as? AudioCaptureEngine {
                audioStatus = engine.systemAudioStatus
                micStatus = engine.microphoneStatus
            }
        }
        
        print(renderer.separator)
        let statusLine = renderer.buildStatusLine(
            mode: currentMode,
            audioStatus: audioStatus,
            micStatus: micStatus
        )
        print(statusLine)
        print("❯ \(inputHandler.getPromptWithCursor())", terminator: "")
        fflush(stdout)
    }
    
    // MARK: - LLM Query Execution
    
    private func executeLLMQuery(type: String, content: String) {
        let queryIcon = type == "chat" ? "💬" : "⚡"
        let queryLabel = type == "chat" ? "Chat" : "Quick"
        
        print("\n\(queryIcon) \(queryLabel) query: \"\(content)\"")
        tui.showProcessingIndicator()
        print("   ✻ Processing...")
        fflush(stdout)
        
        let context = buildTranscriptContext()
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            defer { semaphore.signal() }
            
            do {
                if await !ipcClient.connected {
                    try await ipcClient.connect()
                }
                
                let result = try await llmService.executeLocalQuery(type: type, content: content, context: context)
                
                self.tui.hideProcessingIndicator()
                print("\r\u{001B}[K   ✅ Processed in \(String(format: "%.1f", result.elapsed))s")
                
                self.tui.addLLMResponse(result.content, model: result.model)
                
                print("\n   🤖 [\(result.model)] Response:")
                for line in result.content.split(separator: "\n", omittingEmptySubsequences: false) {
                    print("      \(line)")
                }
                print("")
                fflush(stdout)
                
            } catch {
                self.tui.hideProcessingIndicator()
                if error.localizedDescription.contains("not connected") || error.localizedDescription.contains("Connection") {
                    print("\r\u{001B}[K   ❌ Python backend not connected.")
                    print("   💡 Start backend: cd backend && source .venv/bin/activate && python main.py\n")
                } else {
                    print("\r\u{001B}[K   ❌ LLM query failed: \(error.localizedDescription)\n")
                }
                fflush(stdout)
            }
        }
        
        _ = semaphore.wait(timeout: .now() + 120)
    }
    
    private func executeCloudLLMQuery(content: String) {
        print("\n☁️  Cloud LLM query: \"\(content)\"")
        tui.showProcessingIndicator()
        print("   ✻ Processing with Cloud LLM...")
        fflush(stdout)
        
        let context = buildTranscriptContext()
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            defer { semaphore.signal() }
            
            do {
                if await !ipcClient.connected {
                    try await ipcClient.connect()
                }
                
                let result = try await llmService.executeCloudQuery(content: content, context: context)
                
                self.tui.hideProcessingIndicator()
                let ragIndicator = result.usedRag ? " (RAG)" : ""
                print("\r\u{001B}[K   ✅ Processed in \(String(format: "%.1f", result.elapsed))s\(ragIndicator)")
                
                self.tui.addLLMResponse(result.content, model: result.model)
                
                print("\n   \u{001B}[36m☁️  [\(result.model)] Response:\u{001B}[0m")
                for line in result.content.split(separator: "\n", omittingEmptySubsequences: false) {
                    print("      \(line)")
                }
                
                if !result.sources.isEmpty {
                    print("\n   \u{001B}[33m📚 Sources:\u{001B}[0m")
                    for source in result.sources {
                        print("      • \(source)")
                    }
                }
                print("")
                fflush(stdout)
                
            } catch let error as IPCError {
                self.tui.hideProcessingIndicator()
                switch error {
                case .cloudLLMError(let errorMsg):
                    print("\r\u{001B}[K   ❌ Cloud LLM error: \(errorMsg.error)")
                    print("   💡 \(errorMsg.suggestion ?? "Try /quick for local LLM")")
                    print("")
                case .notConnected, .connectionFailed:
                    print("\r\u{001B}[K   ❌ Python backend not connected.")
                    print("   💡 Start backend: cd backend && source .venv/bin/activate && python main.py\n")
                default:
                    print("\r\u{001B}[K   ❌ Cloud LLM query failed: \(error.localizedDescription)")
                    print("   💡 Try /quick for local LLM\n")
                }
                fflush(stdout)
            } catch {
                self.tui.hideProcessingIndicator()
                if error.localizedDescription.contains("not connected") || error.localizedDescription.contains("Connection") {
                    print("\r\u{001B}[K   ❌ Python backend not connected.")
                    print("   💡 Start backend: cd backend && source .venv/bin/activate && python main.py\n")
                } else {
                    print("\r\u{001B}[K   ❌ Cloud LLM query failed: \(error.localizedDescription)")
                    print("   💡 Try /quick for local LLM\n")
                }
                fflush(stdout)
            }
        }
        
        _ = semaphore.wait(timeout: .now() + 180)
    }
    
    private func buildTranscriptContext() -> [TranscriptionMessage] {
        return tui.transcriptEntries.map { entry in
            TranscriptionMessage(
                text: entry.text,
                source: entry.source.rawValue,
                timestamp: entry.timestamp.timeIntervalSince1970
            )
        }
    }

    // MARK: - KB Operations
    
    private func executeKBList(continuationToken: String?) {
        print("\n📋 Knowledge Base Documents:")
        print("   ─────────────────────────────────────")
        
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            defer { semaphore.signal() }
            
            do {
                if await !ipcClient.connected {
                    try await ipcClient.connect()
                }
                
                let result = try await kbService.listDocuments(continuationToken: continuationToken)
                
                if result.documents.isEmpty {
                    print("   (No documents found)")
                    print("")
                    print("   💡 Use /add {path} {name} to add a markdown document")
                } else {
                    for doc in result.documents {
                        print("   📄 \(doc.name)")
                        print("      Size: \(doc.formattedSize) | Modified: \(doc.formattedDate)")
                    }
                    
                    if result.hasMore {
                        print("")
                        print("   📑 More documents available. Type /more to see next page.")
                    }
                }
                print("")
                
            } catch let error as IPCError {
                self.handleKBError(error, operation: "list documents")
            } catch {
                print("   ❌ Failed to list documents: \(error.localizedDescription)")
                print("")
            }
        }
        
        _ = semaphore.wait(timeout: .now() + 30)
    }
    
    private func executeKBAdd(fromPath: String, name: String) {
        print("\n➕ Adding document to knowledge base...")
        print("   From: \(fromPath)")
        print("   Name: \(name)")
        
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            defer { semaphore.signal() }
            
            do {
                if await !ipcClient.connected {
                    try await ipcClient.connect()
                }
                
                let result = try await kbService.addDocument(fromPath: fromPath, name: name)
                
                if result.success {
                    if let doc = result.document {
                        print("   ✅ Added: \(doc.name) (\(doc.formattedSize))")
                        print("   📝 Document will be automatically indexed by Bedrock KB")
                    } else {
                        print("   ✅ \(result.message)")
                    }
                } else {
                    print("   ❌ \(result.message)")
                }
                print("")
                
            } catch let error as IPCError {
                self.handleKBError(error, operation: "add document", name: name)
            } catch {
                print("   ❌ Failed to add document: \(error.localizedDescription)")
                print("")
            }
        }
        
        _ = semaphore.wait(timeout: .now() + 60)
    }
    
    private func executeKBUpdate(fromPath: String, name: String) {
        print("\n🔄 Updating document in knowledge base...")
        print("   From: \(fromPath)")
        print("   Name: \(name)")
        
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            defer { semaphore.signal() }
            
            do {
                if await !ipcClient.connected {
                    try await ipcClient.connect()
                }
                
                let result = try await kbService.updateDocument(fromPath: fromPath, name: name)
                
                if result.success {
                    if let doc = result.document {
                        print("   ✅ Updated: \(doc.name) (\(doc.formattedSize))")
                        print("   📝 Document will be automatically reindexed by Bedrock KB")
                    } else {
                        print("   ✅ \(result.message)")
                    }
                } else {
                    print("   ❌ \(result.message)")
                }
                print("")
                
            } catch let error as IPCError {
                self.handleKBError(error, operation: "update document", name: name)
            } catch {
                print("   ❌ Failed to update document: \(error.localizedDescription)")
                print("")
            }
        }
        
        _ = semaphore.wait(timeout: .now() + 60)
    }
    
    private func executeKBRemove(name: String) {
        print("\n🗑️  Removing document from knowledge base...")
        print("   Name: \(name)")
        
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            defer { semaphore.signal() }
            
            do {
                if await !ipcClient.connected {
                    try await ipcClient.connect()
                }
                
                let result = try await kbService.removeDocument(name: name)
                
                if result.success {
                    print("   ✅ Removed: \(name)")
                    print("   🔄 Triggering Bedrock KB reindexing...")
                    
                    do {
                        let syncStatus = try await kbService.getSyncStatus()
                        print("   \(syncStatus.statusIcon) KB Status: \(syncStatus.status) (\(syncStatus.documentCount) documents)")
                    } catch {
                        print("   ⚠️  Could not get sync status")
                    }
                } else {
                    print("   ❌ \(result.message)")
                }
                print("")
                
            } catch let error as IPCError {
                self.handleKBError(error, operation: "remove document", name: name)
            } catch {
                print("   ❌ Failed to remove document: \(error.localizedDescription)")
                print("")
            }
        }
        
        _ = semaphore.wait(timeout: .now() + 60)
    }
    
    private func executeKBSync() {
        print("\n🔄 Triggering Knowledge Base sync...")
        
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            defer { semaphore.signal() }
            
            do {
                if await !ipcClient.connected {
                    try await ipcClient.connect()
                }
                
                let result = try await kbService.triggerSync()
                
                if result.success {
                    print("   ✅ Sync triggered successfully")
                    if let jobId = result.ingestionJobId {
                        print("   📋 Ingestion Job ID: \(jobId)")
                    }
                    if !result.message.isEmpty {
                        print("   ℹ️  \(result.message)")
                    }
                } else {
                    print("   ❌ \(result.message)")
                }
                print("")
                
            } catch let error as IPCError {
                self.handleKBError(error, operation: "trigger sync")
            } catch {
                print("   ❌ Failed to trigger sync: \(error.localizedDescription)")
                print("")
            }
        }
        
        _ = semaphore.wait(timeout: .now() + 60)
    }
    
    private func handleKBError(_ error: IPCError, operation: String, name: String? = nil) {
        switch error {
        case .kbError(let kbError):
            if kbError.errorType == "exists", let name = name {
                print("   ❌ Document '\(name)' already exists")
                print("   💡 Use /update to replace the existing document")
            } else if kbError.errorType == "not_found", let name = name {
                print("   ❌ Document '\(name)' not found")
                print("   💡 Use /list to see available documents")
            } else {
                print("   ❌ \(kbError.error)")
            }
        case .notConnected, .connectionFailed:
            print("   ❌ Python backend not connected.")
            print("   💡 Start backend: cd backend && source .venv/bin/activate && python main.py")
        default:
            print("   ❌ Failed to \(operation): \(error.localizedDescription)")
        }
        print("")
    }
}
