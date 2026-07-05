# dev.echo Backend

Python backend for dev.echo providing transcription and LLM integration.

## Components

- **Transcription Engine**: MLX-Whisper based local transcription
- **LLM Agent**: Strands Agent with Ollama/Llama integration
- **Knowledge Base Manager**: Document management for context
- **IPC Server**: Unix Domain Socket server for Swift CLI communication
- **S3 Document Manager**: AWS S3 based document storage for Bedrock KB
- **Knowledge Base Service**: AWS Bedrock Knowledge Base integration

## Installation

```bash
cd backend
pip install -e ".[dev]"
```

## Requirements

- Python 3.10+
- Ollama installed and running with Llama model
- MLX-Whisper compatible hardware (Apple Silicon)

## AWS Configuration (Phase 2)

Phase 2 features require AWS credentials and the following environment variables:

```bash
# Required for AWS Bedrock and Knowledge Base features
export AWS_REGION="us-west-2"                    # AWS region (default: us-west-2)
export DEVECHO_S3_BUCKET="your-bucket-name"      # S3 bucket for KB documents
export DEVECHO_S3_PREFIX="kb-documents/"         # S3 key prefix (default: kb-documents/)
export DEVECHO_KB_ID="your-knowledge-base-id"    # Bedrock Knowledge Base ID
export DEVECHO_KB_DS_ID="your-data-source-id"    # Bedrock KB Data Source ID (for sync)
export DEVECHO_BEDROCK_MODEL="us.anthropic.claude-sonnet-4-20250514-v1:0"  # Bedrock model ID
```

AWS credentials can be configured via:
- AWS CLI (`aws configure`)
- Environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`)
- IAM role (when running on AWS infrastructure)
