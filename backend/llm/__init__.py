"""
LLM Integration Module

Provides local LLM integration via Strands Agent with Ollama provider.
"""

from .agent import LocalLLMAgent, LLMResponse, ConversationContext, TranscriptContext
from .service import LLMService
from .exceptions import LLMError, OllamaUnavailableError, ModelNotFoundError

__all__ = [
    "LocalLLMAgent",
    "LLMResponse",
    "ConversationContext",
    "TranscriptContext",
    "LLMService",
    "LLMError",
    "OllamaUnavailableError",
    "ModelNotFoundError",
]
