# dev.echo Project Status

## Overview
dev.echo is an AI partner for developers, providing real-time audio capture/transcription and context-aware LLM support.

## Architecture
- **Frontend**: Swift CLI (macOS, ScreenCaptureKit)
- **Backend**: Python (MLX-Whisper, Strands Agents, Ollama)
- **IPC**: Unix Domain Socket (JSON protocol)

## Project Structure
```
dev.echo/
├── Package.swift                    # Swift package manifest
├── Package.resolved                 # Dependency lock file
├── KIRO.md                          # This file - project status
│
├── Sources/DevEcho/
│   ├── main.swift                   # CLI entry point (ArgumentParser)
│   │
│   ├── Command/                     # Command parsing
│   │   ├── Command.swift            # Command enum (new, chat, quick, etc.)
│   │   └── CommandParser.swift      # Input string → Command parsing
│   │
│   ├── Audio/                       # Audio capture engine
│   │   ├── SystemAudioCapture.swift # ScreenCaptureKit handler (macOS 13+)
│   │   ├── MicrophoneCapture.swift  # AVAudioEngine mic input
│   │   ├── SampleRateConverter.swift # 48kHz → 16kHz (vDSP)
│   │   └── AudioCaptureEngine.swift # Unified capture + IPC streaming
│   │
│   ├── IPC/                         # Inter-process communication
│   │   ├── IPCClient.swift          # Unix socket client
│   │   └── IPCProtocol.swift        # Message types, AudioSource
│   │
│   └── TUI/                         # Terminal UI (Claude Code style)
│       ├── TUIEngine.swift          # Main UI engine
│       ├── HeaderView.swift         # Logo, version, model info
│       ├── StatusBar.swift          # Status types (CaptureStatus, AudioChannel, PermissionStatus)
│       ├── StatusBarManager.swift   # Real-time status management
│       ├── ProcessingIndicator.swift # Animated spinner + elapsed time
│       ├── TranscriptEntry.swift    # Transcript/LLM response models
│       ├── TranscriptExporter.swift # Markdown export and file saving
│       └── ApplicationMode.swift    # App mode enum (command, transcribing, kb)
│
├── backend/
│   ├── pyproject.toml               # Python dependencies
│   ├── README.md                    # Backend documentation
│   ├── __init__.py
│   ├── main.py                      # Backend entry point
│   ├── ipc/
│   │   ├── __init__.py
│   │   ├── server.py                # Unix socket server (asyncio)
│   │   └── protocol.py              # Message protocol definitions
│   └── transcription/
│       ├── __init__.py
│       ├── engine.py                # MLX-Whisper transcription engine
│       └── service.py               # Transcription service with buffering
│
└── .kiro/
    ├── specs/dev-echo-phase1/       # Spec documents
    │   ├── requirements.md
    │   ├── design.md
    │   └── tasks.md
    └── steering/
        └── dev-echo-steering.md     # AI assistant rules
```

## Implementation Progress

### ✅ Completed Tasks

#### Task 1: Project Structure and Build Configuration
- [x] 1.1 Swift Package with ArgumentParser, swift-log
- [x] 1.2 Python backend with mlx-whisper, strands-agents, ollama
- [x] 1.3 IPC foundation (Unix Domain Socket server/client, JSON protocol)

#### Task 2: Command Parser
- [x] 2.1 Command enum and CommandParser implementation
  - All commands: `/new`, `/managekb`, `/quit`, `/chat`, `/quick`, `/stop`, `/save`, `/list`, `/remove`, `/update`, `/add`
  - Handles quoted paths for `/add` and `/update`

#### Task 3: Terminal UI Manager (Claude Code Style)
- [x] 3.1 TUIEngine with header, transcript area, input, status bar
- [x] 3.2 StatusBarManager with real-time status updates
- [x] 3.3 ProcessingIndicator with animated spinner

#### Task 4: Application Mode Management
- [x] 4.1 ApplicationModeStateMachine with mode transitions
  - Mode transitions: command → transcribing, command → kb_management
  - Mode-specific command validation via `validCommands` and `isValidCommand()`
  - `ModeTransitionResult` enum for transition outcomes
  - Integrated into Application class in main.swift

#### Task 6: Audio Capture Engine
- [x] 6.1 SystemAudioCapture (ScreenCaptureKit, macOS 13+)
  - SCStream for system audio capture
  - Permission checking and requesting
  - Audio sample extraction from CMSampleBuffer
- [x] 6.2 MicrophoneCapture (AVAudioEngine)
  - AVAudioEngine tap for mic input
  - Permission handling via AVCaptureDevice
  - Mono conversion for stereo input
- [x] 6.3 SampleRateConverter (48kHz → 16kHz)
  - vDSP-based low-pass filter and decimation
  - Maintains audio quality during conversion
- [x] 6.5 AudioCaptureEngine (unified + IPC streaming)
  - Manages both system and mic capture
  - Streams converted audio to Python backend via IPC
  - Status and permission callbacks
  - Debug mode support with runtime toggle (Ctrl+B)

#### Task 7: Transcription Engine (Python)
- [x] 7.1 MLX-Whisper transcription service
  - TranscriptionEngine class with model initialization
  - Async transcribe() method for audio processing
  - Custom exceptions (TranscriptionError, ModelInitializationError, AudioProcessingError)
  - English-only transcription (`language="en"`)
- [x] 7.2 Stream transcription with source tracking
  - TranscriptionService with audio buffering
  - Source identification (system/microphone) maintained
  - Error recovery with logging and continuation
  - Integration with IPC server for real-time results

#### Task 8: Checkpoint - Audio Pipeline
- [x] All Swift tests passing (49 tests)
- [x] Python backend tests added and passing (18 tests)
  - `test_protocol.py`: IPC protocol tests
  - `test_transcription.py`: Transcription engine tests

#### Debug Mode Implementation
- [x] `--debug` CLI flag for Swift app
- [x] `--debug` CLI flag for Python backend
- [x] Ctrl+B runtime toggle for debug mode
- [x] Debug mode propagation to all Audio components
- [x] IPCClient debug mode with `setDebug()` method

#### Task 9: Local LLM Integration (Python)
- [x] 9.1 Strands Agent with Ollama provider
  - LocalLLMAgent class with Ollama/Llama integration
  - Ollama service availability checking
  - Model existence validation
  - Custom exceptions (OllamaUnavailableError, ModelNotFoundError)
- [x] 9.2 Query method with context inclusion
  - ConversationContext and TranscriptContext dataclasses
  - Context building from transcript history
  - LLMService for IPC integration
  - LLM query handler in DevEchoBackend

#### Task 10: Transcript Management
- [x] 10.1 Transcript and TranscriptEntry models
  - TranscriptEntry with timestamp, source, content, LLM response support
  - Transcript model with entries collection, start/end time
  - Chronological ordering maintained via addEntry/addLLMResponse
  - Markdown export with toMarkdown() method
- [x] 10.2 Transcript ordering and display
  - TUIEngine updated to use Transcript model
  - Entries sorted by timestamp (chronological order)
  - New entries scroll from bottom (most recent at bottom)
  - Line-count aware scrolling for multi-line entries
- [x] 10.4 Markdown export
  - TranscriptExporter with export to path, Documents, or current directory
  - TranscriptExportResult and TranscriptExportError types
  - TUIEngine integration with saveTranscript methods
  - Error handling for empty transcript, invalid path, permission denied, disk full

#### Task 13: Wire Components Together
- [x] 13.1 Main application loop
  - Ctrl+Q handling for graceful shutdown (Requirement 1.2)
  - Signal handler for SIGINT
  - Command routing to appropriate handlers
  - Mode-specific command validation with helpful error messages
- [x] 13.2 Transcribing Mode flow
  - /new starts audio capture and new transcript session
  - Real-time transcription display via IPC
  - /chat and /quick commands with LLM integration
  - Context building from transcript history (Requirement 7.2)
  - Processing indicator with elapsed time (Requirement 3.8)
  - /stop, /save, /quit commands fully functional
- [x] 13.3 KB Management Mode flow
  - /list, /add, /update, /remove commands with validation
  - Markdown file validation (Requirement 4.5)
  - File existence checking
  - Placeholder for KB Manager (Task 11)

### 🔲 Pending Tasks
- [ ] **Task 10**: Transcript Management (optional PBT tasks remaining)
- [ ] **Task 11**: Knowledge Base Manager (Python)
- [ ] **Task 12**: Checkpoint - Backend services
- [x] **Task 13**: Wire components together
- [ ] **Task 14**: Final checkpoint

## Key Components

### Swift CLI Components

| Component | File | Description |
|-----------|------|-------------|
| **Entry Point** | `main.swift` | ArgumentParser command, app initialization |
| **Command** | `Command.swift` | All command variants enum |
| **CommandParser** | `CommandParser.swift` | String → Command parsing with validation |
| **IPCClient** | `IPCClient.swift` | Unix socket client for Python backend |
| **IPCProtocol** | `IPCProtocol.swift` | Message types, AudioSource, AudioBuffer |
| **TUIEngine** | `TUIEngine.swift` | Main terminal UI rendering engine |
| **HeaderView** | `HeaderView.swift` | App header with logo, version, path |
| **StatusBar** | `StatusBar.swift` | CaptureStatus, AudioChannel, PermissionStatus |
| **StatusBarManager** | `StatusBarManager.swift` | Real-time status updates |
| **ProcessingIndicator** | `ProcessingIndicator.swift` | Animated spinner with elapsed time |
| **TranscriptEntry** | `TranscriptEntry.swift` | Transcript and LLM response models |
| **ApplicationMode** | `ApplicationMode.swift` | command, transcribing, knowledgeBaseManagement |
| **SystemAudioCapture** | `Audio/SystemAudioCapture.swift` | ScreenCaptureKit system audio (macOS 13+) |
| **MicrophoneCapture** | `Audio/MicrophoneCapture.swift` | AVAudioEngine microphone input |
| **SampleRateConverter** | `Audio/SampleRateConverter.swift` | 48kHz → 16kHz conversion (vDSP) |
| **AudioCaptureEngine** | `Audio/AudioCaptureEngine.swift` | Unified capture + IPC streaming |

### Python Backend Components

| Component | File | Description |
|-----------|------|-------------|
| **IPC Server** | `ipc/server.py` | Asyncio Unix socket server |
| **Protocol** | `ipc/protocol.py` | Message protocol definitions |
| **TranscriptionEngine** | `transcription/engine.py` | MLX-Whisper transcription |
| **TranscriptionService** | `transcription/service.py` | Audio buffering + transcription |
| **LocalLLMAgent** | `llm/agent.py` | Strands Agent with Ollama/Llama |
| **LLMService** | `llm/service.py` | LLM service layer for IPC |
| **Backend Main** | `main.py` | Backend entry point |

## Type Definitions

### Commands (Swift)
```swift
enum Command {
    case new, managekb, quit           // Command Mode
    case chat(content: String)         // Transcribing Mode
    case quick(content: String)
    case stop, save
    case list                          // KB Management Mode
    case remove(name: String)
    case update(fromPath: String, name: String)
    case add(fromPath: String, name: String)
    case unknown(input: String)
}
```

### Application Modes (Swift)
```swift
enum ApplicationMode {
    case command                       // Default - select mode
    case transcribing                  // Audio capture active
    case knowledgeBaseManagement       // Managing KB docs
}
```

### Audio Source (Swift)
```swift
enum AudioSource: String, Codable {
    case system = "system"             // 🔊 System Audio
    case microphone = "microphone"     // 🎤 Microphone
}
```

### Status Types (Swift)
```swift
enum CaptureStatus { case active, inactive }
enum AudioChannel { case headphone, speaker }
struct PermissionStatus { var screenCapture: Bool; var microphone: Bool }
```

## Build Commands
```bash
# Swift build
swift build

# Run dev.echo
swift run dev.echo

# Run with debug logging
swift run dev.echo --debug

# Python setup (using venv)
cd backend
source .venv/bin/activate
pip install -e ".[dev]"

# Run Python backend
cd backend && source .venv/bin/activate && python main.py

# Run Python backend with debug logging
cd backend && source .venv/bin/activate && python main.py --debug

# Run Python tests
cd backend && source .venv/bin/activate && pytest
```

## Debug Mode
- **CLI flag**: `--debug` enables verbose logging at startup
- **Runtime toggle**: Press `Ctrl+B` to toggle debug mode while running
- **Scope**: Affects IPCClient, AudioCaptureEngine, SystemAudioCapture, MicrophoneCapture
- **Default**: Debug OFF (only warnings and transcription output shown)

## Requirements
- macOS 13.0+ (ScreenCaptureKit audio capture)
- Swift 5.9+
- Python 3.10+
- Ollama (for LLM features)

## IPC Configuration
- Socket path: `/tmp/devecho.sock`
- Protocol: JSON over Unix Domain Socket
- Message types: audio_data, transcription, llm_query, llm_response, ping/pong, shutdown
