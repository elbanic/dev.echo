import Foundation

// MARK: - Message Types

/// IPC message types for Swift-Python communication
enum MessageType: String, Codable {
    // Audio messages
    case audioData = "audio_data"
    
    // Transcription messages
    case transcription = "transcription"
    case transcriptionError = "transcription_error"
    
    // LLM messages (Phase 1 - Local LLM)
    case llmQuery = "llm_query"
    case llmResponse = "llm_response"
    case llmError = "llm_error"
    
    // Cloud LLM messages (Phase 2)
    case cloudLLMQuery = "cloud_llm_query"
    case cloudLLMResponse = "cloud_llm_response"
    case cloudLLMError = "cloud_llm_error"
    
    // Knowledge Base messages
    case kbList = "kb_list"
    case kbListResponse = "kb_list_response"
    case kbAdd = "kb_add"
    case kbUpdate = "kb_update"
    case kbRemove = "kb_remove"
    case kbResponse = "kb_response"
    case kbError = "kb_error"
    
    // Knowledge Base sync messages (Phase 2)
    case kbSyncStatus = "kb_sync_status"
    case kbSyncTrigger = "kb_sync_trigger"
    
    // Control messages
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

// MARK: - Phase 2: Cloud LLM Types

/// Cloud LLM query message with RAG support (Phase 2)
/// Requirements: 6.1, 6.2
struct CloudLLMQueryMessage {
    let content: String
    let context: [TranscriptionMessage]
    let forceRag: Bool
    
    init(content: String, context: [TranscriptionMessage], forceRag: Bool = false) {
        self.content = content
        self.context = context
        self.forceRag = forceRag
    }
    
    func toIPCMessage() -> IPCMessage {
        let contextDicts = context.map { msg -> [String: Any] in
            [
                "text": msg.text,
                "source": msg.source,
                "timestamp": msg.timestamp
            ]
        }
        
        return IPCMessage(
            type: .cloudLLMQuery,
            payload: [
                "content": content,
                "context": contextDicts,
                "force_rag": forceRag
            ]
        )
    }
}

/// Cloud LLM response message with sources (Phase 2)
/// Requirements: 6.2, 6.6
struct CloudLLMResponseMessage {
    let content: String
    let model: String
    let sources: [String]
    let tokensUsed: Int
    let usedRag: Bool
    
    init(content: String, model: String, sources: [String] = [], tokensUsed: Int = 0, usedRag: Bool = false) {
        self.content = content
        self.model = model
        self.sources = sources
        self.tokensUsed = tokensUsed
        self.usedRag = usedRag
    }
    
    static func fromPayload(_ payload: [String: Any]) -> CloudLLMResponseMessage? {
        guard let content = payload["content"] as? String,
              let model = payload["model"] as? String else {
            return nil
        }
        
        let sources = payload["sources"] as? [String] ?? []
        let tokensUsed = payload["tokens_used"] as? Int ?? 0
        let usedRag = payload["used_rag"] as? Bool ?? false
        
        return CloudLLMResponseMessage(
            content: content,
            model: model,
            sources: sources,
            tokensUsed: tokensUsed,
            usedRag: usedRag
        )
    }
}

/// Cloud LLM error message (Phase 2)
/// Requirements: 6.5
struct CloudLLMErrorMessage {
    let error: String
    let errorType: String  // "credentials", "service_unavailable", "throttling", "model_error", "other"
    let suggestion: String?
    
    init(error: String, errorType: String, suggestion: String? = nil) {
        self.error = error
        self.errorType = errorType
        self.suggestion = suggestion
    }
    
    static func fromPayload(_ payload: [String: Any]) -> CloudLLMErrorMessage? {
        guard let error = payload["error"] as? String else {
            return nil
        }
        
        let errorType = payload["error_type"] as? String ?? "other"
        let suggestion = payload["suggestion"] as? String
        
        return CloudLLMErrorMessage(
            error: error,
            errorType: errorType,
            suggestion: suggestion
        )
    }
}

// MARK: - Phase 2: KB Types with S3 Pagination

/// KB document info from S3 (Phase 2)
/// Requirements: 2.1
struct KBDocumentInfo {
    let name: String
    let key: String
    let sizeBytes: Int
    let lastModified: Double
    let etag: String?
    
    init(name: String, key: String, sizeBytes: Int, lastModified: Double, etag: String? = nil) {
        self.name = name
        self.key = key
        self.sizeBytes = sizeBytes
        self.lastModified = lastModified
        self.etag = etag
    }
    
    static func fromDict(_ dict: [String: Any]) -> KBDocumentInfo? {
        guard let name = dict["name"] as? String,
              let key = dict["key"] as? String,
              let sizeBytes = dict["size_bytes"] as? Int,
              let lastModified = dict["last_modified"] as? Double else {
            return nil
        }
        
        let etag = dict["etag"] as? String
        
        return KBDocumentInfo(
            name: name,
            key: key,
            sizeBytes: sizeBytes,
            lastModified: lastModified,
            etag: etag
        )
    }
    
    /// Format size for display (e.g., "2.3 KB")
    var formattedSize: String {
        if sizeBytes < 1024 {
            return "\(sizeBytes) B"
        } else if sizeBytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(sizeBytes) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(sizeBytes) / (1024.0 * 1024.0))
        }
    }
    
    /// Format last modified date for display
    var formattedDate: String {
        let date = Date(timeIntervalSince1970: lastModified)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

/// KB list request message with pagination (Phase 2)
/// Requirements: 2.4
struct KBListRequestMessage {
    let continuationToken: String?
    let maxItems: Int
    
    init(continuationToken: String? = nil, maxItems: Int = 20) {
        self.continuationToken = continuationToken
        self.maxItems = maxItems
    }
    
    func toIPCMessage() -> IPCMessage {
        var payload: [String: Any] = ["max_items": maxItems]
        if let token = continuationToken {
            payload["continuation_token"] = token
        }
        return IPCMessage(type: .kbList, payload: payload)
    }
}

/// KB list response message with pagination (Phase 2)
/// Requirements: 2.4
struct KBListResponseMessage {
    let documents: [KBDocumentInfo]
    let hasMore: Bool
    let continuationToken: String?
    
    init(documents: [KBDocumentInfo], hasMore: Bool, continuationToken: String? = nil) {
        self.documents = documents
        self.hasMore = hasMore
        self.continuationToken = continuationToken
    }
    
    static func fromPayload(_ payload: [String: Any]) -> KBListResponseMessage? {
        guard let docDicts = payload["documents"] as? [[String: Any]] else {
            return nil
        }
        
        let documents = docDicts.compactMap { KBDocumentInfo.fromDict($0) }
        let hasMore = payload["has_more"] as? Bool ?? false
        let continuationToken = payload["continuation_token"] as? String
        
        return KBListResponseMessage(
            documents: documents,
            hasMore: hasMore,
            continuationToken: continuationToken
        )
    }
}

/// KB add/update/remove request messages (Phase 2)
struct KBAddMessage {
    let sourcePath: String
    let name: String
    
    func toIPCMessage() -> IPCMessage {
        return IPCMessage(
            type: .kbAdd,
            payload: ["source_path": sourcePath, "name": name]
        )
    }
}

struct KBUpdateMessage {
    let sourcePath: String
    let name: String
    
    func toIPCMessage() -> IPCMessage {
        return IPCMessage(
            type: .kbUpdate,
            payload: ["source_path": sourcePath, "name": name]
        )
    }
}

struct KBRemoveMessage {
    let name: String
    
    func toIPCMessage() -> IPCMessage {
        return IPCMessage(
            type: .kbRemove,
            payload: ["name": name]
        )
    }
}

/// KB operation response message (Phase 2)
struct KBResponseMessage {
    let success: Bool
    let message: String
    let document: KBDocumentInfo?
    
    init(success: Bool, message: String, document: KBDocumentInfo? = nil) {
        self.success = success
        self.message = message
        self.document = document
    }
    
    static func fromPayload(_ payload: [String: Any]) -> KBResponseMessage? {
        guard let success = payload["success"] as? Bool,
              let message = payload["message"] as? String else {
            return nil
        }
        
        var document: KBDocumentInfo? = nil
        if let docDict = payload["document"] as? [String: Any] {
            document = KBDocumentInfo.fromDict(docDict)
        }
        
        return KBResponseMessage(
            success: success,
            message: message,
            document: document
        )
    }
}

/// KB error message (Phase 2)
struct KBErrorMessage {
    let error: String
    let errorType: String  // "not_found", "invalid_markdown", "exists", "other"
    
    init(error: String, errorType: String) {
        self.error = error
        self.errorType = errorType
    }
    
    static func fromPayload(_ payload: [String: Any]) -> KBErrorMessage? {
        guard let error = payload["error"] as? String else {
            return nil
        }
        
        let errorType = payload["error_type"] as? String ?? "other"
        
        return KBErrorMessage(error: error, errorType: errorType)
    }
}

// MARK: - Phase 2: KB Sync Types

/// KB sync status message (Phase 2)
/// Requirements: 11.3, 11.5
struct KBSyncStatusMessage {
    let status: String  // "SYNCING", "READY", "FAILED", "UNKNOWN"
    let documentCount: Int
    let lastSync: Double?
    let errorMessage: String?
    
    init(status: String, documentCount: Int, lastSync: Double? = nil, errorMessage: String? = nil) {
        self.status = status
        self.documentCount = documentCount
        self.lastSync = lastSync
        self.errorMessage = errorMessage
    }
    
    static func fromPayload(_ payload: [String: Any]) -> KBSyncStatusMessage? {
        guard let status = payload["status"] as? String else {
            return nil
        }
        
        let documentCount = payload["document_count"] as? Int ?? 0
        let lastSync = payload["last_sync"] as? Double
        let errorMessage = payload["error_message"] as? String
        
        return KBSyncStatusMessage(
            status: status,
            documentCount: documentCount,
            lastSync: lastSync,
            errorMessage: errorMessage
        )
    }
    
    /// Check if KB is ready for queries
    var isReady: Bool {
        return status == "READY"
    }
    
    /// Format last sync time for display
    var formattedLastSync: String? {
        guard let lastSync = lastSync else { return nil }
        let date = Date(timeIntervalSince1970: lastSync)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
    
    /// Status icon for display
    var statusIcon: String {
        switch status {
        case "READY": return "✅"
        case "SYNCING": return "🔄"
        case "FAILED": return "❌"
        default: return "❓"
        }
    }
}

/// KB sync trigger request message (Phase 2)
struct KBSyncTriggerMessage {
    func toIPCMessage() -> IPCMessage {
        return IPCMessage(type: .kbSyncTrigger, payload: [:])
    }
}

/// KB sync trigger response message (Phase 2)
struct KBSyncTriggerResponseMessage {
    let success: Bool
    let ingestionJobId: String?
    let message: String
    
    init(success: Bool, ingestionJobId: String? = nil, message: String = "") {
        self.success = success
        self.ingestionJobId = ingestionJobId
        self.message = message
    }
    
    static func fromPayload(_ payload: [String: Any]) -> KBSyncTriggerResponseMessage? {
        guard let success = payload["success"] as? Bool else {
            return nil
        }
        
        let ingestionJobId = payload["ingestion_job_id"] as? String
        let message = payload["message"] as? String ?? ""
        
        return KBSyncTriggerResponseMessage(
            success: success,
            ingestionJobId: ingestionJobId,
            message: message
        )
    }
}
