# dev.echo

Real-time audio transcription & AI assistant for software developers. Capture system audio and microphone, get instant transcriptions, and query LLMs with full conversation context.

## Features

- 🎧 System audio + microphone capture (ScreenCaptureKit)
- 📝 Real-time transcription (MLX-Whisper)
- 🤖 Local LLM queries (Ollama) + Cloud LLM with RAG (Bedrock)
- 📚 Knowledge Base management (S3 + Bedrock KB)
- 💾 Markdown transcript export

## Prerequisites

- macOS 13.0+ (ScreenCaptureKit required)
- Xcode (for ScreenCaptureKit compilation)
- Python 3.10+
- Ollama (local LLM)
- AWS account (for cloud features)

## Installation

```bash
# 1. Build Swift CLI
swift build

# 2. Setup Python backend
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"

# 3. Configure AWS (optional, for cloud features)
cp .env.dev.example .env.dev
# Edit .env.dev with your AWS settings

# 4. Install launcher script (optional)
chmod +x scripts/dev-echo
sudo ln -s "$(pwd)/scripts/dev-echo" /usr/local/bin/dev-echo
```

## Quick Start

### Using the Launcher Script (Recommended)

The `dev-echo` script starts both the Python backend and Swift CLI together:

```bash
dev-echo
```

Options:
- `dev-echo` - Start both backend and CLI
- `dev-echo --debug` - Enable debug logging
- `dev-echo --backend-only` - Start only the Python backend
- `dev-echo --cli-only` - Start only the CLI (backend must be running)

The script automatically:
- Loads environment variables from `backend/.env.dev`
- Waits for MLX-Whisper model to load
- Cleans up both processes on Ctrl+C

### Manual Start (Development)

```bash
# Terminal 1: Run backend
cd backend
source .venv/bin/activate
python main.py

# Terminal 2: Build & run CLI
swift build
swift run dev.echo
```

## Commands

| Mode | Command | Description |
|------|---------|-------------|
| Command | `/new` | Start transcribing |
| Command | `/managekb` | Enter KB management |
| Command | `/quit` | Exit app |
| Transcribing | `/chat {msg}` | Query Cloud LLM |
| Transcribing | `/quick {msg}` | Query local LLM |
| Transcribing | `/stop` | Stop capture |
| Transcribing | `/save` | Export transcript |
| Transcribing | `/mic [on\|off]` | Toggle microphone |
| KB | `/list` | List documents |
| KB | `/add {path} {name}` | Add document |
| KB | `/remove {name}` | Remove document |
| KB | `/sync` | Trigger KB sync |

## AWS Configuration (Phase 2)

```bash
export AWS_REGION="your-knowledgebase-region"                    # AWS region (default: us-west-2)
export DEVECHO_S3_BUCKET="your-bucket-name"      # S3 bucket for KB documents
export DEVECHO_S3_PREFIX="kb-documents/"         # S3 key prefix (default: kb-documents/)
export DEVECHO_KB_ID="your-knowledge-base-id"    # Bedrock Knowledge Base ID
export DEVECHO_KB_DS_ID="your-data-source-id"    # Bedrock KB Data Source ID (for sync)
export DEVECHO_BEDROCK_MODEL="us.anthropic.claude-sonnet-4-20250514-v1:0"  # Bedrock model ID
```
