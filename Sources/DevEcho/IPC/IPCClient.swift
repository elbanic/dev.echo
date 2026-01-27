import Foundation
import Logging

/// IPC Client for communicating with Python backend via Unix Domain Socket
actor IPCClient {
    private let socketPath: String
    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    private var isConnected = false
    private var logger: Logger
    
    // Pending LLM response continuation
    private var pendingLLMResponse: CheckedContinuation<LLMResponseMessage, Error>?
    
    static let defaultSocketPath = "/tmp/devecho.sock"
    
    init(socketPath: String = IPCClient.defaultSocketPath, debug: Bool = false) {
        self.socketPath = socketPath
        self.logger = Logger(label: "dev.echo.ipc")
        self.logger.logLevel = debug ? .debug : .warning
    }
    
    /// Update debug mode at runtime
    func setDebug(_ debug: Bool) {
        logger.logLevel = debug ? .debug : .warning
    }
    
    /// Connect to the Python backend IPC server
    func connect() async throws {
        guard !isConnected else { return }
        
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        
        CFStreamCreatePairWithSocketToHost(
            kCFAllocatorDefault,
            "localhost" as CFString,
            0,
            &readStream,
            &writeStream
        )
        
        // Create Unix socket streams
        _ = URL(fileURLWithPath: socketPath)
        
        Stream.getStreamsToHost(
            withName: socketPath,
            port: 0,
            inputStream: &inputStream,
            outputStream: &outputStream
        )
        
        // For Unix Domain Socket, we need to use a different approach
        let socket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socket >= 0 else {
            throw IPCError.connectionFailed("Failed to create socket")
        }
        
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        
        let pathBytes = socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                for (i, byte) in pathBytes.enumerated() {
                    dest[i] = byte
                }
            }
        }
        
        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(socket, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        
        guard connectResult == 0 else {
            close(socket)
            throw IPCError.connectionFailed("Failed to connect to \(socketPath)")
        }
        
        // Create streams from socket
        var readStreamRef: Unmanaged<CFReadStream>?
        var writeStreamRef: Unmanaged<CFWriteStream>?
        
        CFStreamCreatePairWithSocket(
            kCFAllocatorDefault,
            socket,
            &readStreamRef,
            &writeStreamRef
        )
        
        guard let readRef = readStreamRef, let writeRef = writeStreamRef else {
            close(socket)
            throw IPCError.connectionFailed("Failed to create streams")
        }
        
        inputStream = readRef.takeRetainedValue()
        outputStream = writeRef.takeRetainedValue()
        
        inputStream?.open()
        outputStream?.open()
        
        isConnected = true
        logger.info("Connected to IPC server at \(socketPath)")
    }
    
    /// Disconnect from the IPC server
    func disconnect() async {
        inputStream?.close()
        outputStream?.close()
        inputStream = nil
        outputStream = nil
        isConnected = false
        logger.info("Disconnected from IPC server")
    }
    
    /// Send a message to the Python backend
    func send(_ message: IPCMessage) async throws {
        guard isConnected, let output = outputStream else {
            throw IPCError.notConnected
        }
        
        let jsonData = try message.toJSON()
        let data = jsonData + "\n"
        
        guard let bytes = data.data(using: .utf8) else {
            throw IPCError.encodingFailed
        }
        
        // Write all bytes, handling partial writes
        var totalWritten = 0
        let totalBytes = bytes.count
        
        while totalWritten < totalBytes {
            let remaining = totalBytes - totalWritten
            let written = bytes.withUnsafeBytes { ptr in
                let basePtr = ptr.bindMemory(to: UInt8.self).baseAddress!
                return output.write(basePtr.advanced(by: totalWritten), maxLength: remaining)
            }
            
            if written < 0 {
                throw IPCError.sendFailed
            }
            
            if written == 0 {
                // Stream is full, wait a bit
                try await Task.sleep(nanoseconds: 1_000_000) // 1ms
                continue
            }
            
            totalWritten += written
        }
    }
    
    /// Receive a message from the Python backend
    func receive() async throws -> IPCMessage {
        guard isConnected, let input = inputStream else {
            throw IPCError.notConnected
        }
        
        var buffer = [UInt8](repeating: 0, count: 65536)
        var data = Data()
        
        while true {
            let bytesRead = input.read(&buffer, maxLength: buffer.count)
            
            if bytesRead < 0 {
                throw IPCError.receiveFailed
            }
            
            if bytesRead == 0 {
                throw IPCError.connectionClosed
            }
            
            data.append(contentsOf: buffer[0..<bytesRead])
            
            // Check for newline (message delimiter)
            if let newlineIndex = data.firstIndex(of: UInt8(ascii: "\n")) {
                let messageData = data[..<newlineIndex]
                guard let jsonString = String(data: messageData, encoding: .utf8) else {
                    throw IPCError.decodingFailed
                }
                return try IPCMessage.fromJSON(jsonString)
            }
        }
    }
    
    /// Send audio data to the transcription engine
    func sendAudioData(_ buffer: AudioBuffer) async throws {
        let message = IPCMessage(
            type: .audioData,
            payload: [
                "samples_base64": buffer.samplesToBase64(),
                "sample_rate": buffer.sampleRate,
                "timestamp": buffer.timestamp.timeIntervalSince1970,
                "source": buffer.source.rawValue
            ]
        )
        try await send(message)
    }
    
    /// Send LLM query and receive response
    func sendLLMQuery(type: String, content: String, context: [TranscriptionMessage]) async throws -> LLMResponseMessage {
        let contextDicts = context.map { msg -> [String: Any] in
            [
                "text": msg.text,
                "source": msg.source,
                "timestamp": msg.timestamp
            ]
        }
        
        let message = IPCMessage(
            type: .llmQuery,
            payload: [
                "query_type": type,
                "content": content,
                "context": contextDicts
            ]
        )
        
        // Use continuation to wait for response from startListening
        return try await withCheckedThrowingContinuation { continuation in
            self.pendingLLMResponse = continuation
            
            Task {
                do {
                    try await self.send(message)
                } catch {
                    self.pendingLLMResponse = nil
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Phase 2: Cloud LLM Methods
    
    /// Pending Cloud LLM response continuation
    private var pendingCloudLLMResponse: CheckedContinuation<CloudLLMResponseMessage, Error>?
    
    /// Send Cloud LLM query with RAG support (Phase 2)
    /// Requirements: 6.1, 6.2
    func sendCloudLLMQuery(content: String, context: [TranscriptionMessage], forceRag: Bool = false) async throws -> CloudLLMResponseMessage {
        let queryMessage = CloudLLMQueryMessage(content: content, context: context, forceRag: forceRag)
        let message = queryMessage.toIPCMessage()
        
        return try await withCheckedThrowingContinuation { continuation in
            self.pendingCloudLLMResponse = continuation
            
            Task {
                do {
                    try await self.send(message)
                } catch {
                    self.pendingCloudLLMResponse = nil
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Phase 2: KB Methods
    
    /// Pending KB list response continuation
    private var pendingKBListResponse: CheckedContinuation<KBListResponseMessage, Error>?
    
    /// Pending KB operation response continuation
    private var pendingKBResponse: CheckedContinuation<KBResponseMessage, Error>?
    
    /// Pending KB sync status response continuation
    private var pendingKBSyncStatusResponse: CheckedContinuation<KBSyncStatusMessage, Error>?
    
    /// List KB documents with pagination (Phase 2)
    /// Requirements: 2.1, 2.4
    func listKBDocuments(continuationToken: String? = nil, maxItems: Int = 20) async throws -> KBListResponseMessage {
        let requestMessage = KBListRequestMessage(continuationToken: continuationToken, maxItems: maxItems)
        let message = requestMessage.toIPCMessage()
        
        try await send(message)
        
        // Wait for response directly
        let response = try await receive()
        
        if response.type == .kbError {
            if let errorMsg = KBErrorMessage.fromPayload(response.payload) {
                throw IPCError.kbError(errorMsg)
            }
            throw IPCError.unexpectedResponse
        }
        
        guard response.type == .kbListResponse,
              let listResponse = KBListResponseMessage.fromPayload(response.payload) else {
            logger.error("Unexpected response type: \(response.type), payload: \(response.payload)")
            throw IPCError.unexpectedResponse
        }
        
        return listResponse
    }
    
    /// Add document to KB (Phase 2)
    /// Requirements: 3.1, 3.2
    func addKBDocument(sourcePath: String, name: String) async throws -> KBResponseMessage {
        let addMessage = KBAddMessage(sourcePath: sourcePath, name: name)
        let message = addMessage.toIPCMessage()
        
        try await send(message)
        
        let response = try await receive()
        
        if response.type == .kbError {
            if let errorMsg = KBErrorMessage.fromPayload(response.payload) {
                throw IPCError.kbError(errorMsg)
            }
            throw IPCError.unexpectedResponse
        }
        
        guard response.type == .kbResponse,
              let kbResponse = KBResponseMessage.fromPayload(response.payload) else {
            throw IPCError.unexpectedResponse
        }
        
        return kbResponse
    }
    
    /// Update document in KB (Phase 2)
    /// Requirements: 4.1, 4.2
    func updateKBDocument(sourcePath: String, name: String) async throws -> KBResponseMessage {
        let updateMessage = KBUpdateMessage(sourcePath: sourcePath, name: name)
        let message = updateMessage.toIPCMessage()
        
        try await send(message)
        
        let response = try await receive()
        
        if response.type == .kbError {
            if let errorMsg = KBErrorMessage.fromPayload(response.payload) {
                throw IPCError.kbError(errorMsg)
            }
            throw IPCError.unexpectedResponse
        }
        
        guard response.type == .kbResponse,
              let kbResponse = KBResponseMessage.fromPayload(response.payload) else {
            throw IPCError.unexpectedResponse
        }
        
        return kbResponse
    }
    
    /// Remove document from KB (Phase 2)
    /// Requirements: 5.1
    func removeKBDocument(name: String) async throws -> KBResponseMessage {
        let removeMessage = KBRemoveMessage(name: name)
        let message = removeMessage.toIPCMessage()
        
        try await send(message)
        
        let response = try await receive()
        
        if response.type == .kbError {
            if let errorMsg = KBErrorMessage.fromPayload(response.payload) {
                throw IPCError.kbError(errorMsg)
            }
            throw IPCError.unexpectedResponse
        }
        
        guard response.type == .kbResponse,
              let kbResponse = KBResponseMessage.fromPayload(response.payload) else {
            throw IPCError.unexpectedResponse
        }
        
        return kbResponse
    }
    
    /// Get KB sync status (Phase 2)
    /// Requirements: 11.3, 11.5
    func getKBSyncStatus() async throws -> KBSyncStatusMessage {
        let message = IPCMessage(type: .kbSyncStatus, payload: [:])
        
        try await send(message)
        
        let response = try await receive()
        
        if response.type == .kbError {
            if let errorMsg = KBErrorMessage.fromPayload(response.payload) {
                throw IPCError.kbError(errorMsg)
            }
            throw IPCError.unexpectedResponse
        }
        
        guard response.type == .kbSyncStatus,
              let statusResponse = KBSyncStatusMessage.fromPayload(response.payload) else {
            throw IPCError.unexpectedResponse
        }
        
        return statusResponse
    }
    
    /// Trigger KB sync (Phase 2)
    /// Requirements: 5.2
    func triggerKBSync() async throws -> KBSyncTriggerResponseMessage {
        let triggerMessage = KBSyncTriggerMessage()
        let message = triggerMessage.toIPCMessage()
        
        try await send(message)
        
        // Wait for response
        let response = try await receive()
        guard response.type == .kbResponse,
              let triggerResponse = KBSyncTriggerResponseMessage.fromPayload(response.payload) else {
            throw IPCError.unexpectedResponse
        }
        
        return triggerResponse
    }
    
    /// Start listening for incoming messages (transcriptions, etc.)
    func startListening(onTranscription: @escaping @Sendable (TranscriptionMessage) -> Void) async {
        guard isConnected, let input = inputStream else {
            logger.error("Cannot start listening: not connected")
            return
        }
        
        logger.debug("Starting to listen for transcriptions...")
        
        var buffer = Data()
        var readBuffer = [UInt8](repeating: 0, count: 4096)
        
        while isConnected {
            // Check if data is available
            if input.hasBytesAvailable {
                let bytesRead = input.read(&readBuffer, maxLength: readBuffer.count)
                
                if bytesRead > 0 {
                    buffer.append(contentsOf: readBuffer[0..<bytesRead])
                    
                    // Process complete messages
                    while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                        let messageData = buffer[..<newlineIndex]
                        buffer = Data(buffer[(newlineIndex + 1)...])
                        
                        if let jsonString = String(data: messageData, encoding: .utf8) {
                            logger.debug("Received message: \(jsonString.prefix(100))...")
                            
                            if let message = try? IPCMessage.fromJSON(jsonString) {
                                // Handle transcription messages
                                if message.type == .transcription,
                                   let transcription = TranscriptionMessage.fromPayload(message.payload) {
                                    logger.debug("Got transcription: \(transcription.text)")
                                    onTranscription(transcription)
                                }
                                // Handle LLM response messages (Phase 1 - Local LLM)
                                else if message.type == .llmResponse {
                                    let response = LLMResponseMessage(
                                        content: message.payload["content"] as? String ?? "",
                                        model: message.payload["model"] as? String ?? "unknown"
                                    )
                                    logger.debug("Got LLM response: \(response.content.prefix(50))...")
                                    
                                    // Resume pending continuation if exists
                                    if let continuation = pendingLLMResponse {
                                        pendingLLMResponse = nil
                                        continuation.resume(returning: response)
                                    }
                                }
                                // Handle Cloud LLM response messages (Phase 2)
                                else if message.type == .cloudLLMResponse {
                                    if let response = CloudLLMResponseMessage.fromPayload(message.payload) {
                                        logger.debug("Got Cloud LLM response: \(response.content.prefix(50))...")
                                        
                                        if let continuation = pendingCloudLLMResponse {
                                            pendingCloudLLMResponse = nil
                                            continuation.resume(returning: response)
                                        }
                                    }
                                }
                                // Handle Cloud LLM error messages (Phase 2)
                                else if message.type == .cloudLLMError {
                                    if let errorMsg = CloudLLMErrorMessage.fromPayload(message.payload) {
                                        logger.error("Cloud LLM error: \(errorMsg.error)")
                                        
                                        if let continuation = pendingCloudLLMResponse {
                                            pendingCloudLLMResponse = nil
                                            continuation.resume(throwing: IPCError.cloudLLMError(errorMsg))
                                        }
                                    }
                                }
                                // Handle KB list response messages (Phase 2)
                                else if message.type == .kbListResponse {
                                    logger.debug("Parsing KB list response payload: \(message.payload)")
                                    if let response = KBListResponseMessage.fromPayload(message.payload) {
                                        logger.debug("Got KB list response: \(response.documents.count) documents")
                                        
                                        if let continuation = pendingKBListResponse {
                                            pendingKBListResponse = nil
                                            continuation.resume(returning: response)
                                        }
                                    } else {
                                        logger.error("Failed to parse KB list response from payload")
                                        if let continuation = pendingKBListResponse {
                                            pendingKBListResponse = nil
                                            continuation.resume(throwing: IPCError.decodingFailed)
                                        }
                                    }
                                }
                                // Handle KB operation response messages (Phase 2)
                                else if message.type == .kbResponse {
                                    if let response = KBResponseMessage.fromPayload(message.payload) {
                                        logger.debug("Got KB response: \(response.message)")
                                        
                                        if let continuation = pendingKBResponse {
                                            pendingKBResponse = nil
                                            continuation.resume(returning: response)
                                        }
                                    }
                                }
                                // Handle KB error messages (Phase 2)
                                else if message.type == .kbError {
                                    if let errorMsg = KBErrorMessage.fromPayload(message.payload) {
                                        logger.error("KB error: \(errorMsg.error)")
                                        
                                        if let continuation = pendingKBResponse {
                                            pendingKBResponse = nil
                                            continuation.resume(throwing: IPCError.kbError(errorMsg))
                                        }
                                        if let continuation = pendingKBListResponse {
                                            pendingKBListResponse = nil
                                            continuation.resume(throwing: IPCError.kbError(errorMsg))
                                        }
                                    }
                                }
                                // Handle KB sync status messages (Phase 2)
                                else if message.type == .kbSyncStatus {
                                    if let status = KBSyncStatusMessage.fromPayload(message.payload) {
                                        logger.debug("Got KB sync status: \(status.status)")
                                        
                                        if let continuation = pendingKBSyncStatusResponse {
                                            pendingKBSyncStatusResponse = nil
                                            continuation.resume(returning: status)
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else if bytesRead < 0 {
                    logger.error("Error reading from stream")
                    break
                }
            }
            
            // Small delay to prevent busy-waiting
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }
        
        logger.debug("Stopped listening")
    }
    
    /// Check if connected
    var connected: Bool {
        isConnected
    }
}

// MARK: - Error Types

enum IPCError: Error, LocalizedError {
    case connectionFailed(String)
    case notConnected
    case encodingFailed
    case decodingFailed
    case sendFailed
    case receiveFailed
    case connectionClosed
    case unexpectedResponse
    
    // Phase 2 error types
    case cloudLLMError(CloudLLMErrorMessage)
    case kbError(KBErrorMessage)
    
    var errorDescription: String? {
        switch self {
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .notConnected:
            return "Not connected to IPC server"
        case .encodingFailed:
            return "Failed to encode message"
        case .decodingFailed:
            return "Failed to decode message"
        case .sendFailed:
            return "Failed to send message"
        case .receiveFailed:
            return "Failed to receive message"
        case .connectionClosed:
            return "Connection closed by server"
        case .unexpectedResponse:
            return "Received unexpected response type"
        case .cloudLLMError(let errorMsg):
            return "Cloud LLM error: \(errorMsg.error)"
        case .kbError(let errorMsg):
            return "KB error: \(errorMsg.error)"
        }
    }
    
    /// Get suggestion for Cloud LLM errors (Phase 2)
    var suggestion: String? {
        switch self {
        case .cloudLLMError(let errorMsg):
            return errorMsg.suggestion
        default:
            return nil
        }
    }
}
