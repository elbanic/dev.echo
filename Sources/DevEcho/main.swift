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
    private var terminalWidth: Int = 60
    private var terminalHeight: Int = 24
    
    // Fixed footer height (separator + input + separator + status)
    private let footerHeight = 4
    
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
                    switch source {
                    case .system:
                        self?.tui.statusBar.setAudioStatus(status)
                    case .microphone:
                        self?.tui.statusBar.setMicStatus(status)
                    }
                    self?.renderFooter()
                }
            }
            engine.onPermissionUpdate = { [weak self] permissions in
                DispatchQueue.main.async {
                    self?.tui.statusBar.setPermissions(
                        screenCapture: permissions.screenCapture,
                        microphone: permissions.microphone
                    )
                    self?.renderFooter()
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
            printPrompt()
            
            let input = readInputWithSlashHint()
            
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
            
            // Empty input
            if input.isEmpty {
                clearAndResetPrompt()
                continue
            }
            
            // Clear screen and show fresh prompt area
            clearScreen()
            showHeader()
            print(separator)
            
            let command = parser.parse(input: input)
            handleCommand(command)
        }
        
        print("\nGoodbye! 👋\n")
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
    
    /// Read input with "/" hint support
    /// Requirements: 1.2 - Handle ctrl+q for graceful exit
    private func readInputWithSlashHint() -> String {
        var input = ""
        var hintsShown = false
        
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
            
            // Enter
            if char == 10 || char == 13 {
                print("")
                break
            }
            
            // Ctrl+Q - Graceful exit (Requirement 1.2)
            if char == 17 {
                print("")
                return "\u{11}"
            }
            
            // Ctrl+C or Ctrl+D
            if char == 3 || char == 4 {
                print("")
                return "\u{03}"
            }
            
            // Ctrl+B - Toggle debug mode
            if char == 2 {
                debug.toggle()
                continue
            }
            
            // Backspace
            if char == 127 || char == 8 {
                if !input.isEmpty {
                    input.removeLast()
                    
                    // If we had hints and now input is empty, redraw without hints
                    if hintsShown && input.isEmpty {
                        clearAndResetPrompt()
                        printPromptInline()
                        hintsShown = false
                    } else {
                        // Just erase one character
                        print("\u{001B}[1D \u{001B}[1D", terminator: "")
                        fflush(stdout)
                    }
                }
                continue
            }
            
            // Regular printable character
            if char >= 32 && char < 127 {
                let c = Character(UnicodeScalar(UInt8(char)))
                input.append(c)
                print(String(c), terminator: "")
                fflush(stdout)
                
                // Show hints when "/" is first typed
                if input == "/" && !hintsShown {
                    print("")
                    print(separator)
                    showCommandHints()
                    print("❯ /", terminator: "")
                    fflush(stdout)
                    hintsShown = true
                }
            }
        }
        
        return input
    }
    
    private func printPromptInline() {
        print(separator)
        print("❯ ", terminator: "")
        print("")
        print(separator)
        print("\u{001B}[2A\u{001B}[3C", terminator: "")
        fflush(stdout)
    }
    
    private let separator = String(repeating: "─", count: 60)
    
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
    
    // MARK: - Fixed Footer Rendering
    
    /// Save cursor position
    private func saveCursor() {
        print("\u{001B}[s", terminator: "")
    }
    
    /// Restore cursor position
    private func restoreCursor() {
        print("\u{001B}[u", terminator: "")
    }
    
    /// Move cursor to specific row
    private func moveCursorToRow(_ row: Int) {
        print("\u{001B}[\(row);1H", terminator: "")
    }
    
    /// Clear from cursor to end of line
    private func clearToEndOfLine() {
        print("\u{001B}[K", terminator: "")
    }
    
    /// Render the fixed footer at bottom of terminal
    private func renderFooter() {
        updateTerminalSize()
        saveCursor()
        
        let footerStartRow = terminalHeight - footerHeight + 1
        
        // Line 1: Separator
        moveCursorToRow(footerStartRow)
        clearToEndOfLine()
        print(separator, terminator: "")
        
        // Line 2: Input prompt
        moveCursorToRow(footerStartRow + 1)
        clearToEndOfLine()
        print("❯ ", terminator: "")
        
        // Line 3: Separator
        moveCursorToRow(footerStartRow + 2)
        clearToEndOfLine()
        print(separator, terminator: "")
        
        // Line 4: Status bar
        moveCursorToRow(footerStartRow + 3)
        clearToEndOfLine()
        let statusLine = renderStatusLine()
        print(statusLine, terminator: "")
        
        restoreCursor()
        fflush(stdout)
    }
    
    /// Render status line based on current mode
    private func renderStatusLine() -> String {
        let modeIcon = currentMode == .transcribing ? "🎙️" : "📝"
        let modeDisplay = "[\(currentMode.displayName)]"
        
        if currentMode == .transcribing {
            let audioStatus = tui.statusBar.audioStatus == .active ? "🔊 ON" : "🔊 OFF"
            let micStatus = tui.statusBar.micStatus == .active ? "🎤 ON" : "🎤 OFF"
            return "\(modeIcon) \(modeDisplay) │ \(audioStatus) │ \(micStatus)"
        } else {
            return "\(modeIcon) \(modeDisplay)"
        }
    }
    
    /// Setup the initial screen layout with fixed footer
    private func setupScreenLayout() {
        clearScreen()
        showHeader()
        print("")
        print("Welcome to dev.echo! Type / for commands.")
        print("")
        
        // Set scroll region to exclude footer
        updateTerminalSize()
        let scrollEndRow = terminalHeight - footerHeight
        print("\u{001B}[1;\(scrollEndRow)r", terminator: "")  // Set scroll region
        
        renderFooter()
        
        // Move cursor to content area
        moveCursorToRow(7)
        fflush(stdout)
    }
    
    /// Print transcript entry in the scroll region
    private func printTranscript(icon: String, timestamp: String, text: String) {
        saveCursor()
        
        // Move to scroll region (before footer)
        let scrollEndRow = terminalHeight - footerHeight
        moveCursorToRow(scrollEndRow)
        
        // Print with newline to scroll content up
        print("")
        print("\(icon) [\(timestamp)] \(text)", terminator: "")
        
        restoreCursor()
        fflush(stdout)
    }
    
    private func showWelcome() {
        print("""
        
        ▐▛███▜▌   dev.echo v1.0.0
         ▗▗ ▗▗    MLX-Whisper · Ollama/Llama
        ▐█████▌
        
        Welcome to dev.echo! Type / for commands.
        
        """)
        // Don't print status bar here - it will be printed by printPrompt()
    }
    
    private func printStatusBar() {
        print(separator)
        // Show current mode
        let modeDisplay = "[\(currentMode.displayName)]"
        
        // In transcribing mode, show audio status
        if currentMode == .transcribing {
            let audioStatus = tui.statusBar.audioStatus == .active ? "🔊 ON" : "🔊 OFF"
            let micStatus = tui.statusBar.micStatus == .active ? "🎤 ON" : "🎤 OFF"
            let channel = tui.statusBar.currentChannel.icon
            let perms = tui.statusBar.permissionStatus.allGranted ? "✓" : "✗"
            print("\(modeDisplay) │ \(channel) │ \(audioStatus) │ \(micStatus) │ \(perms) Permissions")
        } else {
            print(modeDisplay)
        }
    }
    
    private func printPrompt() {
        printStatusBar()
        print(separator)
        print("❯ ", terminator: "")
        print("")
        print(separator)
        print("\u{001B}[2A\u{001B}[3C", terminator: "") // Move up 2 lines, right 3 chars (after "❯ ")
        fflush(stdout)
    }
    
    private func printPromptEnd() {
        print(separator)
    }
    
    private func showCommandHints() {
        print("Available commands:")
        print(currentMode.availableCommandsHelp)
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
                        print("   ✅ Connected to Python backend")
                        
                        // Start listening for transcriptions
                        startIPCListening()
                    } catch {
                        print("   ⚠️  Python backend not running: \(error.localizedDescription)")
                        print("   💡 Start backend with: cd backend && source .venv/bin/activate && python main.py")
                    }
                    
                    // Check and request permissions first
                    let permissions = await engine.requestPermissions()
                    
                    if !permissions.screenCapture {
                        print("   ⚠️  Screen capture permission required for system audio")
                    }
                    if !permissions.microphone {
                        print("   ⚠️  Microphone permission required")
                    }
                    
                    try await engine.startCapture()
                    print("   ✅ Audio capture started")
                } catch {
                    print("   ❌ Failed to start audio capture: \(error.localizedDescription)")
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
                
                // Print to console for now (until full TUI rendering is implemented)
                let icon = source.icon
                let timestamp = self.formatTimestamp(transcription.timestamp)
                
                // Clear current line and print transcription
                print("\r\u{001B}[K", terminator: "")  // Clear line
                print("\(icon) [\(timestamp)] \(transcription.text)")
                print("❯ ", terminator: "")
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
        print("   ✻ Processing...", terminator: "")
        fflush(stdout)
        
        // Build context from current transcript
        let context = buildTranscriptContext()
        
        // Send query to Python backend via IPC
        Task {
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
                await MainActor.run {
                    self.tui.hideProcessingIndicator()
                    print("\r\u{001B}[K   ✻ Processed in \(String(format: "%.1f", elapsed))s")
                    
                    // Add response to transcript
                    self.tui.addLLMResponse(response.content, model: response.model)
                    
                    // Display response
                    print("\n   🤖 [\(response.model)] Response:")
                    let lines = response.content.split(separator: "\n", omittingEmptySubsequences: false)
                    for line in lines {
                        print("      \(line)")
                    }
                    print("")
                }
                
            } catch {
                await MainActor.run {
                    self.tui.hideProcessingIndicator()
                    print("\r\u{001B}[K")
                    
                    // Requirement 7.4: Display error if Ollama is not running
                    if error.localizedDescription.contains("not connected") ||
                       error.localizedDescription.contains("Connection") {
                        print("   ❌ Python backend not connected.")
                        print("   💡 Start backend: cd backend && source .venv/bin/activate && python main.py\n")
                    } else {
                        print("   ❌ LLM query failed: \(error.localizedDescription)\n")
                    }
                }
            }
        }
        
        // Wait briefly for async task to complete display
        Thread.sleep(forTimeInterval: 0.1)
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
