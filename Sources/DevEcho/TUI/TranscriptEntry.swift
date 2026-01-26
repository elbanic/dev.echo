import Foundation

/// Represents a single entry in the transcript display
struct TranscriptEntry: Equatable, Identifiable {
    let id: UUID
    let timestamp: Date
    let source: AudioSource
    let text: String
    let isLLMResponse: Bool
    
    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        source: AudioSource,
        text: String,
        isLLMResponse: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.text = text
        self.isLLMResponse = isLLMResponse
    }
    
    /// Format timestamp as HH:mm:ss
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }
    
    /// Format timestamp for markdown export (YYYY-MM-DD HH:mm:ss)
    var markdownTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: timestamp)
    }
    
    /// Speaker label for markdown export
    var speakerLabel: String {
        if isLLMResponse {
            return "🤖 LLM"
        }
        switch source {
        case .system:
            return "🔊 System Audio"
        case .microphone:
            return "🎤 You"
        }
    }
}

/// LLM response entry (displayed in center with distinct styling)
struct LLMResponseEntry: Equatable, Identifiable {
    let id: UUID
    let timestamp: Date
    let content: String
    let model: String
    
    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        content: String,
        model: String = "Ollama/Llama"
    ) {
        self.id = id
        self.timestamp = timestamp
        self.content = content
        self.model = model
    }
    
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }
    
    /// Format timestamp for markdown export
    var markdownTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: timestamp)
    }
}

// MARK: - Transcript Model

/// Represents a complete transcript session with all entries
struct Transcript: Identifiable {
    let id: UUID
    private(set) var entries: [TranscriptEntry]
    private(set) var llmResponses: [LLMResponseEntry]
    let startTime: Date
    var endTime: Date?
    
    init(
        id: UUID = UUID(),
        entries: [TranscriptEntry] = [],
        llmResponses: [LLMResponseEntry] = [],
        startTime: Date = Date(),
        endTime: Date? = nil
    ) {
        self.id = id
        self.entries = entries
        self.llmResponses = llmResponses
        self.startTime = startTime
        self.endTime = endTime
    }
    
    /// Add a transcript entry, maintaining chronological order
    mutating func addEntry(_ entry: TranscriptEntry) {
        entries.append(entry)
        entries.sort { $0.timestamp < $1.timestamp }
    }
    
    /// Add an LLM response entry, maintaining chronological order
    mutating func addLLMResponse(_ response: LLMResponseEntry) {
        llmResponses.append(response)
        llmResponses.sort { $0.timestamp < $1.timestamp }
    }
    
    /// Get all entries (transcript + LLM) sorted by timestamp
    var allEntriesSorted: [Any] {
        var combined: [(date: Date, entry: Any)] = []
        
        for entry in entries {
            combined.append((entry.timestamp, entry))
        }
        for response in llmResponses {
            combined.append((response.timestamp, response))
        }
        
        combined.sort { $0.date < $1.date }
        return combined.map { $0.entry }
    }
    
    /// Mark the transcript as ended
    mutating func end() {
        endTime = Date()
    }
    
    /// Total entry count
    var totalEntryCount: Int {
        entries.count + llmResponses.count
    }
    
    /// Check if transcript is empty
    var isEmpty: Bool {
        entries.isEmpty && llmResponses.isEmpty
    }
    
    /// Duration of the transcript session
    var duration: TimeInterval? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(startTime)
    }
    
    /// Format duration as human-readable string
    var formattedDuration: String? {
        guard let duration = duration else { return nil }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // MARK: - Markdown Export
    
    /// Convert transcript to markdown format
    func toMarkdown() -> String {
        var markdown = "# Transcript\n\n"
        
        // Header with session info
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        markdown += "**Session Start:** \(dateFormatter.string(from: startTime))\n"
        if let end = endTime {
            markdown += "**Session End:** \(dateFormatter.string(from: end))\n"
        }
        if let duration = formattedDuration {
            markdown += "**Duration:** \(duration)\n"
        }
        markdown += "\n---\n\n"
        
        // Combine and sort all entries
        var allItems: [(date: Date, markdown: String)] = []
        
        for entry in entries {
            let line = "**[\(entry.markdownTimestamp)]** \(entry.speakerLabel)\n\n\(entry.text)\n"
            allItems.append((entry.timestamp, line))
        }
        
        for response in llmResponses {
            let line = "**[\(response.markdownTimestamp)]** 🤖 LLM (\(response.model))\n\n\(response.content)\n"
            allItems.append((response.timestamp, line))
        }
        
        // Sort by timestamp
        allItems.sort { $0.date < $1.date }
        
        // Append all entries
        for item in allItems {
            markdown += item.markdown + "\n"
        }
        
        return markdown
    }
}
