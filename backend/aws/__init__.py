"""
AWS Integration Module for dev.echo Phase 2

This module provides AWS service integrations:
- S3 Document Manager: CRUD operations for knowledge base documents
- Knowledge Base Service: Bedrock Knowledge Base operations
- Cloud LLM Agents: Strands Agent with Bedrock Claude
- AWS Configuration: Environment-based configuration
- IPC Handlers: Phase 2 message handlers for IPC server
"""

from .config import AWSConfig
from .s3_manager import (
    S3DocumentManager,
    S3Document,
    S3DocumentError,
    DocumentNotFoundError,
    DocumentExistsError,
    InvalidMarkdownError,
)
from .kb_service import (
    KnowledgeBaseService,
    SyncStatus,
    RetrievalResult,
    KBServiceError,
    KBNotFoundError,
    KBAccessDeniedError,
    KBSyncError,
)
from .agents import (
    SimpleCloudAgent,
    RAGCloudAgent,
    IntentClassifier,
    CloudLLMService,
    QueryIntent,
    TranscriptContext,
    ConversationContext,
    CloudLLMResponse,
    CloudLLMError,
    BedrockUnavailableError,
    BedrockAccessDeniedError,
    CloudQueryTimeoutError,
)
from .handlers import (
    CloudLLMHandler,
    S3KBHandler,
    KBSyncHandler,
)

__all__ = [
    # Config
    "AWSConfig",
    # S3 Document Manager
    "S3DocumentManager",
    "S3Document",
    "S3DocumentError",
    "DocumentNotFoundError",
    "DocumentExistsError",
    "InvalidMarkdownError",
    # Knowledge Base Service
    "KnowledgeBaseService",
    "SyncStatus",
    "RetrievalResult",
    "KBServiceError",
    "KBNotFoundError",
    "KBAccessDeniedError",
    "KBSyncError",
    # Cloud LLM Agents
    "SimpleCloudAgent",
    "RAGCloudAgent",
    "IntentClassifier",
    "CloudLLMService",
    "QueryIntent",
    "TranscriptContext",
    "ConversationContext",
    "CloudLLMResponse",
    "CloudLLMError",
    "BedrockUnavailableError",
    "BedrockAccessDeniedError",
    "CloudQueryTimeoutError",
    # IPC Handlers
    "CloudLLMHandler",
    "S3KBHandler",
    "KBSyncHandler",
]
