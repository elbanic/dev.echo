"""
Local LLM Agent

Strands Agent wrapper for Ollama/Llama integration.
Provides context-aware LLM queries for dev.echo.

Requirements: 7.1, 7.2, 7.3, 7.4
"""

import asyncio
import logging
from dataclasses import dataclass, field
from typing import List, Optional

import ollama
from strands import Agent
from strands.models.ollama import OllamaModel

from .exceptions import (
    LLMError,
    OllamaUnavailableError,
    ModelNotFoundError,
    QueryTimeoutError,
)

logger = logging.getLogger(__name__)


@dataclass
class TranscriptContext:
    """Single transcript entry for context."""
    text: str
    source: str  # "system" or "microphone"
    timestamp: float


@dataclass
class ConversationContext:
    """Context for LLM queries including transcript history."""
    transcript: List[TranscriptContext] = field(default_factory=list)
    user_query: str = ""
    
    def to_context_string(self) -> str:
        """
        Convert transcript to a formatted context string.
        
        Requirements: 7.2 - Include current conversation transcript as context
        """
        if not self.transcript:
            return ""
        
        lines = ["## Conversation Transcript\n"]
        for entry in self.transcript:
            source_label = "🔊 System" if entry.source == "system" else "🎤 You"
            lines.append(f"{source_label}: {entry.text}")
        
        return "\n".join(lines)


@dataclass
class LLMResponse:
    """Response from LLM query."""
    content: str
    model: str
    tokens_used: int = 0


class LocalLLMAgent:
    """
    Strands Agent wrapper for Ollama/Llama.
    
    Provides local LLM integration for quick responses without network latency.
    
    Requirements: 7.1, 7.2, 7.3, 7.4
    """
    
    DEFAULT_MODEL = "llama3.2:3b"
    DEFAULT_HOST = "http://localhost:11434"
    DEFAULT_TIMEOUT = 60.0  # seconds
    
    def __init__(
        self,
        model_name: str = DEFAULT_MODEL,
        host: str = DEFAULT_HOST,
        timeout: float = DEFAULT_TIMEOUT,
    ):
        """
        Initialize the Local LLM Agent.
        
        Args:
            model_name: Ollama model name (default: llama3.2)
            host: Ollama server host URL
            timeout: Query timeout in seconds
        """
        self.model_name = model_name
        self.host = host
        self.timeout = timeout
        
        self._agent: Optional[Agent] = None
        self._ollama_client: Optional[ollama.Client] = None
        self._initialized = False

    async def initialize(self) -> None:
        """
        Initialize Strands Agent with Ollama provider.
        
        Requirements: 7.1 - Process request using Ollama with Llama model
        
        Raises:
            OllamaUnavailableError: If Ollama service is not running
            ModelNotFoundError: If the specified model is not available
        """
        if self._initialized:
            return
        
        logger.info(f"Initializing LocalLLMAgent with model: {self.model_name}")
        
        # Check Ollama availability first
        if not self.is_available():
            raise OllamaUnavailableError()
        
        # Check if model exists
        if not await self._check_model_exists():
            raise ModelNotFoundError(self.model_name)
        
        try:
            # Initialize Ollama client
            self._ollama_client = ollama.Client(host=self.host)
            
            # Initialize Strands Agent with Ollama model
            ollama_model = OllamaModel(
                model_id=self.model_name,
                host=self.host,
            )
            
            self._agent = Agent(
                model=ollama_model,
                system_prompt=self._get_system_prompt(),
            )
            
            self._initialized = True
            logger.info(f"LocalLLMAgent initialized successfully with {self.model_name}")
            
        except Exception as e:
            logger.error(f"Failed to initialize LocalLLMAgent: {e}")
            raise LLMError(f"Failed to initialize agent: {e}")
    
    def is_available(self) -> bool:
        """
        Check if Ollama service is running.
        
        Requirements: 7.4 - Check Ollama service availability
        
        Returns:
            True if Ollama is running and accessible, False otherwise
        """
        try:
            client = ollama.Client(host=self.host)
            # Try to list models - this will fail if Ollama is not running
            client.list()
            return True
        except Exception as e:
            logger.warning(f"Ollama service check failed: {e}")
            return False
    
    async def _check_model_exists(self) -> bool:
        """Check if the specified model is available in Ollama."""
        try:
            client = ollama.Client(host=self.host)
            result = client.list()
            
            # Handle new ollama library format (ListResponse with models attribute)
            if hasattr(result, 'models'):
                model_names = [m.model.split(":")[0] for m in result.models]
                full_model_names = [m.model for m in result.models]
            else:
                # Fallback for older format
                model_names = [m.get("name", "").split(":")[0] for m in result.get("models", [])]
                full_model_names = [m.get("name", "") for m in result.get("models", [])]
            
            # Check for exact match or base name match
            base_model_name = self.model_name.split(":")[0]
            return (
                self.model_name in full_model_names or
                base_model_name in model_names or
                any(base_model_name in name for name in model_names)
            )
        except Exception as e:
            logger.error(f"Failed to check model availability: {e}")
            return False
    
    def _get_system_prompt(self) -> str:
        """Get the system prompt for the agent."""
        return """You are dev.echo, an AI assistant for developers. You help with:
- Understanding conversations and meetings
- Answering technical questions
- Providing code suggestions and explanations
- Summarizing discussions

You have access to the conversation transcript as context. Use it to provide relevant, context-aware responses.
Be concise and helpful. Focus on actionable information."""

    async def query(self, context: ConversationContext) -> LLMResponse:
        """
        Send query with context to local LLM.
        
        Requirements: 7.2 - Include current conversation transcript as context
        Requirements: 7.3 - Display response in transcript area
        
        Args:
            context: ConversationContext with transcript and user query
            
        Returns:
            LLMResponse with content and model info
            
        Raises:
            OllamaUnavailableError: If Ollama is not running
            QueryTimeoutError: If query times out
            LLMError: For other errors
        """
        if not self._initialized:
            await self.initialize()
        
        # Check availability before query
        if not self.is_available():
            raise OllamaUnavailableError()
        
        # Build prompt with context
        prompt = self._build_prompt(context)
        
        logger.debug(f"Sending query to {self.model_name}: {context.user_query[:100]}...")
        
        try:
            # Run query with timeout
            response = await asyncio.wait_for(
                self._execute_query(prompt),
                timeout=self.timeout
            )
            
            logger.info(f"Received response from {self.model_name} ({response.tokens_used} tokens)")
            return response
            
        except asyncio.TimeoutError:
            raise QueryTimeoutError(self.timeout)
        except OllamaUnavailableError:
            raise
        except Exception as e:
            logger.error(f"LLM query failed: {e}")
            raise LLMError(f"Query failed: {e}")
    
    def _build_prompt(self, context: ConversationContext) -> str:
        """
        Build the full prompt including context.
        
        Requirements: 7.2 - Include current conversation transcript as context
        """
        parts = []
        
        # Add transcript context if available
        context_str = context.to_context_string()
        if context_str:
            parts.append(context_str)
            parts.append("\n---\n")
        
        # Add user query
        parts.append(f"User Query: {context.user_query}")
        
        return "\n".join(parts)
    
    async def _execute_query(self, prompt: str) -> LLMResponse:
        """Execute the query using Strands Agent."""
        if not self._agent:
            raise LLMError("Agent not initialized")
        
        try:
            # Use Strands Agent to process the query
            result = self._agent(prompt)
            
            # Extract response content
            content = str(result)
            
            # Estimate tokens (rough approximation)
            tokens_used = len(prompt.split()) + len(content.split())
            
            return LLMResponse(
                content=content,
                model=self.model_name,
                tokens_used=tokens_used
            )
            
        except Exception as e:
            # Check if it's an Ollama connection error
            error_str = str(e).lower()
            if "connection" in error_str or "refused" in error_str:
                raise OllamaUnavailableError()
            raise
    
    async def shutdown(self) -> None:
        """Clean up resources."""
        self._agent = None
        self._ollama_client = None
        self._initialized = False
        logger.info("LocalLLMAgent shutdown complete")
