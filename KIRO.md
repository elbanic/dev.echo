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
│   ├── main.swift                   # CLI entry point + Application class
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
│   ├── Services/                    # Extracted service layer
│   │   ├── KBService.swift          # KB CRUD operations via IPC
│   │   ├── LLMService.swift         # Local/Cloud LLM queries via IPC
│   │   ├── TerminalRenderer.swift   # Display width, wrapping, status line
│   │   └── InputHandler.swift       # Raw mode terminal input handling
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
│   ├── main.py                      # Backend entry point (Phase 1 + Phase 2)
│   ├── aws/                         # Phase 2: AWS integrations
│   │   ├── __init__.py
│   │   ├── config.py                # AWS configuration (env vars)
│   │   ├── s3_manager.py            # S3 document CRUD operations
│   │   ├── kb_service.py            # Bedrock Knowledge Base service
│   │   ├── agents.py                # Cloud LLM agents (Strands + Bedrock)
│   │   └── handlers.py              # Phase 2 IPC handlers
│   ├── ipc/
│   │   ├── __init__.py
│   │   ├── server.py                # Unix socket server (Phase 1 + Phase 2)
│   │   └── protocol.py              # Message protocol definitions
│   ├── kb/
│   │   ├── __init__.py
│   │   ├── manager.py               # Knowledge base document manager
│   │   └── exceptions.py            # KB-specific exceptions
│   ├── llm/
│   │   ├── __init__.py
│   │   ├── agent.py                 # Strands Agent with Ollama
│   │   ├── service.py               # LLM service layer
│   │   └── exceptions.py            # LLM-specific exceptions
│   └── transcription/
│       ├── __init__.py
│       ├── engine.py                # MLX-Whisper transcription engine
│       └── service.py               # Transcription service with buffering
│   └── tests/                       # Python tests
│       ├── test_agents.py           # Cloud LLM agents tests
│       ├── test_handlers.py         # Phase 2 IPC handlers tests
│       ├── test_kb.py               # Knowledge base manager tests
│       ├── test_kb_service.py       # KB service tests
│       ├── test_llm.py              # Local LLM tests
│       ├── test_protocol.py         # IPC protocol tests
│       ├── test_s3_manager.py       # S3 document manager tests
│       └── test_transcription.py    # Transcription engine tests
│
└── .kiro/
    ├── specs/dev-echo-phase1/       # Spec documents
    │   ├── requirements.md
    │   ├── design.md
    │   └── tasks.md
    └── steering/
        └── dev-echo-steering.md     # AI assistant rules
```

## Implementation

##### TUI Implementation Pattern: "Append to Scrollback + Redraw Prompt"
The TUI follows the Claude Code pattern for terminal rendering:

1. **No Alternate Screen Buffer** - Uses normal terminal mode so all output goes to native scrollback buffer
2. **Native Mouse Scroll** - Terminal's built-in scrollback allows natural mouse scrolling through history
3. **Scrollback Pattern** - New content (transcripts, messages) is simply printed and scrolls up naturally
4. **Prompt Restoration** - When async content arrives during input, current line is cleared, content printed, then prompt restored with current input
5. **Same-Source Line Aggregation** - Consecutive transcripts from same source update the same line instead of creating new lines

```
[Terminal Scrollback Buffer - mouse scrollable]
│
│  🔊 [10:30:15] Let's discuss the API design and how we should...  ← updates in place
│  🎤 [10:30:18] I think we should use REST for this...             ← updates in place
│  ✅ Connected to Python backend
│  ... (all output scrolls up naturally)
│
├─────────────────────────────────────
│  🎙️ Transcribing │ 🔊ON 🎤ON │ /chat /quick /stop /save /quit
│  ❯ _                              ← cursor here
```

Key implementation details:
- Status bar + commands shown before each prompt (not fixed footer)
- Async transcript updates: `\r\e[K` clears line, prints content, restores `❯ {input}`
- Same-source aggregation: `\e[A\e[K` moves up and clears to update previous transcript line
- Tracks `lastTranscriptSource`, `lastTranscriptLine`, `lastTranscriptTimestamp` for aggregation
- All debug logs and messages use same scrollback pattern

## Key Components

### Swift CLI Components

| Component | File | Description |
|-----------|------|-------------|
| **Entry Point** | `main.swift` | ArgumentParser command, Application class |
| **KBService** | `Services/KBService.swift` | KB CRUD operations via IPC |
| **LLMService** | `Services/LLMService.swift` | Local/Cloud LLM queries via IPC |
| **TerminalRenderer** | `Services/TerminalRenderer.swift` | Display width, wrapping, status line |
| **InputHandler** | `Services/InputHandler.swift` | Raw mode terminal input handling |
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
| **MicrophoneCapture** | `Audio/MicrophoneCapture.swift` | AVAudioEngine microphone input with VAD |
| **SampleRateConverter** | `Audio/SampleRateConverter.swift` | 48kHz → 16kHz conversion (vDSP) |
| **AudioCaptureEngine** | `Audio/AudioCaptureEngine.swift` | Unified capture + IPC streaming |

### Python Backend Components

| Component | File | Description |
|-----------|------|-------------|
| **IPC Server** | `ipc/server.py` | Asyncio Unix socket server (Phase 1 + Phase 2) |
| **Protocol** | `ipc/protocol.py` | Message protocol definitions (Phase 1 + Phase 2) |
| **TranscriptionEngine** | `transcription/engine.py` | MLX-Whisper transcription |
| **TranscriptionService** | `transcription/service.py` | Audio buffering + transcription + aggregation |
| **LocalLLMAgent** | `llm/agent.py` | Strands Agent with Ollama/Llama |
| **LLMService** | `llm/service.py` | LLM service layer for IPC |
| **KnowledgeBaseManager** | `kb/manager.py` | KB document operations (list, add, update, remove) |
| **AWSConfig** | `aws/config.py` | AWS configuration from environment variables |
| **S3DocumentManager** | `aws/s3_manager.py` | S3 document CRUD with pagination |
| **KnowledgeBaseService** | `aws/kb_service.py` | Bedrock KB connectivity, sync status, sync trigger |
| **SimpleCloudAgent** | `aws/agents.py` | Strands Agent with Bedrock Claude (transcript-only) |
| **RAGCloudAgent** | `aws/agents.py` | Strands Agent with Bedrock KB retrieval (RAG) |
| **IntentClassifier** | `aws/agents.py` | Keyword-based query intent classification |
| **CloudLLMService** | `aws/agents.py` | Service layer routing queries to appropriate agent |
| **ConversationContext** | `aws/agents.py` | Context dataclass with transcript and user query |
| **CloudLLMResponse** | `aws/agents.py` | Response dataclass with content, sources, tokens |
| **CloudLLMHandler** | `aws/handlers.py` | IPC handler for Cloud LLM queries |
| **S3KBHandler** | `aws/handlers.py` | IPC handler for S3-based KB operations |
| **KBSyncHandler** | `aws/handlers.py` | IPC handler for KB sync status and triggers |
| **Backend Main** | `main.py` | Backend entry point (Phase 1 + Phase 2 auto-detection) |

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

## Phase 2 IPC Integration

Phase 2 services are automatically enabled when AWS environment variables are configured:
- `DEVECHO_S3_BUCKET`: S3 bucket for KB documents
- `DEVECHO_KB_ID`: Bedrock Knowledge Base ID
- `AWS_REGION`: AWS region (default: us-west-2)
- `DEVECHO_BEDROCK_MODEL`: Bedrock model ID (default: Claude Sonnet)

### Phase 2 Message Types
| Message Type | Direction | Description |
|--------------|-----------|-------------|
| `cloud_llm_query` | CLI → Backend | Cloud LLM query with RAG support |
| `cloud_llm_response` | Backend → CLI | Response with content and sources |
| `cloud_llm_error` | Backend → CLI | Error with type and suggestion |
| `kb_list` (paginated) | CLI → Backend | List S3 documents with pagination |
| `kb_list_response` | Backend → CLI | Documents with has_more flag |
| `kb_sync_status` | CLI → Backend | Request KB sync status |
| `kb_sync_trigger` | CLI → Backend | Trigger KB reindexing |

### Phase 2 Handler Architecture
```
IPC Server
├── Phase 1 Handlers (local)
│   ├── audio_data → TranscriptionService
│   ├── llm_query → LLMService (Ollama)
│   └── kb_* → KnowledgeBaseManager (local files)
│
└── Phase 2 Handlers (cloud, auto-enabled if configured)
    ├── cloud_llm_query → CloudLLMHandler → CloudLLMService
    ├── kb_list → S3KBHandler → S3DocumentManager
    ├── kb_add/update/remove → S3KBHandler → S3DocumentManager
    └── kb_sync_* → KBSyncHandler → KnowledgeBaseService
```

Phase 2 handlers override Phase 1 KB handlers when AWS is configured, providing S3-based storage with Bedrock KB integration.
