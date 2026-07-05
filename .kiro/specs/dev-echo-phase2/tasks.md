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

- [x] 16. Implement Reading Mode - TTS Engine (Swift) _(AVSpeechSynthesizer — superseded by Task 21-24: Qwen3-TTS)_
  - [x] 16.1 Create TTSEngine class
    - Create Sources/DevEcho/Services/TTSEngine.swift
    - Implement TTSEngine using AVSpeechSynthesizer
    - Implement TTSState enum (idle, speaking, stopping)
    - Implement TTSVoiceConfig struct with voice, rate, volume, language
    - Implement AVSpeechSynthesizerDelegate for playback callbacks
    - Implement speak(), stop(), listVoices(), setVoice(), setRate() methods
    - Default to Korean voice (ko-KR) with rate 0.5
    - _Requirements: 13.1, 13.2, 13.3, 13.4, 13.6_

  - [x] 16.2 Implement TTSEngineDelegate protocol
    - Define delegate protocol for TTS event callbacks
    - Implement ttsDidStartSpeaking, ttsDidFinishSpeaking, ttsDidCancel, ttsDidEncounterError
    - Wire delegate to AVSpeechSynthesizerDelegate methods
    - _Requirements: 13.4, 13.5, 15.2, 15.3_

  - [x] 16.3 Implement voice listing and selection
    - Query AVSpeechSynthesisVoice.speechVoices() for available voices
    - Filter by language if specified
    - Implement voice search by name (case-insensitive partial match)
    - Return TTSVoiceInfo with name, language, identifier
    - _Requirements: 14.1, 14.2, 14.5_

- [ ] 17. Checkpoint - Verify TTS Engine
  - Test speech synthesis with Korean and English text
  - Test stop during playback
  - Test voice switching and rate adjustment
  - Ensure delegate callbacks fire correctly

- [x] 18. Implement Reading Mode - CLI Integration (Swift)
  - [x] 18.1 Add Command.read, Command.voice, Command.speed to Command enum
    - Add `.read` case for entering reading mode
    - Add `.voice(name: String?)` case for voice listing/changing
    - Add `.speed(rate: Float?)` case for speed display/adjustment
    - _Requirements: 12.1, 14.1-14.6_

  - [x] 18.2 Update CommandParser for reading mode commands
    - Parse `/read` → Command.read
    - Parse `/voice` → Command.voice(name: nil)
    - Parse `/voice Yuna` → Command.voice(name: "Yuna")
    - Parse `/speed` → Command.speed(rate: nil)
    - Parse `/speed 0.8` → Command.speed(rate: 0.8)
    - _Requirements: 12.1, 14.1-14.6_

  - [x] 18.3 Add ApplicationMode.reading
    - Add `.reading` case to ApplicationMode enum
    - Define displayName: "Reading Mode"
    - Define validCommands: text input, /stop, /voice, /speed, /quit
    - Define compactCommandsHelp and availableCommandsHelp
    - _Requirements: 12.3, 12.4_

  - [x] 18.4 Update ApplicationModeStateMachine
    - Add transition: .command + .read → .reading
    - Add transition: .reading + .quit → .command
    - _Requirements: 12.1, 12.2_

  - [x] 18.5 Implement reading mode dispatch in main.swift
    - Add executeReadingModeAction() method
    - Handle plain text input → TTSEngine.speak()
    - Handle /stop → TTSEngine.stop()
    - Handle /voice → list voices or change voice
    - Handle /speed → show or change speed
    - Handle /quit → stop speech, transition to command mode
    - Implement TTSEngineDelegate to update UI on speech events
    - _Requirements: 12.1-12.5, 13.1-13.6, 14.1-14.6_

  - [x] 18.6 Implement reading mode status bar
    - Show mode indicator: "📖 Reading Mode"
    - Show current voice name and language
    - Show current speed setting
    - Show speaking indicator with elapsed time when active
    - Show available commands in compact form
    - _Requirements: 15.1-15.4_

- [ ] 19. Checkpoint - Verify Reading Mode integration
  - Test /read enters reading mode from command mode
  - Test text input triggers speech
  - Test /stop stops speech
  - Test /voice lists and changes voices
  - Test /speed shows and changes rate
  - Test /quit returns to command mode and stops speech
  - Test status bar updates correctly during speech

- [ ] 20. Reading Mode tests
  - [x] 20.1 Write unit tests for TTSEngine
    - Test speak() creates correct AVSpeechUtterance
    - Test stop() calls stopSpeaking on synthesizer
    - Test setRate() validates range (0.1-2.0)
    - Test setVoice() validates identifier
    - Test listVoices() returns available voices
    - Test state transitions (idle → speaking → idle)
    - _Validates: Properties 16, 17_

  - [x] 20.2 Write unit tests for reading mode commands
    - Test CommandParser parses /read, /voice, /speed correctly
    - Test ApplicationMode.reading validates commands correctly
    - Test mode transitions for reading mode
    - _Validates: Properties 15, 18_

  - [ ]* 20.3 Write property tests for Reading Mode
    - **Property 15: Reading Mode Transition Round-Trip**
    - **Property 16: TTS Playback Lifecycle**
    - **Property 17: TTS Configuration Persistence**
    - **Property 18: Reading Mode Command Isolation**
    - _Validates: Requirements 12.1-12.5, 13.1-13.6, 14.1-14.6_

- [x] 21. Qwen3-TTS Python Backend Engine
  - [x] 21.1 Create backend/tts/ module structure
    - Create __init__.py, exceptions.py
    - Define TTSError, ModelInitializationError, GenerationError, PlaybackError
    - _Pattern: follow backend/llm/exceptions.py_

  - [x] 21.2 Implement TTSEngine class (backend/tts/engine.py)
    - VoiceConfig dataclass: language, voice_instruct
    - VOICE_PRESETS dict: korean_female, korean_male, english_female, english_male
    - TTSEngineState enum: idle, loading_model, generating, playing, stopping
    - initialize(): load model via mlx_audio.tts.utils.load_model() in executor
    - speak(text): generate via generate_voice_design(), play in daemon thread
    - stop(): threading.Event stop mechanism
    - set_voice_config(), shutdown()
    - _Model: mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16_
    - _API: model.generate_voice_design(text, language, instruct) → yields audio chunks_
    - _Requirements: 13.1, 13.2, 13.3, 13.6_

  - [x] 21.3 Implement TTSService class (backend/tts/service.py)
    - TTSStatus dataclass: state, text, elapsed, error
    - speak(text, language?): lazy-init engine, generate + play, monitor playback
    - stop_speech(): delegate to engine.stop()
    - get_status(), get_voice_config(), set_preset(), list_presets()
    - Status callback for IPC broadcasting
    - _Pattern: follow backend/llm/service.py_
    - _Requirements: 13.1-13.6, 14.1-14.2_

- [x] 22. IPC Protocol TTS Extension
  - [x] 22.1 Add TTS message types to Python protocol
    - Add TTS_SPEAK, TTS_STOP, TTS_STATUS, TTS_SET_VOICE, TTS_VOICE_CONFIG to MessageType enum
    - Add TTSSpeakMessage, TTSStopMessage, TTSStatusMessage, TTSSetVoiceMessage, TTSVoiceConfigMessage dataclasses
    - _File: backend/ipc/protocol.py_

  - [x] 22.2 Add TTS message types to Swift protocol
    - Add ttsSpeak, ttsStop, ttsStatus, ttsSetVoice, ttsVoiceConfig to MessageType enum
    - Add TTSStatusMessage and TTSVoiceConfigResponse Swift structs
    - _File: Sources/DevEcho/IPC/IPCProtocol.swift_

- [x] 23. Backend TTS Integration
  - [x] 23.1 Register TTS handlers in IPC server
    - Add on_tts_speak, on_tts_stop, on_tts_set_voice handler registration
    - Add TTS_SPEAK, TTS_STOP, TTS_SET_VOICE routing in _process_message()
    - Add send_tts_status() broadcast method
    - _File: backend/ipc/server.py_

  - [x] 23.2 Wire TTS service in backend main
    - Add _init_tts_service(): initialize TTSService (always available, not gated by AWS)
    - Register TTS handlers, wire status callback
    - Add TTS service shutdown in stop()
    - _File: backend/main.py_

- [x] 24. Swift TTSEngine Refactor to IPC
  - [x] 24.1 Refactor TTSEngine.swift to use IPC
    - Remove AVSpeechSynthesizer, NSObject, AVSpeechSynthesizerDelegate
    - Add ipcClient: IPCClient dependency
    - Replace TTSVoiceConfig: presetName + language + voiceInstruct
    - speak() → send tts_speak IPC message
    - stop() → send tts_stop IPC message
    - Add handleStatusUpdate() for incoming tts_status messages
    - listVoices() → return preset names
    - setVoiceByName() → send tts_set_voice with preset name
    - Remove setRate() (no speed control in Qwen3-TTS)
    - _File: Sources/DevEcho/Services/TTSEngine.swift_

  - [x] 24.2 Add TTS status handling in IPCClient
    - Add onTTSStatus callback property
    - Handle .ttsStatus and .ttsVoiceConfig in startListening()
    - _File: Sources/DevEcho/IPC/IPCClient.swift_

  - [x] 24.3 Wire TTSEngine in main.swift
    - TTSEngine() → TTSEngine(ipcClient: ipcClient)
    - Wire TTS status callback in IPC listening setup
    - Update executeSpeakText() for new state handling
    - Update executeReadingModeAction() for preset-based /voice
    - Update printStatusAndPrompt() to remove speechRate
    - _File: Sources/DevEcho/main.swift_

- [x] 25. Remove /speed and Update Reading Mode UI
  - [x] 25.1 Remove /speed from Command and CommandParser
    - Removed Command.speed case, CommandType.speed, /speed parsing
    - _Files: Command.swift, CommandParser.swift, ApplicationMode.swift_

  - [x] 25.2 Update ApplicationMode for reading mode
    - Removed /speed from validCommands, availableCommands, help text
    - _File: ApplicationMode.swift_

  - [x] 25.3 Update TerminalRenderer status bar
    - Removed speechRate parameter from buildStatusLine()
    - New format: "📖 Reading │ {preset} │ /voice /stop /quit"
    - _File: TerminalRenderer.swift_

- [ ] 26. Dependencies and Documentation
  - [ ] 26.1 Update pyproject.toml
    - Add "mlx-audio[tts]" and audio playback dependency
    - _File: backend/pyproject.toml_

  - [x] 26.2 Update design.md and tasks.md
    - Apply all changes described in the Qwen3-TTS integration plan
    - _Files: .kiro/specs/dev-echo-phase2/design.md, tasks.md_

- [ ] 27. Qwen3-TTS Tests
  - [ ] 27.1 Write Python TTS engine tests
    - Test VoiceConfig, VOICE_PRESETS, TTSEngineState
    - Test speak() with empty text, stop() when idle
    - Test set_voice_config() updates
    - Mock mlx-audio for model tests
    - _File: backend/tests/test_tts_engine.py_

  - [ ] 27.2 Write Python TTS service tests
    - Test lifecycle, speak/stop delegation, preset management
    - Test status callback invocation
    - _File: backend/tests/test_tts_service.py_

  - [ ] 27.3 Write IPC TTS message tests
    - Test TTS message serialization/deserialization
    - _File: backend/tests/test_protocol.py_

  - [x] 27.4 Update Swift TTSEngine tests
    - Rewrite for IPC-based engine (37 tests)
    - Test speak/stop IPC messages, handleStatusUpdate state transitions
    - Test preset management, delegate callbacks, IPC round-trips
    - _File: Tests/DevEchoTests/TTSEngineTests.swift_

### Implementation Order (dependency-based)

```
21.1 → 21.2 → 21.3 (Python TTS module)
          ↓
22.1 → 22.2 (IPC protocol)
          ↓
23.1 → 23.2 (Backend integration)
          ↓
24.1 → 24.2 → 24.3 (Swift refactoring)
          ↓
25.1 → 25.2 → 25.3 (/speed removal, UI update)
          ↓
26.1, 26.2 (dependencies, documentation)
27.x (tests run in parallel with each stage)
```

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties
- Unit tests validate specific examples and edge cases
- AWS credentials must be configured before testing Phase 2 features
- Bedrock Knowledge Base must be pre-configured with S3 data source
- Reading Mode (Tasks 16-20) was originally implemented with AVSpeechSynthesizer; Tasks 21-27 replace it with Qwen3-TTS via Python backend
- TTS is always available (not gated by AWS configuration)
- Default TTS voice preset is korean_female

