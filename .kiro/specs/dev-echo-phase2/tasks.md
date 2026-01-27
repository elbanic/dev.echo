# Implementation Plan: dev.echo Phase 2

## Overview

This implementation plan covers the cloud services and knowledge base functionality for dev.echo Phase 2. The implementation builds on the existing Phase 1 codebase (Swift CLI + Python backend) and adds S3 document storage, Bedrock Knowledge Base integration, and Cloud LLM with RAG capabilities using Strands Agent.

## Tasks

- [x] 1. Set up Phase 2 infrastructure and dependencies
  - [x] 1.1 Add AWS dependencies to Python backend
    - Add boto3, strands-agents, strands-agents-tools to pyproject.toml
    - Create backend/aws/ directory for Phase 2 components
    - _Requirements: 9.1, 10.1_
  
  - [x] 1.2 Create AWS configuration module
    - Create backend/aws/config.py with AWSConfig dataclass
    - Load configuration from environment variables (AWS_REGION, DEVECHO_S3_BUCKET, DEVECHO_KB_ID, DEVECHO_BEDROCK_MODEL)
    - _Requirements: 9.1, 10.1_
  
  - [x] 1.3 Extend IPC protocol for Phase 2 messages
    - Add CLOUD_LLM_QUERY, CLOUD_LLM_RESPONSE, CLOUD_LLM_ERROR message types
    - Add KB_LIST_RESPONSE, KB_SYNC_STATUS, KB_SYNC_TRIGGER message types
    - Create corresponding message dataclasses
    - _Requirements: 6.1, 6.2_

- [x] 2. Checkpoint - Verify infrastructure setup
  - Ensure all dependencies install correctly
  - Verify configuration loads from environment
  - Ask the user if questions arise

- [x] 3. Implement S3 Document Manager
  - [x] 3.1 Create S3DocumentManager class
    - Create backend/aws/s3_manager.py
    - Implement S3Document dataclass with name, key, size_bytes, last_modified, etag
    - Implement validate_markdown() for .md/.markdown extension check
    - _Requirements: 3.3, 4.4_
  
  - [x] 3.2 Implement document listing with pagination
    - Implement list_documents() using S3 list_objects_v2 with pagination
    - Return tuple of (documents, continuation_token)
    - Sort documents alphabetically by name
    - _Requirements: 2.1, 2.3, 2.4, 10.2_
  
  - [x] 3.3 Implement document add operation
    - Implement document_exists() to check if document already exists
    - Implement add_document() to upload file to S3
    - Validate markdown extension before upload
    - Return error if document already exists
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 10.1_
  
  - [x] 3.4 Implement document update operation
    - Implement update_document() to overwrite existing S3 object
    - Return error if document doesn't exist
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 10.3_
  
  - [x] 3.5 Implement document remove operation
    - Implement remove_document() to delete S3 object
    - Return error if document doesn't exist
    - _Requirements: 5.1, 5.4, 10.4_
  
  - [ ]* 3.6 Write property tests for S3DocumentManager
    - **Property 3: S3 Document CRUD Round-Trip**
    - **Property 4: Markdown File Validation**
    - **Property 5: Document List Alphabetical Sorting**
    - **Property 6: S3 Pagination Correctness**
    - **Property 7: Document Existence Validation**
    - **Validates: Requirements 2.1-2.4, 3.1-3.5, 4.1-4.4, 5.1, 5.4, 10.1-10.4**

- [x] 4. Checkpoint - Verify S3 operations
  - Test S3 document CRUD with actual S3 bucket
  - Ensure all tests pass
  - Ask the user if questions arise

- [x] 5. Implement Knowledge Base Service
  - [x] 5.1 Create KnowledgeBaseService class
    - Create backend/aws/kb_service.py
    - Implement SyncStatus and RetrievalResult dataclasses
    - Initialize bedrock-agent and bedrock-agent-runtime clients
    - _Requirements: 7.1, 11.1_
  
  - [x] 5.2 Implement sync status and connectivity check
    - Implement check_connectivity() to verify KB access
    - Implement get_sync_status() to get KB sync status and document count
    - _Requirements: 11.3, 11.5_
  
  - [x] 5.3 Implement sync trigger for document removal
    - Implement start_sync() to trigger KB reindexing via StartIngestionJob API
    - Return ingestion job ID for tracking
    - _Requirements: 5.2, 11.2_
  
  - [ ]* 5.4 Write property tests for KnowledgeBaseService
    - **Property 13: KB Sync Trigger on Document Removal**
    - **Property 14: Startup Connectivity Verification**
    - **Validates: Requirements 5.2, 11.2, 11.3, 11.5**

- [x] 6. Checkpoint - Verify KB service
  - Test KB connectivity and sync status
  - Ensure all tests pass
  - Ask the user if questions arise

- [x] 7. Implement Cloud LLM Agents
  - [x] 7.1 Create SimpleCloudAgent class
    - Create backend/aws/agents.py
    - Implement SimpleCloudAgent for transcript-only queries
    - Initialize Strands Agent without memory tool
    - Implement query() method with transcript context
    - _Requirements: 6.1, 6.2, 6.3_
  
  - [x] 7.2 Create RAGCloudAgent class
    - Implement RAGCloudAgent with memory tool for KB retrieval
    - Set STRANDS_KNOWLEDGE_BASE_ID environment variable
    - Implement code-defined workflow: retrieve → build context → generate response
    - Extract sources from retrieval result
    - _Requirements: 6.1, 6.4, 6.6, 7.1, 7.3, 8.1, 8.2, 8.4, 8.5_
  
  - [x] 7.3 Create IntentClassifier class
    - Implement keyword-based intent classification
    - Define RAG_KEYWORDS set for detecting KB-required queries
    - Implement classify() method returning QueryIntent enum
    - _Requirements: 6.1_
  
  - [x] 7.4 Create CloudLLMService class
    - Implement service layer routing queries to appropriate agent
    - Initialize both SimpleCloudAgent and RAGCloudAgent
    - Implement query() with intent classification and routing
    - Support force_rag parameter for explicit RAG usage
    - _Requirements: 6.1, 6.4, 7.4_
  
  - [ ]* 7.5 Write property tests for Cloud LLM Agents
    - **Property 8: RAG Context Assembly**
    - **Property 9: Retrieval Result Ranking**
    - **Property 10: Graceful Fallback Without KB Results**
    - **Property 11: Response Source Attribution**
    - **Property 12: Context Truncation Priority**
    - **Validates: Requirements 6.1, 6.4, 6.6, 7.1, 7.3, 7.4, 8.1-8.5**
  
  - [x] 7.6 Implement conversation memory persistence using Strands Agent
    - Leverage Strands Agent's built-in `self.messages` for LLM conversation history
    - Maintain Agent instance across session to preserve previous LLM interactions
    - Transcript context passed separately, LLM conversation history managed by Agent
    - Add clear_conversation() method to reset Agent messages when starting new session
    - Update CloudLLMService to maintain stateful Agent instances
    - _Requirements: 8.1, 8.3_

- [x] 8. Checkpoint - Verify Cloud LLM agents
  - Test SimpleCloudAgent with transcript-only queries
  - Test RAGCloudAgent with KB retrieval
  - Test intent classification routing
  - Ensure all tests pass
  - Ask the user if questions arise

- [x] 9. Integrate Phase 2 services with IPC server
  - [x] 9.1 Create CloudLLMHandler for IPC
    - Create backend/aws/handlers.py
    - Implement handle_cloud_llm_query() to process CLOUD_LLM_QUERY messages
    - Build ConversationContext from IPC message
    - Route to CloudLLMService and return response
    - _Requirements: 6.1, 6.2_
  
  - [x] 9.2 Update S3 KB handlers for IPC
    - Update existing KB handlers to use S3DocumentManager
    - Implement KB_LIST handler with pagination support
    - Implement KB_ADD, KB_UPDATE, KB_REMOVE handlers
    - Trigger KB sync on document removal
    - _Requirements: 2.1-2.4, 3.1-3.5, 4.1-4.4, 5.1-5.3_
  
  - [x] 9.3 Add KB sync status handler
    - Implement KB_SYNC_STATUS handler to return sync status
    - Call on application startup to verify connectivity
    - _Requirements: 11.3, 11.5_
  
  - [x] 9.4 Register Phase 2 handlers in IPC server
    - Update backend/ipc/server.py to register new handlers
    - Initialize Phase 2 services on server start
    - Handle AWS credential errors gracefully
    - _Requirements: 9.3, 9.4, 10.5_

- [x] 10. Checkpoint - Verify IPC integration
  - Test IPC messages for all Phase 2 operations
  - Ensure error handling works correctly
  - Ask the user if questions arise

- [ ]* 11. Implement Voice Activity Detection (VAD) for Microphone
  - [ ]* 11.1 Add energy-based VAD to MicrophoneCapture
    - Implement RMS (Root Mean Square) energy calculation
    - Add configurable energy threshold (default: 0.01)
    - Only forward audio buffers when energy exceeds threshold
    - _Requirements: Noise filtering, voice-only capture_
  
  - [ ]* 11.2 Add silence detection with trailing buffer
    - Track consecutive silent frames count
    - Add trailing buffer (e.g., 10 frames) after voice ends
    - Prevent abrupt audio cutoff during natural speech pauses
    - _Requirements: Natural speech capture_
  
  - [ ]* 11.3 Add VAD configuration to AudioCaptureEngine
    - Add vadEnabled property (default: true)
    - Add vadThreshold property for sensitivity adjustment
    - Expose VAD toggle via TUI command if needed
    - _Requirements: User-configurable noise filtering_

- [x] 12. Update Swift CLI for Phase 2
  - [x] 12.1 Extend IPCProtocol for Phase 2 messages
    - Add CloudLLMQueryMessage, CloudLLMResponseMessage structs
    - Add KBListResponseMessage with pagination support
    - Add KBSyncStatusMessage struct
    - _Requirements: 6.1, 6.2, 2.4_
  
  - [x] 12.2 Update /chat command to use Cloud LLM
    - Modify chat command handler to send CLOUD_LLM_QUERY
    - Display response with sources in distinct color
    - Show loading animation while waiting
    - _Requirements: 6.1, 6.2, 6.3, 6.6_
  
  - [x] 12.3 Update KB management mode for S3 operations
    - Update /list to handle pagination (show "more" option if hasMore)
    - Update /add, /update, /remove to use new S3-based handlers
    - Display sync status after document removal
    - _Requirements: 2.1-2.4, 3.1-3.2, 4.1-4.2, 5.1-5.3_
  
  - [x] 12.4 Add startup KB connectivity check
    - Send KB_SYNC_STATUS on startup when in transcribing mode
    - Display KB status and document count in status bar
    - Handle connectivity errors gracefully
    - _Requirements: 11.3, 11.5_
  
  - [ ]* 12.5 Write property tests for Swift CLI Phase 2
    - **Property 1: Mode Transition Round-Trip**
    - **Property 2: KB Command Validation in Mode**
    - **Validates: Requirements 1.1-1.4**

- [ ] 13. Checkpoint - Verify Swift CLI integration
  - Test /chat command with Cloud LLM
  - Test KB management commands with S3
  - Test startup connectivity check
  - Ensure all tests pass
  - Ask the user if questions arise

- [ ] 14. Error handling and edge cases
  - [ ] 14.1 Implement AWS credential error handling
    - Detect missing/invalid AWS credentials
    - Display setup instructions to user
    - _Requirements: 9.3_
  
  - [ ] 14.2 Implement S3 error handling
    - Handle NoSuchBucket, AccessDenied, NoSuchKey errors
    - Display meaningful error messages with suggestions
    - _Requirements: 10.5_
  
  - [ ] 14.3 Implement Bedrock error handling
    - Handle ResourceNotFoundException, AccessDeniedException, ThrottlingException
    - Suggest /quick for local LLM when Cloud LLM unavailable
    - _Requirements: 6.5, 9.4, 11.4_

- [ ] 15. Final checkpoint - End-to-end testing
  - Test complete workflow: add document → /chat with RAG → verify sources
  - Test fallback to transcript-only when no KB results
  - Test error scenarios (missing credentials, unavailable services)
  - Ensure all tests pass
  - Ask the user if questions arise

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties
- Unit tests validate specific examples and edge cases
- AWS credentials must be configured before testing Phase 2 features
- Bedrock Knowledge Base must be pre-configured with S3 data source

