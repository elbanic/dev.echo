# Implementation Plan: dev.echo Phase 1

## Overview

This implementation plan covers the core CLI application with audio capture, transcription, and local LLM integration. The project uses Swift for the CLI frontend and audio capture (ScreenCaptureKit), and Python for transcription (MLX-Whisper) and LLM integration (Strands Agent with Ollama).

## Tasks

- [x] 1. Set up project structure and build configuration
  - [x] 1.1 Create Swift Package structure with Sources/DevEcho directory
    - Initialize Package.swift with dependencies (ArgumentParser, swift-log)
    - Create main.swift entry point
    - _Requirements: 1.1_
  - [x] 1.2 Create Python backend structure
    - Set up pyproject.toml with dependencies (mlx-whisper, strands-agents, ollama)
    - Create backend/ directory with __init__.py
    - _Requirements: 6.1, 7.1_
  - [x] 1.3 Set up IPC communication foundation
    - Create Unix Domain Socket server (Python) and client (Swift)
    - Define message protocol (JSON-based)
    - _Requirements: 5.6, 6.1_

- [x] 2. Implement Command Parser
  - [x] 2.1 Create Command enum and CommandParser
    - Implement all command variants (new, managekb, quit, chat, quick, stop, save, list, remove, update, add)
    - Handle parameter extraction for commands with arguments
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 3.3, 3.4, 3.5, 3.6, 3.7, 4.1, 4.2, 4.3, 4.4, 4.6_
  - [ ]* 2.2 Write property test for command parsing
    - **Property 1: Command Parsing Consistency**
    - **Validates: Requirements 2.1, 2.2, 2.3, 3.3, 3.4, 3.5, 3.6, 3.7, 4.1, 4.2, 4.3, 4.4, 4.6**
  - [ ]* 2.3 Write property test for invalid command rejection
    - **Property 2: Invalid Command Rejection**
    - **Validates: Requirements 2.4**

- [x] 3. Implement Terminal UI Manager (Claude Code Style)
  - [x] 3.1 Create TUIEngine with header, transcript area, input, and status bar
    - Implement HeaderView with logo, version, model info
    - Implement transcript area with scrolling support
    - Implement input area with prompt rendering
    - _Requirements: 1.3, 1.4, 3.1, 3.2_
  - [x] 3.2 Implement StatusBarManager
    - Display audio/mic status, channel, permissions
    - Real-time status updates
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5_
  - [x] 3.3 Implement ProcessingIndicator
    - Animated spinner with elapsed time display
    - _Requirements: 3.8_
  - [ ]* 3.4 Write property test for status bar completeness
    - **Property 12: Status Bar Completeness**
    - **Validates: Requirements 9.1, 9.2, 9.3, 9.4**

- [x] 4. Implement Application Mode Management
  - [x] 4.1 Create ApplicationMode enum and state machine
    - Implement mode transitions (command → transcribing, command → kb_management)
    - Handle mode-specific command validation
    - _Requirements: 2.1, 2.2, 3.7, 4.6_
  - [ ]* 4.2 Write property test for mode transitions
    - **Property 3: Mode Transition Correctness**
    - **Validates: Requirements 2.1, 2.2, 3.7, 4.6**

- [x] 5. Checkpoint - Core CLI structure
  - Ensure all tests pass, ask the user if questions arise.

- [x] 6. Implement Audio Capture Engine
  - [x] 6.1 Create ScreenCaptureKit handler for system audio
    - Initialize SCStream for audio capture
    - Handle permission requests
    - _Requirements: 5.1, 5.5_
  - [x] 6.2 Create microphone capture handler
    - Initialize AVAudioEngine for mic input
    - Handle permission requests
    - _Requirements: 5.2, 5.5_
  - [x] 6.3 Implement SampleRateConverter (48kHz → 16kHz)
    - Use vDSP for efficient conversion
    - Maintain audio quality
    - _Requirements: 5.3, 5.4_
  - [ ]* 6.4 Write property test for sample rate conversion
    - **Property 5: Sample Rate Conversion Integrity**
    - **Validates: Requirements 5.3**
  - [x] 6.5 Implement audio streaming to Python backend via IPC
    - Stream audio buffers with source identification
    - _Requirements: 5.6_

- [x] 7. Implement Transcription Engine (Python)
  - [x] 7.1 Create MLX-Whisper transcription service
    - Initialize model on startup
    - Process audio chunks and return transcription
    - _Requirements: 6.1, 6.2_
  - [x] 7.2 Implement stream transcription with source tracking
    - Maintain source identification (system/microphone)
    - Handle transcription errors gracefully
    - _Requirements: 6.2, 6.3, 6.4_
  - [ ]* 7.3 Write property test for transcription source identification
    - **Property 6: Transcription Source Identification**
    - **Validates: Requirements 6.2**
  - [ ]* 7.4 Write property test for error recovery
    - **Property 7: Transcription Error Recovery**
    - **Validates: Requirements 6.4**

- [x] 8. Checkpoint - Audio pipeline
  - Ensure all tests pass, ask the user if questions arise.

- [x] 9. Implement Local LLM Integration (Python)
  - [x] 9.1 Create Strands Agent with Ollama provider
    - Initialize agent with Llama model
    - Check Ollama service availability
    - _Requirements: 7.1, 7.4_
  - [x] 9.2 Implement query method with context inclusion
    - Build context from transcript history
    - Send query and receive response
    - _Requirements: 7.2, 7.3_
  - [x] 9.3 Implement /quick command handler
    - Send transcript context to local LLM (Ollama/Llama)
    - Display response in transcript area with model info
    - Show processing indicator during query
    - _Requirements: 3.4, 7.1, 7.2, 7.3_
  - [ ]* 9.4 Write property test for context inclusion
    - **Property 8: LLM Context Inclusion**
    - **Validates: Requirements 7.2**

- [x] 10. Implement Transcript Management
  - [x] 10.1 Create Transcript and TranscriptEntry models
    - Store entries with timestamp, source, and content
    - Support LLM response entries
    - _Requirements: 3.1, 3.2_
  - [x] 10.2 Implement transcript ordering and display
    - Maintain chronological order
    - Scroll new entries from bottom
    - _Requirements: 3.2_
  - [ ]* 10.3 Write property test for transcript ordering
    - **Property 4: Transcript Entry Ordering**
    - **Validates: Requirements 3.2**
  - [x] 10.4 Implement markdown export
    - Format with timestamps and speaker identification
    - Save to user-selected location
    - _Requirements: 8.1, 8.2, 8.3, 8.4_
  - [ ]* 10.5 Write property test for markdown format
    - **Property 9: Markdown Transcript Format**
    - **Validates: Requirements 8.2**

- [ ] 11. Implement Knowledge Base Manager (Python)
  - [ ] 11.1 Create KnowledgeBaseManager class
    - Initialize with KB storage path
    - Implement list_documents method
    - _Requirements: 4.1_
  - [ ] 11.2 Implement document operations (add, update, remove)
    - Validate markdown files
    - Handle file operations
    - _Requirements: 4.2, 4.3, 4.4, 4.5_
  - [ ]* 11.3 Write property test for markdown validation
    - **Property 10: KB Document Validation**
    - **Validates: Requirements 4.5**
  - [ ]* 11.4 Write property test for document round-trip
    - **Property 11: KB Document Round-Trip**
    - **Validates: Requirements 4.1, 4.2, 4.4**

- [ ] 12. Checkpoint - Backend services
  - Ensure all tests pass, ask the user if questions arise.

- [x] 13. Wire components together
  - [x] 13.1 Implement main application loop
    - Handle keyboard input (including ctrl+q)
    - Route commands to appropriate handlers
    - _Requirements: 1.1, 1.2_
  - [x] 13.2 Connect Transcribing Mode flow
    - Start audio capture on /new
    - Display transcriptions in real-time
    - Handle /chat and /quick commands
    - Handle /stop, /save, /quit commands
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7_
  - [x] 13.3 Connect KB Management Mode flow
    - Handle /list, /add, /update, /remove, /quit commands
    - Display operation results
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6_
  - [ ]* 13.4 Write property test for status update reactivity
    - **Property 13: Status Update Reactivity**
    - **Validates: Requirements 9.5**

- [ ] 14. Final checkpoint
  - Ensure all tests pass, ask the user if questions arise.
  - Verify all requirements are covered
  - Test end-to-end workflows

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Swift code requires Xcode and macOS 12.3+ for ScreenCaptureKit
- Python backend requires MLX-Whisper and Ollama to be installed
- Property tests use SwiftCheck (Swift) and Hypothesis (Python)
- Each property test references specific design document properties
