# dev.echo

Real-time audio transcription & AI assistant for software developers. Capture system audio and microphone, get instant transcriptions, and query LLMs with full conversation context.

## Features

- 🎧 System audio + microphone capture (ScreenCaptureKit)
- 📝 Real-time transcription (MLX-Whisper)
- 🤖 Local LLM queries (Ollama) + Cloud LLM with RAG (Bedrock)
- 📚 Knowledge Base management (S3 + Bedrock KB)
- 🔊 Text-to-speech reading mode (Qwen3-TTS)
- 💾 Markdown transcript export

## Requirements

**Required:**
- macOS 13.0+ (ScreenCaptureKit)
- Xcode 14.0+ (for Swift build)
- Python 3.10+
- Ollama + llama3.2:3b (for `/quick` local LLM)
- MLX-Whisper (for `/new` transcription)

**Optional:**
- AWS credentials (for `/chat` cloud LLM, `/managekb` knowledge base)
- Qwen3-TTS (for `/read` text-to-speech)

## Installation

```bash
git clone https://github.com/elbanic/dev.echo.git
cd dev.echo

# Build Swift CLI
swift build

# Setup Python backend
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
cd ..

# Run setup wizard
.build/debug/dev.echo setup

# Start dev.echo
./scripts/dev-echo
```

### Setup Wizard

The setup wizard will:
1. Check and install Ollama if needed
2. Download required LLM model (llama3.2:3b)
3. Verify MLX-Whisper and TTS model cache
4. Optionally configure AWS cloud features

## Commands

### CLI Commands

```bash
./scripts/dev-echo           # Start dev.echo (backend + CLI)
.build/debug/dev.echo setup  # Run setup wizard
.build/debug/dev.echo setup --default      # Auto-accept all defaults
.build/debug/dev.echo setup --skip-cloud   # Skip AWS configuration
```

### Application Commands

| Mode | Command | Description |
|------|---------|-------------|
| Command | `/new` | Start transcribing |
| Command | `/read` | Enter reading (TTS) mode |
| Command | `/managekb` | Enter KB management |
| Command | `/quit` | Exit app |
| Transcribing | `/chat {msg}` | Query Cloud LLM with RAG |
| Transcribing | `/quick {msg}` | Query local LLM |
| Transcribing | `/stop` | Stop capture |
| Transcribing | `/save` | Export transcript |
| Transcribing | `/mic [on\|off]` | Toggle microphone |
| Reading | `/voice [preset]` | List or change voice |
| Reading | `/stop` | Stop speaking |
| KB | `/list` | List documents |
| KB | `/add {path} {name}` | Add document |
| KB | `/remove {name}` | Remove document |
| KB | `/sync` | Trigger KB sync |

## Usage Examples

### Basic Workflow

```
❯ /new                              # Start transcribing mode
🎙️ Transcribing │ 🔊ON 🎤OFF

🔊 [10:30:15] Let's discuss the API design...
🔊 [10:30:18] I think we should use REST for this endpoint.

❯ /chat summarize the discussion    # Query Cloud LLM with transcript context
🤖 The discussion covered API design, with a preference for REST endpoints...

❯ /save                             # Export transcript to markdown
💾 Saved to: transcript_2026-01-27_103045.md
```

### Reading Mode (TTS)

```
❯ /read                             # Enter reading mode
📖 Reading Mode
   Voice: Chelsie (English)

❯ Hello, this is a test.            # Type or paste text to read aloud
   🔊 Speaking...

❯ /voice                            # List available voices
❯ /voice ko                         # Switch to Korean voice
```

### Using Microphone

```
❯ /new
❯ /mic on                           # Enable microphone capture
🎤 Microphone enabled

🔊 [10:31:00] What do you think about this approach?
                   🎤 [10:31:05] I agree, let's go with that design.

❯ /quick what was decided?          # Quick query with local LLM
🤖 The team agreed on the proposed design approach.
```

## Configuration

### Setup Wizard

Run `.build/debug/dev.echo setup` to configure dev.echo interactively:

```
🎙️  dev.echo Setup v1.0.0

[1/5] Ollama
  ✓ Ollama installed (v0.12.0)
  ✓ Ollama running

[2/5] LLM Model
  ✓ Model llama3.2:3b installed

[3/5] MLX-Whisper Model
  ✓ Model cached

[4/5] TTS Model (Qwen3-TTS)
  ✓ Model cached

[5/5] AWS Cloud Features
  ○ Skipped

Setup Complete!
```

Configuration is saved to `~/.config/devecho/config.json`.

### AWS Configuration (Optional)

For cloud features (Cloud LLM with RAG, S3-based Knowledge Base):

1. Run setup with AWS: `.build/debug/dev.echo setup`
2. Or create `backend/.env.dev` manually:

```bash
# backend/.env.dev
export AWS_REGION="us-east-1"
export DEVECHO_S3_BUCKET="your-bucket-name"
export DEVECHO_KB_ID="your-knowledge-base-id"
export DEVECHO_KB_DS_ID="your-data-source-id"
export DEVECHO_BEDROCK_MODEL="us.anthropic.claude-sonnet-4-20250514-v1:0"
```

| Variable | Required | Description |
|----------|----------|-------------|
| `AWS_REGION` | Yes* | AWS region for Bedrock and S3 |
| `DEVECHO_S3_BUCKET` | Yes* | S3 bucket name for KB documents |
| `DEVECHO_KB_ID` | Yes* | Bedrock Knowledge Base ID |
| `DEVECHO_KB_DS_ID` | No | Bedrock KB Data Source ID (for sync) |
| `DEVECHO_BEDROCK_MODEL` | No | Bedrock model ID (default: Claude Sonnet) |

*Required only for cloud features. Without these, dev.echo runs in local-only mode.

## Development

### Running Tests

```bash
# Python tests
cd backend && pytest

# Swift tests
swift test
```

## License

dev.echo is licensed under the MIT License. See [LICENSE](LICENSE) for details.

### Third-Party Licenses

This project uses the following third-party software:

- **OpenAI Whisper & MLX-Whisper**: MIT License
- **Llama 3.2** (via Ollama): Llama 3.2 Community License
  - Free for applications with <700M monthly active users
  - Must comply with [Acceptable Use Policy](https://www.llama.com/llama3_2/use-policy)
- **Qwen3-TTS**: Apache License 2.0
- **AWS SDK (boto3)**: Apache License 2.0
- **Ollama**: MIT License
- **Apple MLX**: MIT License

See [NOTICE](NOTICE) for complete third-party notices.

### Built with Llama

This project uses Meta's Llama 3.2 models for local LLM functionality.
