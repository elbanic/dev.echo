import Foundation

// MARK: - Message Types

/// IPC message types for Swift-Python communication
enum MessageType: String, Codable {
    case audioData = "audio_data"
    case transcription = "transcription"
    case transcriptionError = "transcription_error"
    case llmQuery = "llm_query"
    case llmResponse = "llm_response"
    case llmError = "llm_error"
    case ping = "ping"
    case pong = "pong"
    case shutdown = "shutdown"
    case ack = "ack"
}

// MARK: - IPC Message

/// Base IPC message structure
struct IPCMessage {
    let type: MessageType
    let payload: [String: Any]
    
    func toJSON() throws -> String {
        let dict: [String: Any] = [
            "type": type.rawValue,
            "payload": payload
        ]
        let data = try JSONSerialization.data(withJSONObject: dict)
        guard let json = String(data: data, encoding: .utf8) else {
            throw IPCError.encodingFailed
        }
        return json
    }
    
    static func fromJSON(_ json: String) throws -> IPCMessage {
        guard let data = json.data(using: .utf8) else {
            throw IPCError.decodingFailed
        }
        
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let typeString = dict["type"] as? String,
              let type = MessageType(rawValue: typeString) else {
            throw IPCError.decodingFailed
        }
        
        let payload = dict["payload"] as? [String: Any] ?? [:]
        return IPCMessage(type: type, payload: payload)
    }
}

// MARK: - Audio Types

/// Audio source identification
enum AudioSource: String, Codable, Equatable {
    case system = "system"
    case microphone = "microphone"
    
    /// Icon for TUI display
    var icon: String {
        switch self {
        case .system: return "🔊"
        case .microphone: return "🎤"
        }
    }
    
    /// Label for TUI display
    var label: String {
        switch self {
        case .system: return "System Audio"
        case .microphone: return "You"
        }
    }
}

/// Audio buffer for IPC transmission
struct AudioBuffer {
    let samples: [Float]
    let sampleRate: Int
    let timestamp: Date
    let source: AudioSource
    
    /// Convert samples to Base64 encoded string for efficient transmission
    func samplesToBase64() -> String {
        let data = samples.withUnsafeBufferPointer { ptr in
            Data(buffer: ptr)
        }
        return data.base64EncodedString()
    }
}

// MARK: - Transcription Types

/// Transcription message from Python backend
struct TranscriptionMessage {
    let text: String
    let source: String
    let timestamp: Double
    let confidence: Double
    
    init(text: String, source: String, timestamp: Double, confidence: Double = 1.0) {
        self.text = text
        self.source = source
        self.timestamp = timestamp
        self.confidence = confidence
    }
    
    static func fromPayload(_ payload: [String: Any]) -> TranscriptionMessage? {
        guard let text = payload["text"] as? String,
              let source = payload["source"] as? String,
              let timestamp = payload["timestamp"] as? Double else {
            return nil
        }
        
        let confidence = payload["confidence"] as? Double ?? 1.0
        return TranscriptionMessage(
            text: text,
            source: source,
            timestamp: timestamp,
            confidence: confidence
        )
    }
}

// MARK: - LLM Types

/// LLM response message from Python backend
struct LLMResponseMessage {
    let content: String
    let model: String
    let tokensUsed: Int
    
    init(content: String, model: String, tokensUsed: Int = 0) {
        self.content = content
        self.model = model
        self.tokensUsed = tokensUsed
    }
    
    static func fromPayload(_ payload: [String: Any]) -> LLMResponseMessage? {
        guard let content = payload["content"] as? String,
              let model = payload["model"] as? String else {
            return nil
        }
        
        let tokensUsed = payload["tokens_used"] as? Int ?? 0
        return LLMResponseMessage(
            content: content,
            model: model,
            tokensUsed: tokensUsed
        )
    }
}
