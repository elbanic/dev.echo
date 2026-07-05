import Foundation

/// Knowledge Base management service
/// Handles all KB CRUD operations via IPC
/// Requirements: 2.1-2.4, 3.1-3.5, 4.1-4.4, 5.1-5.4 - KB Management
final class KBService {
    private let ipcClient: IPCClient
    private var lastContinuationToken: String?
    
    init(ipcClient: IPCClient) {
        self.ipcClient = ipcClient
    }
    
    /// Get the last continuation token for pagination
    var continuationToken: String? {
        lastContinuationToken
    }
    
    /// List all KB documents with pagination
    /// Requirements: 2.1, 2.3, 2.4 - List documents with pagination
    func listDocuments(continuationToken: String? = nil) async throws -> KBListResult {
        let response = try await ipcClient.listKBDocuments(
            continuationToken: continuationToken,
            maxItems: 20
        )
        
        // Store token for /more command
        lastContinuationToken = response.hasMore ? response.continuationToken : nil
        
        return KBListResult(
            documents: response.documents,
            hasMore: response.hasMore
        )
    }
    
    /// Add document to KB
    /// Requirements: 3.1-3.5: Add markdown file with validation
    func addDocument(fromPath: String, name: String) async throws -> KBOperationResult {
        // Validate markdown file
        let validation = validateMarkdownPath(fromPath)
        guard validation.isValid else {
            return KBOperationResult(success: false, message: validation.error!, document: nil)
        }
        
        let response = try await ipcClient.addKBDocument(
            sourcePath: validation.expandedPath!,
            name: name
        )
        
        return KBOperationResult(
            success: response.success,
            message: response.message,
            document: response.document
        )
    }
    
    /// Update existing KB document
    /// Requirements: 4.1-4.4: Update document with validation
    func updateDocument(fromPath: String, name: String) async throws -> KBOperationResult {
        // Validate markdown file
        let validation = validateMarkdownPath(fromPath)
        guard validation.isValid else {
            return KBOperationResult(success: false, message: validation.error!, document: nil)
        }
        
        let response = try await ipcClient.updateKBDocument(
            sourcePath: validation.expandedPath!,
            name: name
        )
        
        return KBOperationResult(
            success: response.success,
            message: response.message,
            document: response.document
        )
    }
    
    /// Remove document from KB
    /// Requirements: 5.1-5.3: Delete document
    func removeDocument(name: String) async throws -> KBOperationResult {
        let response = try await ipcClient.removeKBDocument(name: name)
        
        return KBOperationResult(
            success: response.success,
            message: response.message,
            document: nil
        )
    }
    
    /// Trigger KB sync/indexing
    /// Requirements: 5.2 - Trigger Bedrock KB reindexing
    func triggerSync() async throws -> KBSyncResult {
        let response = try await ipcClient.triggerKBSync()
        
        return KBSyncResult(
            success: response.success,
            message: response.message,
            ingestionJobId: response.ingestionJobId
        )
    }
    
    /// Get KB sync status
    func getSyncStatus() async throws -> KBSyncStatusMessage {
        return try await ipcClient.getKBSyncStatus()
    }
    
    // MARK: - Validation Helpers
    
    private func validateMarkdownPath(_ path: String) -> PathValidation {
        let lowercasePath = path.lowercased()
        guard lowercasePath.hasSuffix(".md") || lowercasePath.hasSuffix(".markdown") else {
            return PathValidation(
                isValid: false,
                error: "Only markdown files are supported (.md, .markdown)",
                expandedPath: nil
            )
        }
        
        let expandedPath = NSString(string: path).expandingTildeInPath
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: expandedPath) else {
            return PathValidation(
                isValid: false,
                error: "File not found at '\(path)'",
                expandedPath: nil
            )
        }
        
        return PathValidation(isValid: true, error: nil, expandedPath: expandedPath)
    }
}

// MARK: - Result Types

struct KBListResult {
    let documents: [KBDocumentInfo]
    let hasMore: Bool
}

struct KBOperationResult {
    let success: Bool
    let message: String
    let document: KBDocumentInfo?
}

struct KBSyncResult {
    let success: Bool
    let message: String
    let ingestionJobId: String?
}

private struct PathValidation {
    let isValid: Bool
    let error: String?
    let expandedPath: String?
}
