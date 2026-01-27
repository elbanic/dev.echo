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
    
    // Phase 2: KB pagination state
    private var lastKBContinuationToken: String?
    
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
    
    /// Calculate display width accounting for emoji (2 columns each)
    private func displayWidth(_ str: String) -> Int {
        var width = 0
        for scalar in str.unicodeScalars {
            // Emoji and wide characters take 2 columns
            if scalar.value > 0x1F00 || (scalar.value >= 0x2600 && scalar.value <= 0x27BF) ||
               (scalar.value >= 0x1F300 && scalar.value <= 0x1F9FF) {
                width += 2
            } else {
                width += 1
            }
        }
        return width
    }
    
    /// Truncate string to fit display width
    private func truncateToWidth(_ str: String, maxWidth: Int) -> String {
        var width = 0
        var result = ""
        for char in str {
            var charWidth = 0
            for scalar in char.unicodeScalars {
                if scalar.value > 0x1F00 || (scalar.value >= 0x2600 && scalar.value <= 0x27BF) ||
                   (scalar.value >= 0x1F300 && scalar.value <= 0x1F9FF) {
                    charWidth = 2
                } else {
                    charWidth = max(charWidth, 1)
                }
            }
            if width + charWidth + 3 > maxWidth {  // Leave room for "..."
                return result + "..."
            }
            width += charWidth
            result.append(char)
        }
        return result
    }
    
    /// Wrap string into multiple lines to fit display width (right-aligned for microphone)
    private func wrapToWidth(_ str: String, maxWidth: Int, rightAlign: Bool) -> [String] {
        var lines: [String] = []
        var currentLine = ""
        var currentWidth = 0
        
        for char in str {
            var charWidth = 0
            for scalar in char.unicodeScalars {
                if scalar.value > 0x1F00 || (scalar.value >= 0x2600 && scalar.value <= 0x27BF) ||
                   (scalar.value >= 0x1F300 && scalar.value <= 0x1F9FF) {
                    charWidth = 2
                } else {
                    charWidth = max(charWidth, 1)
                }
            }
            
            if currentWidth + charWidth > maxWidth {
                lines.append(currentLine)
                currentLine = String(char)
                currentWidth = charWidth
            } else {
                currentLine.append(char)
                currentWidth += charWidth
            }
        }
        
        if !currentLine.isEmpty {
            lines.append(currentLine)
        }
        
        return lines
    }
    
    /// Print content with optional right alignment, wrapping if needed
    private func printWrapped(_ content: String, maxWidth: Int, rightAlign: Bool) {
        let contentWidth = displayWidth(content)
        
        if contentWidth <= maxWidth {
            // Fits on one line
            if rightAlign {
                let padding = max(0, terminalWidth - contentWidth)
                print(String(repeating: " ", count: padding) + content)
            } else {
                print(content)
            }
        } else {
            // Need to wrap
            let lines = wrapToWidth(content, maxWidth: maxWidth, rightAlign: rightAlign)
            for line in lines {
                if rightAlign {
                    let lineWidth = displayWidth(line)
                    let padding = max(0, terminalWidth - lineWidth)
                    print(String(repeating: " ", count: padding) + line)
                } else {
                    print(line)
                }
            }
        }
    }
    
    /// Build the status line with mode, audio status, and available commands
    private func buildStatusLine() -> String {
        let modeIcon = currentMode == .transcribing ? "🎙️" : (currentMode == .knowledgeBaseManagement ? "📚" : "🤖")
        let modeName = currentMode.displayName.replacingOccurrences(of: " Mode", with: "")
        
        if currentMode == .transcribing {
            let audioStatus = tui.statusBar.audioStatus == .active ? "🔊ON" : "🔊--"
            let micStatus = tui.statusBar.micStatus == .active ? "🎤ON" : "🎤OFF"
            return "\(modeIcon) \(modeName) │ \(audioStatus) \(micStatus) │ /chat /quick /mic /stop /save /quit"
        } else if currentMode == .knowledgeBaseManagement {
            return "\(modeIcon) \(modeName) │ /list /add /update /remove /sync /quit"
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
                        
                        // Phase 2: Check KB connectivity on startup
                        // Requirements: 11.3, 11.5
                        await checkKBConnectivity()
                        
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
    
    /// Check KB connectivity on startup (Phase 2)
    /// Requirements: 11.3, 11.5
    private func checkKBConnectivity() async {
        do {
            let syncStatus = try await ipcClient.getKBSyncStatus()
            
            // Update status bar with KB status
            tui.statusBar.setKBStatus(from: syncStatus)
            
            // Display KB status
            print("\r\u{001B}[K   \(syncStatus.statusIcon) KB: \(syncStatus.status) (\(syncStatus.documentCount) documents)")
            
            if let errorMessage = syncStatus.errorMessage {
                print("\r\u{001B}[K   ⚠️  KB Warning: \(errorMessage)")
            }
            
            print("❯ \(self.currentInput)", terminator: "")
            fflush(stdout)
            
        } catch {
            // Handle connectivity errors gracefully
            tui.statusBar.setKBStatus(isConnected: false, status: "UNKNOWN", documentCount: 0)
            
            // Don't show error for KB - it's optional
            // Just log it for debugging
            logger.debug("KB connectivity check failed: \(error.localizedDescription)")
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
                        self.printWrapped(content, maxWidth: maxLineWidth, rightAlign: true)
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
                            self.printWrapped(content, maxWidth: maxLineWidth, rightAlign: true)
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
                            self.printWrapped(content, maxWidth: maxLineWidth, rightAlign: true)
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
        setMicrophoneCapture(enable: nil)
    }
    
    /// Set microphone capture state
    /// - Parameter enable: true to enable, false to disable, nil to toggle
    private func setMicrophoneCapture(enable: Bool?) {
        if #available(macOS 13.0, *) {
            guard let engine = audioEngine as? AudioCaptureEngine else {
                print("\n⚠️  Audio engine not available\n")
                return
            }
            
            Task {
                let currentlyEnabled = engine.microphoneEnabled
                let shouldEnable: Bool
                
                if let enable = enable {
                    // Explicit on/off
                    shouldEnable = enable
                    if shouldEnable == currentlyEnabled {
                        // Already in desired state
                        let state = shouldEnable ? "enabled" : "disabled"
                        print("\n🎤 Microphone capture already \(state)\n")
                        return
                    }
                } else {
                    // Toggle
                    shouldEnable = !currentlyEnabled
                }
                
                // Perform the toggle (which will set to opposite of current state)
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
            // Requirement 6.1, 6.2: Send request with context to Cloud LLM (Phase 2)
            executeCloudLLMQuery(content: content)
            
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
            
        case .mic(let enable):
            // Toggle or set microphone capture on/off
            setMicrophoneCapture(enable: enable)
            
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
    
    /// Execute Cloud LLM query with RAG support (Phase 2)
    /// Requirements: 6.1, 6.2, 6.3, 6.6 - Cloud LLM queries with sources
    private func executeCloudLLMQuery(content: String) {
        print("\n☁️  Cloud LLM query: \"\(content)\"")
        
        // Requirement 6.3: Display loading animation
        tui.showProcessingIndicator()
        print("   ✻ Processing with Cloud LLM...")
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
                let response = try await ipcClient.sendCloudLLMQuery(
                    content: content,
                    context: context,
                    forceRag: false
                )
                let elapsed = Date().timeIntervalSince(startTime)
                
                // Hide processing indicator and show response
                self.tui.hideProcessingIndicator()
                
                let ragIndicator = response.usedRag ? " (RAG)" : ""
                print("\r\u{001B}[K   ✅ Processed in \(String(format: "%.1f", elapsed))s\(ragIndicator)")
                
                // Add response to transcript
                self.tui.addLLMResponse(response.content, model: response.model)
                
                // Display response with distinct color (cyan for Cloud LLM)
                print("\n   \u{001B}[36m☁️  [\(response.model)] Response:\u{001B}[0m")
                let lines = response.content.split(separator: "\n", omittingEmptySubsequences: false)
                for line in lines {
                    print("      \(line)")
                }
                
                // Requirement 6.6: Display sources used from KB
                if !response.sources.isEmpty {
                    print("\n   \u{001B}[33m📚 Sources:\u{001B}[0m")
                    for source in response.sources {
                        print("      • \(source)")
                    }
                }
                
                print("")
                fflush(stdout)
                
            } catch let error as IPCError {
                self.tui.hideProcessingIndicator()
                
                switch error {
                case .cloudLLMError(let errorMsg):
                    // Requirement 6.5: Display error and suggest /quick
                    print("\r\u{001B}[K   ❌ Cloud LLM error: \(errorMsg.error)")
                    if let suggestion = errorMsg.suggestion {
                        print("   💡 \(suggestion)")
                    } else {
                        print("   💡 Try /quick for local LLM")
                    }
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
                
                if error.localizedDescription.contains("not connected") ||
                   error.localizedDescription.contains("Connection") {
                    print("\r\u{001B}[K   ❌ Python backend not connected.")
                    print("   💡 Start backend: cd backend && source .venv/bin/activate && python main.py\n")
                } else {
                    print("\r\u{001B}[K   ❌ Cloud LLM query failed: \(error.localizedDescription)")
                    print("   💡 Try /quick for local LLM\n")
                }
                fflush(stdout)
            }
        }
        
        // Wait for async task to complete (with timeout)
        _ = semaphore.wait(timeout: .now() + 180)  // 3 minute timeout for Cloud LLM response
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
            // Requirement 2.1: Display all documents in knowledge base
            executeKBList(continuationToken: nil)
            
        case .listMore:
            // Requirement 2.4: Pagination support - use stored token
            if let token = lastKBContinuationToken {
                executeKBList(continuationToken: token)
            } else {
                print("\n   ⚠️  No more documents to show. Use /list to start from the beginning.\n")
            }
            
        case .add(let fromPath, let name):
            // Requirement 3.1-3.5: Add markdown document to knowledge base
            executeKBAdd(fromPath: fromPath, name: name)
            
        case .update(let fromPath, let name):
            // Requirement 4.1-4.4: Update existing document
            executeKBUpdate(fromPath: fromPath, name: name)
            
        case .remove(let name):
            // Requirement 5.1-5.3: Delete document and trigger sync
            executeKBRemove(name: name)
            
        case .sync:
            // Trigger KB indexing/sync
            executeKBSync()
            
        default:
            break
        }
    }
    
    /// List all KB documents with pagination (Phase 2)
    /// Requirements: 2.1, 2.3, 2.4 - List documents with pagination
    private func executeKBList(continuationToken: String?) {
        print("\n📋 Knowledge Base Documents:")
        print("   ─────────────────────────────────────")
        
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            defer { semaphore.signal() }
            
            do {
                // Connect if not connected
                if await !ipcClient.connected {
                    try await ipcClient.connect()
                }
                
                let response = try await ipcClient.listKBDocuments(
                    continuationToken: continuationToken,
                    maxItems: 20
                )
                
                if response.documents.isEmpty {
                    print("   (No documents found)")
                    print("")
                    print("   💡 Use /add {path} {name} to add a markdown document")
                } else {
                    // Requirement 2.3: Sort alphabetically (already sorted by backend)
                    for doc in response.documents {
                        print("   📄 \(doc.name)")
                        print("      Size: \(doc.formattedSize) | Modified: \(doc.formattedDate)")
                    }
                    
                    // Requirement 2.4: Show pagination info
                    if response.hasMore {
                        self.lastKBContinuationToken = response.continuationToken
                        print("")
                        print("   📑 More documents available. Type /more to see next page.")
                    } else {
                        self.lastKBContinuationToken = nil
                    }
                }
                print("")
                
            } catch let error as IPCError {
                switch error {
                case .kbError(let kbError):
                    print("   ❌ \(kbError.error)")
                case .notConnected, .connectionFailed:
                    print("   ❌ Python backend not connected.")
                    print("   💡 Start backend: cd backend && source .venv/bin/activate && python main.py")
                default:
                    print("   ❌ Failed to list documents: \(error.localizedDescription)")
                }
                print("")
            } catch {
                print("   ❌ Failed to list documents: \(error.localizedDescription)")
                print("")
            }
        }
        
        _ = semaphore.wait(timeout: .now() + 30)
    }
    
    /// Add document to KB (Phase 2)
    /// Requirements: 3.1-3.5: Add markdown file with validation
    private func executeKBAdd(fromPath: String, name: String) {
        print("\n➕ Adding document to knowledge base...")
        print("   From: \(fromPath)")
        print("   Name: \(name)")
        
        // Requirement 3.3: Validate markdown file
        let lowercasePath = fromPath.lowercased()
        guard lowercasePath.hasSuffix(".md") || lowercasePath.hasSuffix(".markdown") else {
            print("   ❌ Error: Only markdown files are supported (.md, .markdown)")
            print("   💡 Please provide a path to a markdown file\n")
            return
        }
        
        // Check if file exists
        let fileManager = FileManager.default
        let expandedPath = NSString(string: fromPath).expandingTildeInPath
        
        guard fileManager.fileExists(atPath: expandedPath) else {
            // Requirement 3.4: Display error for non-existent file
            print("   ❌ Error: File not found at '\(fromPath)'")
            print("   💡 Please check the file path and try again\n")
            return
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            defer { semaphore.signal() }
            
            do {
                // Connect if not connected
                if await !ipcClient.connected {
                    try await ipcClient.connect()
                }
                
                let response = try await ipcClient.addKBDocument(
                    sourcePath: expandedPath,
                    name: name
                )
                
                if response.success {
                    // Requirement 3.2: Display confirmation with size
                    if let doc = response.document {
                        print("   ✅ Added: \(doc.name) (\(doc.formattedSize))")
                        print("   📝 Document will be automatically indexed by Bedrock KB")
                    } else {
                        print("   ✅ \(response.message)")
                    }
                } else {
                    print("   ❌ \(response.message)")
                }
                print("")
                
            } catch let error as IPCError {
                switch error {
                case .kbError(let kbError):
                    // Requirement 3.5: Show error if document exists
                    if kbError.errorType == "exists" {
                        print("   ❌ Document '\(name)' already exists")
                        print("   💡 Use /update to replace the existing document")
                    } else {
                        print("   ❌ \(kbError.error)")
                    }
                case .notConnected, .connectionFailed:
                    print("   ❌ Python backend not connected.")
                    print("   💡 Start backend: cd backend && source .venv/bin/activate && python main.py")
                default:
                    print("   ❌ Failed to add document: \(error.localizedDescription)")
                }
                print("")
            } catch {
                print("   ❌ Failed to add document: \(error.localizedDescription)")
                print("")
            }
        }
        
        _ = semaphore.wait(timeout: .now() + 60)
    }
    
    /// Update existing KB document (Phase 2)
    /// Requirements: 4.1-4.4: Update document with validation
    private func executeKBUpdate(fromPath: String, name: String) {
        print("\n🔄 Updating document in knowledge base...")
        print("   From: \(fromPath)")
        print("   Name: \(name)")
        
        // Validate markdown file
        let lowercasePath = fromPath.lowercased()
        guard lowercasePath.hasSuffix(".md") || lowercasePath.hasSuffix(".markdown") else {
            // Requirement 4.4: Validate markdown
            print("   ❌ Error: Only markdown files are supported (.md, .markdown)\n")
            return
        }
        
        // Check if file exists
        let fileManager = FileManager.default
        let expandedPath = NSString(string: fromPath).expandingTildeInPath
        
        guard fileManager.fileExists(atPath: expandedPath) else {
            // Requirement 4.4: Display error for non-existent file
            print("   ❌ Error: File not found at '\(fromPath)'\n")
            return
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            defer { semaphore.signal() }
            
            do {
                // Connect if not connected
                if await !ipcClient.connected {
                    try await ipcClient.connect()
                }
                
                let response = try await ipcClient.updateKBDocument(
                    sourcePath: expandedPath,
                    name: name
                )
                
                if response.success {
                    // Requirement 4.2: Display confirmation with new size
                    if let doc = response.document {
                        print("   ✅ Updated: \(doc.name) (\(doc.formattedSize))")
                        print("   📝 Document will be automatically reindexed by Bedrock KB")
                    } else {
                        print("   ✅ \(response.message)")
                    }
                } else {
                    print("   ❌ \(response.message)")
                }
                print("")
                
            } catch let error as IPCError {
                switch error {
                case .kbError(let kbError):
                    // Requirement 4.3: Show error if document doesn't exist
                    if kbError.errorType == "not_found" {
                        print("   ❌ Document '\(name)' not found")
                        print("   💡 Use /add to create a new document")
                    } else {
                        print("   ❌ \(kbError.error)")
                    }
                case .notConnected, .connectionFailed:
                    print("   ❌ Python backend not connected.")
                    print("   💡 Start backend: cd backend && source .venv/bin/activate && python main.py")
                default:
                    print("   ❌ Failed to update document: \(error.localizedDescription)")
                }
                print("")
            } catch {
                print("   ❌ Failed to update document: \(error.localizedDescription)")
                print("")
            }
        }
        
        _ = semaphore.wait(timeout: .now() + 60)
    }
    
    /// Remove document from KB (Phase 2)
    /// Requirements: 5.1-5.3: Delete document and trigger sync
    private func executeKBRemove(name: String) {
        print("\n🗑️  Removing document from knowledge base...")
        print("   Name: \(name)")
        
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            defer { semaphore.signal() }
            
            do {
                // Connect if not connected
                if await !ipcClient.connected {
                    try await ipcClient.connect()
                }
                
                let response = try await ipcClient.removeKBDocument(name: name)
                
                if response.success {
                    // Requirement 5.2, 5.3: Trigger sync and display status
                    print("   ✅ Removed: \(name)")
                    print("   🔄 Triggering Bedrock KB reindexing...")
                    
                    // The backend should have triggered sync automatically
                    // Display sync status
                    do {
                        let syncStatus = try await ipcClient.getKBSyncStatus()
                        print("   \(syncStatus.statusIcon) KB Status: \(syncStatus.status) (\(syncStatus.documentCount) documents)")
                    } catch {
                        print("   ⚠️  Could not get sync status")
                    }
                } else {
                    print("   ❌ \(response.message)")
                }
                print("")
                
            } catch let error as IPCError {
                switch error {
                case .kbError(let kbError):
                    // Requirement 5.4: Show error if document doesn't exist
                    if kbError.errorType == "not_found" {
                        print("   ❌ Document '\(name)' not found")
                        print("   💡 Use /list to see available documents")
                    } else {
                        print("   ❌ \(kbError.error)")
                    }
                case .notConnected, .connectionFailed:
                    print("   ❌ Python backend not connected.")
                    print("   💡 Start backend: cd backend && source .venv/bin/activate && python main.py")
                default:
                    print("   ❌ Failed to remove document: \(error.localizedDescription)")
                }
                print("")
            } catch {
                print("   ❌ Failed to remove document: \(error.localizedDescription)")
                print("")
            }
        }
        
        _ = semaphore.wait(timeout: .now() + 60)
    }
    
    /// Trigger KB sync/indexing (Phase 2)
    /// Requirements: 5.2 - Trigger Bedrock KB reindexing
    private func executeKBSync() {
        print("\n🔄 Triggering Knowledge Base sync...")
        
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            defer { semaphore.signal() }
            
            do {
                // Connect if not connected
                if await !ipcClient.connected {
                    try await ipcClient.connect()
                }
                
                let response = try await ipcClient.triggerKBSync()
                
                if response.success {
                    print("   ✅ Sync triggered successfully")
                    if let jobId = response.ingestionJobId {
                        print("   📋 Ingestion Job ID: \(jobId)")
                    }
                    if !response.message.isEmpty {
                        print("   ℹ️  \(response.message)")
                    }
                } else {
                    print("   ❌ \(response.message)")
                }
                print("")
                
            } catch let error as IPCError {
                switch error {
                case .kbError(let kbError):
                    print("   ❌ \(kbError.error)")
                case .notConnected, .connectionFailed:
                    print("   ❌ Python backend not connected.")
                    print("   💡 Start backend: cd backend && source .venv/bin/activate && python main.py")
                default:
                    print("   ❌ Failed to trigger sync: \(error.localizedDescription)")
                }
                print("")
            } catch {
                print("   ❌ Failed to trigger sync: \(error.localizedDescription)")
                print("")
            }
        }
        
        _ = semaphore.wait(timeout: .now() + 60)
    }
}
