import Foundation

/// Protocol for Terminal UI management
protocol TerminalUIManagerProtocol {
    func render()
    func renderHeader()
    func renderModeIndicator(mode: ApplicationMode)
    func renderTranscriptArea()
    func renderInputArea()
    func renderStatusBar()
    
    func appendTranscript(entry: TranscriptEntry)
    func appendLLMResponse(_ response: LLMResponseEntry)
    func showProcessingIndicator()
    func hideProcessingIndicator()
    func showError(message: String)
    func clearScreen()
}

/// Main Terminal UI Engine - Claude Code style interface
/// Manages header, transcript area, input, and status bar
final class TUIEngine: TerminalUIManagerProtocol {
    
    // MARK: - Properties
    
    private let header: HeaderView
    private(set) var statusBar: StatusBarManager
    private(set) var processingIndicator: ProcessingIndicator
    
    private(set) var currentMode: ApplicationMode
    
    /// Current transcript session
    private(set) var transcript: Transcript
    
    /// Legacy accessors for backward compatibility
    var transcriptEntries: [TranscriptEntry] {
        transcript.entries
    }
    
    var llmResponses: [LLMResponseEntry] {
        transcript.llmResponses
    }
    
    private let terminalWidth: Int
    private let transcriptHeight: Int
    private var currentInput: String
    private var lastError: String?

    
    // MARK: - Initialization
    
    init(
        version: String = "1.0.0",
        modelInfo: String = "MLX-Whisper · Ollama/Llama",
        terminalWidth: Int = 90,
        transcriptHeight: Int = 15
    ) {
        self.header = HeaderView(version: version, modelInfo: modelInfo)
        self.statusBar = StatusBarManager()
        self.processingIndicator = ProcessingIndicator()
        self.currentMode = .command
        self.transcript = Transcript()
        self.terminalWidth = terminalWidth
        self.transcriptHeight = transcriptHeight
        self.currentInput = ""
        self.lastError = nil
    }
    
    // MARK: - Mode Management
    
    func setMode(_ mode: ApplicationMode) {
        currentMode = mode
    }
    
    // MARK: - Rendering
    
    func render() {
        clearScreen()
        renderHeader()
        print("")
        renderModeIndicator(mode: currentMode)
        print("")
        renderSeparator()
        renderTranscriptArea()
        renderSeparator()
        print("")
        renderInputArea()
        print("")
        renderDivider()
        renderStatusBar()
    }
    
    func renderHeader() {
        print(header.render(width: terminalWidth))
    }
    
    func renderModeIndicator(mode: ApplicationMode) {
        let indicator = centerText("\(mode.displayName) · \(mode.exitHint)", width: terminalWidth)
        print(indicator)
    }
    
    func renderTranscriptArea() {
        // Combine and sort all entries by timestamp using Transcript model
        var allEntries: [(date: Date, render: String, lineCount: Int)] = []
        
        // Add transcript entries (already sorted in Transcript model)
        for entry in transcript.entries {
            let rendered = renderTranscriptEntry(entry)
            let lineCount = rendered.components(separatedBy: "\n").count
            allEntries.append((entry.timestamp, rendered, lineCount))
        }
        
        // Add LLM responses (already sorted in Transcript model)
        for response in transcript.llmResponses {
            let rendered = renderLLMResponse(response)
            let lineCount = rendered.components(separatedBy: "\n").count
            allEntries.append((response.timestamp, rendered, lineCount))
        }
        
        // Sort by timestamp (chronological order)
        allEntries.sort { $0.date < $1.date }
        
        // Calculate how many entries fit in the transcript area
        // New entries scroll from bottom (most recent at bottom)
        var visibleEntries: [(date: Date, render: String, lineCount: Int)] = []
        var totalLines = 0
        
        // Start from the end (most recent) and work backwards
        for entry in allEntries.reversed() {
            if totalLines + entry.lineCount <= transcriptHeight {
                visibleEntries.insert(entry, at: 0)
                totalLines += entry.lineCount
            } else {
                break
            }
        }
        
        // Render empty lines if needed (to push content to bottom)
        let emptyLines = transcriptHeight - totalLines
        for _ in 0..<emptyLines {
            print("")
        }
        
        // Render visible entries (oldest first, newest at bottom)
        for entry in visibleEntries {
            print(entry.render)
        }
        
        // Show processing indicator if active
        if processingIndicator.isActive {
            print(processingIndicator.render())
        }
    }

    
    func renderInputArea() {
        if let error = lastError {
            print("  ⚠️  \(error)")
            lastError = nil
        }
        print("❯ \(currentInput)")
    }
    
    func renderStatusBar() {
        print(statusBar.render())
    }
    
    // MARK: - Transcript Management
    
    func appendTranscript(entry: TranscriptEntry) {
        transcript.addEntry(entry)
    }
    
    func appendLLMResponse(_ response: LLMResponseEntry) {
        transcript.addLLMResponse(response)
    }
    
    func clearTranscript() {
        transcript = Transcript()
    }
    
    /// Start a new transcript session
    func startNewTranscript() {
        transcript = Transcript()
    }
    
    /// End the current transcript session
    func endTranscript() {
        transcript.end()
    }
    
    /// Get the current transcript for export
    func getCurrentTranscript() -> Transcript {
        return transcript
    }
    
    /// Export transcript to markdown
    func exportTranscriptToMarkdown() -> String {
        return transcript.toMarkdown()
    }
    
    // MARK: - Transcript Save
    
    /// Save transcript to a file at the specified path
    /// - Parameter path: The file path to save to
    /// - Returns: Result indicating success or failure
    func saveTranscript(to path: String) -> TranscriptExportResult {
        // End the transcript session before saving
        transcript.end()
        return TranscriptExporter.export(transcript, to: path)
    }
    
    /// Save transcript to Documents directory with auto-generated filename
    /// - Returns: Result indicating success or failure
    func saveTranscriptToDocuments() -> TranscriptExportResult {
        transcript.end()
        return TranscriptExporter.exportToDocuments(transcript)
    }
    
    /// Save transcript to current directory with auto-generated filename
    /// - Returns: Result indicating success or failure
    func saveTranscriptToCurrentDirectory() -> TranscriptExportResult {
        transcript.end()
        return TranscriptExporter.exportToCurrentDirectory(transcript)
    }
    
    /// Display save result message
    func displaySaveResult(_ result: TranscriptExportResult) {
        switch result {
        case .success(let path):
            print("  ✅ Transcript saved to: \(path)")
        case .failure(let error):
            showError(message: error.description)
        }
    }
    
    // MARK: - Processing Indicator
    
    func showProcessingIndicator() {
        processingIndicator.start()
    }
    
    func hideProcessingIndicator() {
        processingIndicator.stop()
    }
    
    func updateProcessingIndicator() {
        processingIndicator.nextFrame()
    }
    
    // MARK: - Error Display
    
    func showError(message: String) {
        lastError = message
    }
    
    // MARK: - Input Management
    
    func setInput(_ input: String) {
        currentInput = input
    }
    
    func clearInput() {
        currentInput = ""
    }
    
    // MARK: - Screen Control
    
    func clearScreen() {
        // ANSI escape code to clear screen and move cursor to top
        print("\u{001B}[2J\u{001B}[H", terminator: "")
    }
    
    // MARK: - Private Helpers
    
    private func renderSeparator() {
        print(String(repeating: "═", count: terminalWidth))
    }
    
    private func renderDivider() {
        print(String(repeating: "─", count: terminalWidth))
    }
    
    private func centerText(_ text: String, width: Int) -> String {
        let padding = max(0, (width - text.count) / 2)
        return String(repeating: " ", count: padding) + text
    }

    
    private func renderTranscriptEntry(_ entry: TranscriptEntry) -> String {
        let timeStamp = "[\(entry.formattedTime)]"
        
        switch entry.source {
        case .system:
            // System audio on the left side
            // 🔊 [10:30:15] System Audio:
            // ⎿  Let's discuss the API design...
            let header = "  \(entry.source.icon) \(timeStamp) \(entry.source.label):"
            let content = "  ⎿  \(entry.text)"
            return "\(header)\n\(content)"
            
        case .microphone:
            // Microphone on the right side (right-aligned)
            // 🎤 [10:30:18] You:
            // ⎿  I think we should use REST...
            let header = "\(entry.source.icon) \(timeStamp) \(entry.source.label):"
            let content = "⎿  \(entry.text)"
            let rightPadding = max(0, terminalWidth - header.count - 2)
            let contentPadding = max(0, terminalWidth - content.count - 2)
            return "\(String(repeating: " ", count: rightPadding))\(header)\n\(String(repeating: " ", count: contentPadding))\(content)"
        }
    }
    
    private func renderLLMResponse(_ response: LLMResponseEntry) -> String {
        // LLM response in center with distinct styling
        // 🤖 LLM Response:
        // ⎿  Based on the discussion...
        let header = "  🤖 LLM Response:"
        let lines = response.content.split(separator: "\n", omittingEmptySubsequences: false)
        var result = header
        for line in lines {
            result += "\n  ⎿  \(line)"
        }
        return result
    }
}

// MARK: - Convenience Extensions

extension TUIEngine {
    /// Add a system audio transcript entry
    func addSystemAudioEntry(_ text: String) {
        let entry = TranscriptEntry(source: .system, text: text)
        appendTranscript(entry: entry)
    }
    
    /// Add a microphone transcript entry
    func addMicrophoneEntry(_ text: String) {
        let entry = TranscriptEntry(source: .microphone, text: text)
        appendTranscript(entry: entry)
    }
    
    /// Add an LLM response
    func addLLMResponse(_ content: String, model: String = "Ollama/Llama") {
        let response = LLMResponseEntry(content: content, model: model)
        appendLLMResponse(response)
    }
}
