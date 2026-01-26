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
    private var currentInput: String = ""  // Track current input for footer rendering
    private var debug: Bool {
        didSet {
            // Update IPC client debug mode
            Task {
                await ipcClient.setDebug(debug)
            }
            // Update audio engine debug mode
            if #available(macOS 13.0, *) {
                if let engine = audioEngine as? AudioCaptureEngine {
                    engine.setDebug(debug)
                }
            }
            logger.logLevel = debug ? .debug : .info
            if debug {
                print("\r\u{001B}[K🐛 Debug mode ON")
            } else {
                print("\r\u{001B}[K🐛 Debug mode OFF")
            }
        }
    }
    
    // Audio capture engine (macOS 13.0+ only)
    private var audioEngine: Any?  // Type-erased to support availability check
    
    // IPC listening task
    private var ipcListeningTask: Task<Void, Never>?
    
    // Terminal dimensions
    private var terminalWidth: Int = 80
    private var terminalHeight: Int = 24
    
    // Fixed footer height (separator + input + status bar with commands)
    private let footerLines = 3
    
    // Transcript line aggregation - track last source and line content
    private var lastTranscriptSource: AudioSource?
    private var lastTranscriptLine: String = ""
    private var lastTranscriptTimestamp: String = ""
    private var lastHeaderTime: Date = Date.distantPast  // Track when we last showed icon+timestamp
    private let headerInterval: TimeInterval = 7.0  // Show icon+timestamp every 7 seconds
    
    /// Current application mode (delegated to state machine)
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
        
        // Get terminal size
        updateTerminalSize()
        
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
                    // Update status display in real-time during transcribing mode
                    if self.currentMode == .transcribing {
                        let statusIcon = source == .system ? "🔊" : "🎤"
                        let statusText = status == .active ? "ON" : "--"
                        print("\r\u{001B}[K", terminator: "")  // Clear line
                        print("   \(statusIcon) \(statusText)")
                        print("❯ \(self.currentInput)", terminator: "")
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
                    // Permission updates are shown in the next prompt cycle
                }
            }
            self.audioEngine = engine
        }
    }
    
    private func updateTerminalSize() {
        var ws = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0 {
            terminalWidth = Int(ws.ws_col)
            terminalHeight = Int(ws.ws_row)
        }
    }
    
    /// Main application loop
    /// Requirements: 1.1 - Launch and display Command_Mode interface
    /// Requirements: 1.2 - Handle ctrl+q for graceful termination
    func run() {
        showWelcome()
        
        while isRunning {
            // Print status bar and prompt
            printStatusAndPrompt()
            
            let input = readInput()
            
            // Handle ctrl+q for graceful exit (Requirement 1.2)
            if input == "\u{11}" { // Ctrl+Q
                gracefulShutdown()
                continue
            }
            
            // Handle Ctrl+C, Ctrl+D
            if input == "\u{03}" || input == "\u{04}" {
                gracefulShutdown()
                continue
            }
            
            // Empty input - just continue
            if input.isEmpty {
                continue
            }
            
            let command = parser.parse(input: input)
            handleCommand(command)
        }
        
        print("\nGoodbye! 👋\n")
    }
    
    /// Print status bar and input prompt (scrollback style)
    private func printStatusAndPrompt() {
        print(separator)
        let statusLine = buildStatusLine()
        print(statusLine)
        print("❯ ", terminator: "")
        fflush(stdout)
    }
    
    /// Graceful shutdown - stop all processes and exit
    /// Requirements: 1.2 - Gracefully terminate all active processes
    private func gracefulShutdown() {
        print("\n\n⏳ Shutting down...")
        
        // Stop audio capture if active
        if currentMode == .transcribing {
            stopAudioCapture()
        }
        
        // Disconnect IPC
        Task {
            await ipcClient.disconnect()
        }
        
        isRunning = false
    }
    
    /// Read input (simple raw mode input)
    /// Requirements: 1.2 - Handle ctrl+q for graceful exit
    private func readInput() -> String {
        currentInput = ""
        
        // Set terminal to raw mode
        var oldTermios = termios()
        tcgetattr(STDIN_FILENO, &oldTermios)
        var newTermios = oldTermios
        newTermios.c_lflag &= ~UInt(ICANON | ECHO)
        tcsetattr(STDIN_FILENO, TCSANOW, &newTermios)
        
        defer {
            tcsetattr(STDIN_FILENO, TCSANOW, &oldTermios)
        }
        
        while true {
            let char = getchar()
            
            // Enter - submit input
            if char == 10 || char == 13 {
                print("")  // Move to next line
                return currentInput
            }
            
            // Ctrl+Q - Graceful exit (Requirement 1.2)
            if char == 17 {
                return "\u{11}"
            }
            
            // Ctrl+C or Ctrl+D
            if char == 3 || char == 4 {
                return "\u{03}"
            }
            
            // Ctrl+B - Toggle debug mode
            if char == 2 {
                debug.toggle()
                continue
            }
            
            // Backspace
            if char == 127 || char == 8 {
                if !currentInput.isEmpty {
                    currentInput.removeLast()
                    print("\u{001B}[1D \u{001B}[1D", terminator: "")
                    fflush(stdout)
                }
                continue
            }
            
            // Regular printable character
            if char >= 32 && char < 127 {
                let c = Character(UnicodeScalar(UInt8(char)))
                currentInput.append(c)
                print(String(c), terminator: "")
                fflush(stdout)
            }
        }
    }
    
    private var separator: String {
        String(repeating: "─", count: terminalWidth)
    }
    
    private func clearScreen() {
        print("\u{001B}[2J\u{001B}[H", terminator: "")
        fflush(stdout)
    }
    
    private func showHeader() {
        print("""
        ▐▛███▜▌   dev.echo v1.0.0
         ▗▗ ▗▗    MLX-Whisper · Ollama/Llama
        ▐█████▌
        """)
    }
    
    private func clearAndResetPrompt() {
        clearScreen()
        showHeader()
        print("")
    }
    
    // MARK: - Status Line Builder
    
    /// Build the status line with mode, audio status, and available commands
    private func buildStatusLine() -> String {
        let modeIcon = currentMode == .transcribing ? "🎙️" : (currentMode == .knowledgeBaseManagement ? "📚" : "🤖")
        let modeName = currentMode.displayName.replacingOccurrences(of: " Mode", with: "")
        
        if currentMode == .transcribing {
            let audioStatus = tui.statusBar.audioStatus == .active ? "🔊ON" : "🔊--"
            let micStatus = tui.statusBar.micStatus == .active ? "🎤ON" : "🎤OFF"
            return "\(modeIcon) \(modeName) │ \(audioStatus) \(micStatus) │ /chat /quick /mic /stop /save /quit"
        } else if currentMode == .knowledgeBaseManagement {
            return "\(modeIcon) \(modeName) │ /list /add /update /remove /quit"
        } else {
            return "\(modeIcon) \(modeName) │ /new /managekb /quit"
        }
    }
    
    private func showWelcome() {
        print("""
        
        ▐▛███▜▌   dev.echo v1.0.0
         ▗▗ ▗▗    MLX-Whisper · Ollama/Llama
        ▐█████▌
        
        Welcome to dev.echo! Commands are shown in the status bar below.
        
        """)
    }

    
    private func handleCommand(_ command: Command) {
        // First, validate command using state machine
        let transitionResult = stateMachine.transition(with: command)
        
        switch transitionResult {
        case .invalidCommand(let reason):
            print("❌ \(reason)")
            print("   Available commands: \(currentMode.compactCommandsHelp)")
            return
            
        case .success(let newMode):
            // Mode changed - handle the transition
            handleModeTransition(to: newMode, via: command)
            return
            
        case .noTransition:
            // Command is valid but doesn't change mode - execute it
            break
        }
        
        // Execute mode-specific command logic
        switch currentMode {
        case .command:
            executeCommandModeAction(command)
        case .transcribing:
            executeTranscribingModeAction(command)
        case .knowledgeBaseManagement:
            executeKBModeAction(command)
        }
    }
    
    // MARK: - Mode Transition Handler
    /// Requirements: 2.1, 2.2, 3.7, 4.6 - Mode transitions
    
    private func handleModeTransition(to newMode: ApplicationMode, via command: Command) {
        switch (command, newMode) {
        case (.new, .transcribing):
            // Requirement 2.1: Transition to Transcribing_Mode and start audio capture
            tui.setMode(.transcribing)
            tui.startNewTranscript()  // Start fresh transcript session
            print("🎙️  Transcribing Mode")
            print("   Type /chat or /quick to query LLM with context")
            print("   Type /stop to pause, /save to export, /quit to return\n")
            startAudioCapture()
            
        case (.managekb, .knowledgeBaseManagement):
            // Requirement 2.2: Transition to KB_Management_Mode
            tui.setMode(.knowledgeBaseManagement)
            print("📚 KB Management Mode")
            print("   Type /list to see documents, /add, /update, /remove to manage")
            print("   Type /quit to return to command mode\n")
            
        case (.quit, .command):
            // Requirement 3.7, 4.6: Return to Command_Mode
            stopAudioCapture()
            tui.statusBar.setAudioStatus(.inactive)
            tui.statusBar.setMicStatus(.inactive)
            tui.endTranscript()  // End transcript session
            tui.setMode(.command)
            print("↩️  Returned to Command Mode\n")
            
        default:
            break
        }
    }
    
    // MARK: - Audio Capture Control
    
    private func startAudioCapture() {
        if #available(macOS 13.0, *) {
            guard let engine = audioEngine as? AudioCaptureEngine else {
                print("   ⚠️  Audio engine not available")
                return
            }
            
            Task {
                do {
                    // Connect to Python backend first
                    do {
                        try await ipcClient.connect()
                        // Clear line and print, then restore prompt
                        print("\r\u{001B}[K   ✅ Connected to Python backend")
                        print("❯ \(self.currentInput)", terminator: "")
                        fflush(stdout)
                        
                        // Start listening for transcriptions
                        startIPCListening()
                    } catch {
                        print("\r\u{001B}[K   ⚠️  Python backend not running: \(error.localizedDescription)")
                        print("   💡 Start backend with: cd backend && source .venv/bin/activate && python main.py")
                        print("❯ \(self.currentInput)", terminator: "")
                        fflush(stdout)
                    }
                    
                    // Check and request permissions first
                    let permissions = await engine.requestPermissions()
                    
                    if !permissions.screenCapture {
                        print("\r\u{001B}[K   ⚠️  Screen capture permission required for system audio")
                        print("❯ \(self.currentInput)", terminator: "")
                        fflush(stdout)
                    }
                    if !permissions.microphone {
                        print("\r\u{001B}[K   ⚠️  Microphone permission required")
                        print("❯ \(self.currentInput)", terminator: "")
                        fflush(stdout)
                    }
                    
                    try await engine.startCapture()
                    print("\r\u{001B}[K   ✅ Audio capture started")
                    print("❯ \(self.currentInput)", terminator: "")
                    fflush(stdout)
                } catch {
                    print("\r\u{001B}[K   ❌ Failed to start audio capture: \(error.localizedDescription)")
                    print("❯ \(self.currentInput)", terminator: "")
                    fflush(stdout)
                }
            }
        } else {
            print("   ⚠️  Audio capture requires macOS 13.0+")
            // Still set status to show UI is in transcribing mode
            tui.statusBar.setAudioStatus(.inactive)
            tui.statusBar.setMicStatus(.inactive)
        }
    }
    
    private func startIPCListening() {
        ipcListeningTask = Task {
            await ipcClient.startListening { [weak self] transcription in
                guard let self = self else { return }
                
                // Add transcription to TUI
                let source = AudioSource(rawValue: transcription.source) ?? .system
                let entry = TranscriptEntry(source: source, text: transcription.text)
                self.tui.appendTranscript(entry: entry)
                
                // Update terminal size before rendering
                self.updateTerminalSize()
                
                let icon = source.icon
                let timestamp = self.formatTimestamp(transcription.timestamp)
                let now = Date()
                
                // Determine if we should show header (icon + timestamp)
                let timeSinceLastHeader = now.timeIntervalSince(self.lastHeaderTime)
                let sourceChanged = source != self.lastTranscriptSource
                let shouldShowHeader = sourceChanged || timeSinceLastHeader >= self.headerInterval
                
                // Calculate available width for text
                let headerWidth = "\(icon) [\(timestamp)] ".count
                let maxLineWidth = self.terminalWidth - 2  // Leave some margin
                
                // Clear current input line
                print("\r\u{001B}[K", terminator: "")
                
                if shouldShowHeader {
                    // Start new line with header
                    self.lastTranscriptSource = source
                    self.lastTranscriptTimestamp = timestamp
                    self.lastTranscriptLine = transcription.text
                    self.lastHeaderTime = now
                    
                    let content = "\(icon) [\(timestamp)] \(transcription.text)"
                    
                    if source == .microphone {
                        let padding = max(0, self.terminalWidth - content.count)
                        print(String(repeating: " ", count: padding) + content)
                    } else {
                        print(content)
                    }
                } else {
                    // Continue on same or new line without header
                    let newText = self.lastTranscriptLine + " " + transcription.text
                    let currentLineLength = headerWidth + self.lastTranscriptLine.count
                    
                    if currentLineLength + transcription.text.count + 1 <= maxLineWidth {
                        // Fits on current line - update in place
                        self.lastTranscriptLine = newText
                        
                        let content = "\(icon) [\(self.lastTranscriptTimestamp)] \(newText)"
                        
                        // Move up and clear to update previous line
                        print("\u{001B}[A\u{001B}[K", terminator: "")
                        
                        if source == .microphone {
                            let padding = max(0, self.terminalWidth - content.count)
                            print(String(repeating: " ", count: padding) + content)
                        } else {
                            print(content)
                        }
                    } else {
                        // Doesn't fit - start new line without header (continuation)
                        self.lastTranscriptLine = transcription.text
                        
                        // Just print the text, indented to align with previous content
                        let indent = String(repeating: " ", count: headerWidth)
                        
                        if source == .microphone {
                            let content = indent + transcription.text
                            let padding = max(0, self.terminalWidth - content.count)
                            print(String(repeating: " ", count: padding) + content)
                        } else {
                            print(indent + transcription.text)
                        }
                    }
                }
                
                print("❯ \(self.currentInput)", terminator: "")  // Restore prompt with input
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
        // Stop IPC listening
        ipcListeningTask?.cancel()
        ipcListeningTask = nil
        
        Task {
            await ipcClient.disconnect()
        }
        
        if #available(macOS 13.0, *) {
            guard let engine = audioEngine as? AudioCaptureEngine else { return }
            
            Task {
                await engine.stopCapture()
            }
        }
    }
    
    /// Toggle microphone capture on/off
    private func toggleMicrophoneCapture() {
        if #available(macOS 13.0, *) {
            guard let engine = audioEngine as? AudioCaptureEngine else {
                print("\n⚠️  Audio engine not available\n")
                return
            }
            
            Task {
                let enabled = await engine.toggleMicrophone()
                if enabled {
                    tui.statusBar.setMicStatus(.active)
                    print("\n🎤 Microphone capture enabled\n")
                } else {
                    tui.statusBar.setMicStatus(.inactive)
                    print("\n🎤 Microphone capture disabled\n")
                }
            }
        } else {
            print("\n⚠️  Audio capture requires macOS 13.0+\n")
        }
    }
    
    // MARK: - Command Mode Actions
    
    private func executeCommandModeAction(_ command: Command) {
        switch command {
        case .quit:
            isRunning = false
        default:
            // Other commands handled by mode transition
            break
        }
    }
    
    // MARK: - Transcribing Mode Actions
    /// Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7 - Transcribing Mode Operations
    
    private func executeTranscribingModeAction(_ command: Command) {
        switch command {
        case .chat(let content):
            // Requirement 3.3: Send request with context to remote LLM
            executeLLMQuery(type: "chat", content: content)
            
        case .quick(let content):
            // Requirement 3.4: Send request with context to local LLM (Ollama)
            executeLLMQuery(type: "quick", content: content)
            
        case .stop:
            // Requirement 3.5: Stop capturing audio and microphone input
            stopAudioCapture()
            tui.statusBar.setAudioStatus(.inactive)
            tui.statusBar.setMicStatus(.inactive)
            print("\n⏹️  Audio capture stopped.\n")
            
        case .save:
            // Requirement 3.6: Display location selection and save transcript
            print("\n💾 Saving transcript...")
            let result = tui.saveTranscriptToDocuments()
            switch result {
            case .success(let path):
                print("   ✅ Transcript saved to: \(path)\n")
            case .failure(let error):
                print("   ⚠️  \(error.description)\n")
            }
            
        case .mic:
            // Toggle microphone capture on/off
            toggleMicrophoneCapture()
            
        default:
            break
        }
    }
    
    /// Execute LLM query with context
    /// Requirements: 3.3, 3.4, 3.8 - LLM queries with loading animation
    private func executeLLMQuery(type: String, content: String) {
        let queryIcon = type == "chat" ? "💬" : "⚡"
        let queryLabel = type == "chat" ? "Chat" : "Quick"
        
        print("\n\(queryIcon) \(queryLabel) query: \"\(content)\"")
        
        // Requirement 3.8: Display loading animation
        tui.showProcessingIndicator()
        print("   ✻ Processing...")
        fflush(stdout)
        
        // Build context from current transcript
        let context = buildTranscriptContext()
        
        // Use semaphore to wait for async task completion
        let semaphore = DispatchSemaphore(value: 0)
        
        // Send query to Python backend via IPC
        Task {
            defer { semaphore.signal() }
            
            do {
                // Check if connected, if not try to connect
                if await !ipcClient.connected {
                    try await ipcClient.connect()
                }
                
                let startTime = Date()
                let response = try await ipcClient.sendLLMQuery(
                    type: type,
                    content: content,
                    context: context
                )
                let elapsed = Date().timeIntervalSince(startTime)
                
                // Hide processing indicator and show response
                self.tui.hideProcessingIndicator()
                print("\r\u{001B}[K   ✅ Processed in \(String(format: "%.1f", elapsed))s")
                
                // Add response to transcript
                self.tui.addLLMResponse(response.content, model: response.model)
                
                // Display response
                print("\n   🤖 [\(response.model)] Response:")
                let lines = response.content.split(separator: "\n", omittingEmptySubsequences: false)
                for line in lines {
                    print("      \(line)")
                }
                print("")
                fflush(stdout)
                
            } catch {
                self.tui.hideProcessingIndicator()
                
                // Requirement 7.4: Display error if Ollama is not running
                if error.localizedDescription.contains("not connected") ||
                   error.localizedDescription.contains("Connection") {
                    print("\r\u{001B}[K   ❌ Python backend not connected.")
                    print("   💡 Start backend: cd backend && source .venv/bin/activate && python main.py\n")
                } else {
                    print("\r\u{001B}[K   ❌ LLM query failed: \(error.localizedDescription)\n")
                }
                fflush(stdout)
            }
        }
        
        // Wait for async task to complete (with timeout)
        _ = semaphore.wait(timeout: .now() + 120)  // 2 minute timeout for LLM response
    }
    
    /// Build transcript context for LLM queries
    /// Requirement 7.2: Include current conversation transcript as context
    private func buildTranscriptContext() -> [TranscriptionMessage] {
        return tui.transcriptEntries.map { entry in
            TranscriptionMessage(
                text: entry.text,
                source: entry.source.rawValue,
                timestamp: entry.timestamp.timeIntervalSince1970
            )
        }
    }
    
    // MARK: - KB Management Mode Actions
    /// Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6 - Knowledge Base Management
    
    private func executeKBModeAction(_ command: Command) {
        switch command {
        case .list:
            // Requirement 4.1: Display all documents in knowledge base
            executeKBList()
            
        case .add(let fromPath, let name):
            // Requirement 4.4, 4.5: Add markdown document to knowledge base
            executeKBAdd(fromPath: fromPath, name: name)
            
        case .update(let fromPath, let name):
            // Requirement 4.3: Update existing document
            executeKBUpdate(fromPath: fromPath, name: name)
            
        case .remove(let name):
            // Requirement 4.2: Delete document and confirm deletion
            executeKBRemove(name: name)
            
        default:
            break
        }
    }
    
    /// List all KB documents
    /// Requirement 4.1: Display all documents in the current knowledge base
    private func executeKBList() {
        print("\n📋 Knowledge Base Documents:")
        print("   ─────────────────────────────────────")
        
        // TODO: Connect to Python backend KB Manager (Task 11)
        // For now, show placeholder message
        print("   (KB Manager will be implemented in Task 11)")
        print("   No documents found.")
        print("")
        print("   💡 Use /add {path} {name} to add a markdown document")
        print("")
    }
    
    /// Add document to KB
    /// Requirements: 4.4, 4.5: Add markdown file, reject non-markdown
    private func executeKBAdd(fromPath: String, name: String) {
        print("\n➕ Adding document to knowledge base...")
        print("   From: \(fromPath)")
        print("   Name: \(name)")
        
        // Requirement 4.5: Validate markdown file
        guard fromPath.lowercased().hasSuffix(".md") else {
            print("   ❌ Error: Only markdown (.md) files are supported")
            print("   💡 Please provide a path to a .md file\n")
            return
        }
        
        // Check if file exists
        let fileManager = FileManager.default
        let expandedPath = NSString(string: fromPath).expandingTildeInPath
        
        guard fileManager.fileExists(atPath: expandedPath) else {
            print("   ❌ Error: File not found at '\(fromPath)'")
            print("   💡 Please check the file path and try again\n")
            return
        }
        
        // TODO: Connect to Python backend KB Manager (Task 11)
        print("   ✅ Would add '\(name)' to knowledge base")
        print("   (KB Manager will be implemented in Task 11)\n")
    }
    
    /// Update existing KB document
    /// Requirement 4.3: Update existing document with content from path
    private func executeKBUpdate(fromPath: String, name: String) {
        print("\n🔄 Updating document in knowledge base...")
        print("   From: \(fromPath)")
        print("   Name: \(name)")
        
        // Validate markdown file
        guard fromPath.lowercased().hasSuffix(".md") else {
            print("   ❌ Error: Only markdown (.md) files are supported\n")
            return
        }
        
        // Check if file exists
        let fileManager = FileManager.default
        let expandedPath = NSString(string: fromPath).expandingTildeInPath
        
        guard fileManager.fileExists(atPath: expandedPath) else {
            print("   ❌ Error: File not found at '\(fromPath)'\n")
            return
        }
        
        // TODO: Connect to Python backend KB Manager (Task 11)
        print("   ✅ Would update '\(name)' in knowledge base")
        print("   (KB Manager will be implemented in Task 11)\n")
    }
    
    /// Remove document from KB
    /// Requirement 4.2: Delete document and confirm deletion
    private func executeKBRemove(name: String) {
        print("\n🗑️  Removing document from knowledge base...")
        print("   Name: \(name)")
        
        // TODO: Connect to Python backend KB Manager (Task 11)
        print("   ✅ Would remove '\(name)' from knowledge base")
        print("   (KB Manager will be implemented in Task 11)\n")
    }
}
