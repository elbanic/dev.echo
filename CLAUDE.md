# dev.echo Project Status

## Language Preferences

- **Conversation**: Always respond in Korean (한국어)
- **Documentation & Code**: Write in English by default (unless explicitly requested otherwise)

## Git Commit Rules

- **Do NOT add Co-Authored-By** line in commit messages
- Before committing or pushing, ALWAYS review the code to ensure you're not uploading any security-related credentials.

---

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
│   │   ├── TTSEngine.swift          # Text-to-speech (AVSpeechSynthesizer)
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
│       └── ApplicationMode.swift    # App mode enum (command, transcribing, kb, reading)
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
| **TTSEngine** | `Services/TTSEngine.swift` | Text-to-speech engine (AVSpeechSynthesizer) |
| **TerminalRenderer** | `Services/TerminalRenderer.swift` | Display width, wrapping, status line |
| **InputHandler** | `Services/InputHandler.swift` | Raw mode terminal input, command history, cursor navigation |
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
    case read                          // Command Mode → Reading Mode
    case chat(content: String)         // Transcribing Mode
    case quick(content: String)
    case stop, save
    case list                          // KB Management Mode
    case remove(name: String)
    case update(fromPath: String, name: String)
    case add(fromPath: String, name: String)
    case voice(name: String?)          // Reading Mode
    case unknown(input: String)
}
```

### Application Modes (Swift)
```swift
enum ApplicationMode {
    case command                       // Default - select mode
    case transcribing                  // Audio capture active
    case knowledgeBaseManagement       // Managing KB docs
    case reading                       // Text-to-speech mode
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
# Unified launcher (recommended)
./scripts/dev-echo              # Start both backend and CLI
./scripts/dev-echo --debug      # With debug logging
./scripts/dev-echo --backend-only  # Backend only
./scripts/dev-echo --cli-only   # CLI only (backend must be running)

# Manual execution (if needed)
swift build                     # Build Swift CLI
swift run dev.echo              # Run CLI directly

# Python backend (manual)
cd backend
source .venv/bin/activate
python main.py                  # Run backend server

# Tests
cd backend && pytest            # Python tests
swift test                      # Swift tests
```

## Debug Mode

### CLI Debug Mode
- **CLI flag**: `--debug` enables verbose logging at startup
- **Runtime toggle**: Press `Ctrl+B` to toggle debug mode while running
- **Scope**: Affects IPCClient, AudioCaptureEngine, SystemAudioCapture, MicrophoneCapture
- **Default**: Debug OFF (only warnings and transcription output shown)

### Input Handler Features
The `InputHandler` provides shell-like input experience:
- **Command History**: Up/Down arrow keys navigate through previously entered commands
- **Cursor Navigation**: Left/Right arrow keys move cursor within current input
- **Tab Completion**: Tab key cycles through matching commands (for `/` prefixed commands)
- **In-place Editing**: Insert/delete characters at cursor position
- **History Persistence**: Commands stored in memory (max 100 entries per session)

### Backend Debug Mode
The Python backend debug mode can be enabled in several ways:

1. **Via launcher script (both backend + CLI)**:
   ```bash
   ./scripts/dev-echo --debug
   ```
   This enables debug mode for both Swift CLI and Python backend.

2. **CLI only debug (backend running separately)**:
   ```bash
   # Terminal 1: Start backend normally
   cd backend && source .venv/bin/activate
   python main.py
   
   # Terminal 2: Start CLI with debug
   ./scripts/dev-echo --cli-only --debug
   ```

3. **Backend only debug (CLI running separately)**:
   ```bash
   # Terminal 1: Start backend with debug
   cd backend && source .venv/bin/activate
   DEVECHO_LOG_LEVEL=DEBUG python main.py
   
   # Terminal 2: Start CLI normally
   ./scripts/dev-echo --cli-only
   ```

4. **Via `.env.dev` file (always debug for backend)**:
   Add to `backend/.env.dev`:
   ```bash
   export DEVECHO_LOG_LEVEL="DEBUG"
   ```

Debug mode enables:
- Detailed logging output from all backend components
- Cloud LLM Agent streaming output visible in terminal (normally suppressed to prevent duplicate output)

## Backend Logging Configuration
The Python backend uses a centralized logging setup in `main.py`:
- **Log level**: Controlled via `DEVECHO_LOG_LEVEL` environment variable (default: INFO)
- **External library suppression**: Strands, boto3, botocore, urllib3, httpx logs are set to WARNING level to keep output clean
- **Format**: `HH:MM:SS [LEVEL] module: message`

To enable debug logging for the backend:
```bash
DEVECHO_LOG_LEVEL=DEBUG python main.py
```

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

---

## Custom Subagents (TDD Multi-Agent System)

This project uses a 4-agent TDD feedback loop. Agents are defined in `.claude/agents/`.

### Agent Overview

| Agent | TDD Phase | Purpose | Tools |
|-------|-----------|---------|-------|
| 🧪 `test-architect` | RED | Design & write failing tests | Read, Write, Glob, Grep, Bash |
| ⚙️ `implementer` | GREEN | Write minimal code to pass tests | Read, Write, Edit, Glob, Grep, Bash |
| 🔍 `code-reviewer` | Quality Gate | Review code, approve/reject | Read, Glob, Grep, Bash (read-only) |
| ✨ `refactorer` | REFACTOR | Improve code without changing behavior | Read, Write, Edit, Glob, Grep, Bash |

### TDD Feedback Loop

```
┌─────────────────────────────────────────────────────────────┐
│                    TDD Cycle Flow                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   🧪 test-architect                                         │
│      │ "Write failing tests for [component]"                │
│      │                                                      │
│      ▼ (failing tests)                                      │
│   ⚙️ implementer                                            │
│      │ "Make these tests pass"                              │
│      │                                                      │
│      ▼ (implementation)                                     │
│   🔍 code-reviewer                                          │
│      │ "Review this implementation"                         │
│      │                                                      │
│      ├─── REJECT → back to implementer                      │
│      │                                                      │
│      ▼ APPROVE                                              │
│   ✨ refactorer                                             │
│      │ "Improve this code"                                  │
│      │                                                      │
│      ▼ (edge cases found)                                   │
│   🧪 test-architect (next cycle)                            │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Usage Examples

```bash
# Start TDD cycle for a new component
> Use test-architect to write property tests for PromptAnalyzer based on Properties 2-5

# After tests are written
> Use implementer to make these tests pass

# After implementation
> Use code-reviewer to review the PromptAnalyzer implementation

# After approval
> Use refactorer to improve the PromptAnalyzer code

# Or invoke directly with Task tool
> @test-architect Write property tests for confidence scoring (Property 12)
```

### When to Use Each Agent

| Scenario | Agent to Use |
|----------|--------------|
| Starting new feature | test-architect |
| Tests exist but failing | implementer |
| Implementation complete | code-reviewer |
| Code approved, needs cleanup | refactorer |
| Bug found in production | test-architect (write test first!) |
| Performance issue | refactorer |

---

## TDD Workflow Protocol

### Prompt Template for Task Implementation

Use this template when requesting task implementation:

```
Implement Task [X.Y]: [Task Name]

References:
- Requirements: .kiro/specs/claude-code-sentinel/requirements.md (Requirement [N])
- Design: .kiro/specs/claude-code-sentinel/design.md
- Properties to validate: [Property numbers]

TDD Loop Rules:
1. Execute: test-architect → implementer → code-reviewer → refactorer
2. MAX 3 ITERATIONS per cycle
3. If unresolved after 3 loops: STOP and report to user
4. On task completion: ASK user confirmation before updating tasks.md

Acceptance Criteria:
- [ ] [Criterion 1]
- [ ] [Criterion 2]
- [ ] All property tests pass
- [ ] Code review approved
```

### Compact Version

```
Implement Task 2.1: Intent Classifier

TDD Loop (max 3 iterations):
🧪 → ⚙️ → 🔍 → ✨ → (repeat if needed)

STOP conditions:
- 3 iterations without resolution → ask user
- Unclear requirements → ask user
- Task complete → confirm with user, then update tasks.md

Properties: 2, 3 from design.md
```

### Loop Execution Rules

| Iteration | Action |
|-----------|--------|
| 1st | Normal TDD cycle |
| 2nd | Focus on specific failing tests |
| 3rd | Final attempt with simplified approach |
| 4th+ | **STOP** - Report status and ask user for guidance |

### Stop and Report Format

When stopping after 3 iterations:

```
## TDD Loop Status Report

### Task: [X.Y] [Task Name]
### Iterations Completed: 3

### Current State:
- Tests passing: X/Y
- Failing tests: [list]
- Blocker: [specific issue]

### Attempted Solutions:
1. [Approach 1] - Result: [outcome]
2. [Approach 2] - Result: [outcome]
3. [Approach 3] - Result: [outcome]

### Options for User:
A) [Suggested direction 1]
B) [Suggested direction 2]
C) Provide additional guidance

Awaiting your input before continuing.
```

### Task Completion Protocol

When task is complete:

```
## Task Completion: [X.Y] [Task Name]

### Summary:
- All tests passing: ✅
- Code review: APPROVED
- Refactoring: Complete

### Files Created/Modified:
- [file1.ts] - [purpose]
- [file2.ts] - [purpose]

### Properties Validated:
- Property [N]: ✅
- Property [M]: ✅

---
**Ready to mark as complete?**
Reply "yes" to update tasks.md, or provide feedback.
```

After user confirms, update `.kiro/specs/claude-code-sentinel/tasks.md`:
- Change `- [ ]` to `- [x]` for completed task

### Parallel Task Implementation

For parallelizable tasks:

```
Implement IN PARALLEL:
- Task 4.1: SQLite metadata storage
- Task 4.2: Markdown note parser
- Task 4.3: Vector storage (ChromaDB)

Each task follows TDD Loop (max 3 iterations).
Report completion for ALL tasks together.
I will confirm before updating tasks.md.
```

### Quick Reference Commands

| Command | Purpose |
|---------|---------|
| `Implement Task X.Y` | Start single task with TDD loop |
| `Implement Tasks X.Y, X.Z in parallel` | Start parallel tasks |
| `Continue from iteration N` | Resume stopped loop |
| `Skip to refactorer` | After manual fix, continue cycle |
| `Mark Task X.Y complete` | Force complete (after manual verification) |

---