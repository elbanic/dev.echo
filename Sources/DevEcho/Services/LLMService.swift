import Foundation

/// LLM query service
/// Handles local (Ollama) and cloud (Bedrock) LLM queries via IPC
/// Requirements: 3.3, 3.4, 6.1, 6.2 - LLM queries
final class LLMService {
    private let ipcClient: IPCClient
    
    init(ipcClient: IPCClient) {
        self.ipcClient = ipcClient
    }
    
    /// Execute local LLM query (Ollama)
    /// Requirements: 3.3, 3.4 - Local LLM queries
    func executeLocalQuery(type: String, content: String, context: [TranscriptionMessage]) async throws -> LLMQueryResult {
        let startTime = Date()
        
        let response = try await ipcClient.sendLLMQuery(
            type: type,
            content: content,
            context: context
        )
        
        let elapsed = Date().timeIntervalSince(startTime)
        
        return LLMQueryResult(
            content: response.content,
            model: response.model,
            elapsed: elapsed,
            usedRag: false,
            sources: []
        )
    }
    
    /// Execute cloud LLM query (Bedrock) with optional RAG
    /// Requirements: 6.1, 6.2, 6.3, 6.6 - Cloud LLM queries with sources
    func executeCloudQuery(content: String, context: [TranscriptionMessage], forceRag: Bool = false) async throws -> LLMQueryResult {
        let startTime = Date()
        
        let response = try await ipcClient.sendCloudLLMQuery(
            content: content,
            context: context,
            forceRag: forceRag
        )
        
        let elapsed = Date().timeIntervalSince(startTime)
        
        return LLMQueryResult(
            content: response.content,
            model: response.model,
            elapsed: elapsed,
            usedRag: response.usedRag,
            sources: response.sources
        )
    }
}

// MARK: - Result Types

struct LLMQueryResult {
    let content: String
    let model: String
    let elapsed: TimeInterval
    let usedRag: Bool
    let sources: [String]
}
