# dev.echo Backend

Python backend for dev.echo providing transcription and LLM integration.

## Components

- **Transcription Engine**: MLX-Whisper based local transcription
- **LLM Agent**: Strands Agent with Ollama/Llama integration
- **Knowledge Base Manager**: Document management for context
- **IPC Server**: Unix Domain Socket server for Swift CLI communication

## Installation

```bash
cd backend
pip install -e ".[dev]"
```

## Requirements

- Python 3.10+
- Ollama installed and running with Llama model
- MLX-Whisper compatible hardware (Apple Silicon)
