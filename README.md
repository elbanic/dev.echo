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

## Quick Start

```bash
# Build & run CLI
swift build
swift run dev.echo

# Run backend (separate terminal)
cd backend
source .venv/bin/activate
python main.py
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
