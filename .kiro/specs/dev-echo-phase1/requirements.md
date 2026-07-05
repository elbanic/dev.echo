# Requirements Document

## Introduction

dev.echo Phase 1 is a developer-focused AI partner that captures and transcribes audio in real-time, providing context-aware assistance during development and meetings. This phase focuses on building the core CLI interface, audio capture using macOS ScreenCaptureKit, local transcription with MLX-Whisper, and local LLM integration via Ollama with Strands Agent.

## Glossary

- **CLI_Interface**: The command-line interface that provides the main user interaction point for dev.echo
- **Transcribing_Mode**: The operational mode where audio capture and transcription are active
- **Command_Mode**: The default mode where users can select which mode to enter
- **KB_Management_Mode**: The mode for managing knowledge base documents
- **Audio_Capture_Engine**: The component using ScreenCaptureKit to capture system audio and microphone input
- **Transcription_Engine**: The component using MLX-Whisper for local speech-to-text conversion
- **Local_LLM**: The Llama model accessed via Ollama for quick local responses
- **Status_Bar**: The UI component displaying capture status, channel info, and permissions
- **Transcript_Display**: The area showing real-time transcription with system audio on left and microphone on right

## Requirements

### Requirement 1: CLI Application Lifecycle

**User Story:** As a developer, I want to start and exit the dev.echo application easily, so that I can quickly access its features when needed.

#### Acceptance Criteria

1. WHEN a user executes the `dev.echo` command THEN THE CLI_Interface SHALL launch and display the Command_Mode interface
2. WHEN a user presses ctrl+q THEN THE CLI_Interface SHALL gracefully terminate all active processes and exit the application
3. WHILE the application is running THEN THE CLI_Interface SHALL display a chat input area at the bottom of the screen
4. WHILE the application is running THEN THE CLI_Interface SHALL display a Status_Bar below the chat input showing audio/mic capture status, current channel, and permission status

### Requirement 2: Command Mode Operations

**User Story:** As a developer, I want to navigate between different modes using slash commands, so that I can access the functionality I need.

#### Acceptance Criteria

1. WHEN a user enters `/new` in Command_Mode THEN THE CLI_Interface SHALL transition to Transcribing_Mode and start audio/mic capturing and transcription
2. WHEN a user enters `/managekb` in Command_Mode THEN THE CLI_Interface SHALL transition to KB_Management_Mode
3. WHEN a user enters `/quit` in Command_Mode THEN THE CLI_Interface SHALL exit the application gracefully
4. WHEN a user enters an unrecognized command THEN THE CLI_Interface SHALL display an error message with available commands

### Requirement 3: Transcribing Mode Operations

**User Story:** As a developer, I want to capture and transcribe audio while having the ability to interact with an LLM, so that I can get context-aware assistance during meetings or coding sessions.

#### Acceptance Criteria

1. WHEN Transcribing_Mode is active THEN THE Transcript_Display SHALL show system audio transcription on the left side and microphone transcription on the right side
2. WHEN new transcription text arrives THEN THE Transcript_Display SHALL scroll text upward from the bottom
3. WHEN a user enters `/chat {contents}` THEN THE CLI_Interface SHALL send the request with current conversation context to the remote LLM and display the response in the center with a distinct color
4. WHEN a user enters `/quick {contents}` THEN THE CLI_Interface SHALL send the request with current conversation context to the Local_LLM and display the response
5. WHEN a user enters `/stop` THEN THE Audio_Capture_Engine SHALL stop capturing audio and microphone input
6. WHEN a user enters `/save` THEN THE CLI_Interface SHALL display a location selection popup and save the transcript in markdown format
7. WHEN a user enters `/quit` in Transcribing_Mode THEN THE CLI_Interface SHALL stop all capture processes and return to Command_Mode
8. WHILE waiting for an LLM response THEN THE CLI_Interface SHALL display a loading animation

### Requirement 4: Knowledge Base Management Mode

**User Story:** As a developer, I want to manage my knowledge base documents, so that I can maintain relevant context for future queries.

#### Acceptance Criteria

1. WHEN a user enters `/list` in KB_Management_Mode THEN THE CLI_Interface SHALL display all documents in the current knowledge base
2. WHEN a user enters `/remove {name}` THEN THE CLI_Interface SHALL delete the document with the specified filename and confirm deletion
3. WHEN a user enters `/update {from_path} {name}` THEN THE CLI_Interface SHALL update the existing document with content from the specified path
4. WHEN a user enters `/add {from_path} {name}` THEN THE CLI_Interface SHALL upload the markdown file from the specified path with the given name
5. IF a user attempts to add a non-markdown file THEN THE CLI_Interface SHALL reject the operation and display an error message
6. WHEN a user enters `/quit` in KB_Management_Mode THEN THE CLI_Interface SHALL return to Command_Mode

### Requirement 5: Audio Capture

**User Story:** As a developer, I want to capture both system audio and microphone input simultaneously, so that I can transcribe all audio from meetings and my own voice.

#### Acceptance Criteria

1. WHEN Transcribing_Mode starts THEN THE Audio_Capture_Engine SHALL initialize ScreenCaptureKit for system audio capture
2. WHEN Transcribing_Mode starts THEN THE Audio_Capture_Engine SHALL initialize microphone capture
3. WHILE capturing audio THEN THE Audio_Capture_Engine SHALL capture at 48kHz sample rate and convert to 16kHz for transcription
4. WHILE capturing audio THEN THE Audio_Capture_Engine SHALL preserve sound quality during sample rate conversion
5. IF audio capture permissions are not granted THEN THE Audio_Capture_Engine SHALL display a permission request and update the Status_Bar accordingly
6. WHILE capturing THEN THE Audio_Capture_Engine SHALL stream audio data to the Transcription_Engine in real-time

### Requirement 6: Transcription

**User Story:** As a developer, I want real-time transcription of captured audio, so that I can see what is being said as it happens.

#### Acceptance Criteria

1. WHEN audio data is received THEN THE Transcription_Engine SHALL process it using MLX-Whisper for local transcription
2. WHEN transcription is complete for an audio segment THEN THE Transcription_Engine SHALL return the text with source identification (system or microphone)
3. WHILE transcribing THEN THE Transcription_Engine SHALL maintain low latency for near real-time display
4. IF transcription fails for an audio segment THEN THE Transcription_Engine SHALL log the error and continue processing subsequent segments

### Requirement 7: Local LLM Integration

**User Story:** As a developer, I want quick responses from a local LLM, so that I can get assistance without network latency.

#### Acceptance Criteria

1. WHEN a `/quick` command is issued THEN THE Local_LLM SHALL process the request using Ollama with the Llama model
2. WHEN processing a request THEN THE Local_LLM SHALL include the current conversation transcript as context
3. WHEN the Local_LLM generates a response THEN THE CLI_Interface SHALL display it in the transcript area
4. IF Ollama is not running THEN THE CLI_Interface SHALL display an error message indicating the service is unavailable

### Requirement 8: Transcript Persistence

**User Story:** As a developer, I want to save my transcripts, so that I can review them later.

#### Acceptance Criteria

1. WHEN a user executes `/save` THEN THE CLI_Interface SHALL prompt for a save location
2. WHEN saving a transcript THEN THE CLI_Interface SHALL format the output as markdown with timestamps and speaker identification
3. WHEN saving is complete THEN THE CLI_Interface SHALL display a confirmation message with the saved file path
4. IF the save operation fails THEN THE CLI_Interface SHALL display an error message with the failure reason

### Requirement 9: Status Display

**User Story:** As a developer, I want to see the current status of audio capture and permissions, so that I know the system is working correctly.

#### Acceptance Criteria

1. WHILE the application is running THEN THE Status_Bar SHALL display the current audio capture status (active/inactive)
2. WHILE the application is running THEN THE Status_Bar SHALL display the current microphone capture status (active/inactive)
3. WHILE the application is running THEN THE Status_Bar SHALL display the current audio channel (headphone/speaker)
4. WHILE the application is running THEN THE Status_Bar SHALL display permission status for screen capture and microphone access
5. WHEN any status changes THEN THE Status_Bar SHALL update immediately to reflect the new state
