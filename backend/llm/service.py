"""
LLM Service

Service layer for LLM integration with IPC server.
Handles query processing and context management.

Requirements: 7.1, 7.2, 7.3, 7.4
"""

import logging
from typing import List, Optional

from .agent import LocalLLMAgent, ConversationContext, TranscriptContext, LLMResponse
from .exceptions import LLMError, OllamaUnavailableError

logger = logging.getLogger(__name__)


class LLMService:
    """
    Service layer for LLM integration.
    
    Manages the LocalLLMAgent and handles query processing
    with context from transcript history.
    
    Requirements: 7.1, 7.2, 7.3, 7.4
    """
    
    def __init__(
        self,
        model_name: str = LocalLLMAgent.DEFAULT_MODEL,
        host: str = LocalLLMAgent.DEFAULT_HOST,
    ):
        """
        Initialize the LLM service.
        
        Args:
            model_name: Ollama model name
            host: Ollama server host URL
        """
        self.agent = LocalLLMAgent(model_name=model_name, host=host)
        self._running = False
    
    async def start(self) -> None:
        """Start the LLM service."""
        if self._running:
            return
        
        logger.info("Starting LLM service...")
        
        try:
            await self.agent.initialize()
            self._running = True
            logger.info("LLM service started")
        except OllamaUnavailableError:
            # Service can start without Ollama - will check on each query
            logger.warning("Ollama not available at startup - will retry on queries")
            self._running = True
        except Exception as e:
            logger.error(f"Failed to start LLM service: {e}")
            # Still mark as running - queries will fail gracefully
            self._running = True
    
    async def stop(self) -> None:
        """Stop the LLM service."""
        if not self._running:
            return
        
        logger.info("Stopping LLM service...")
        await self.agent.shutdown()
        self._running = False
        logger.info("LLM service stopped")
    
    def is_available(self) -> bool:
        """
        Check if LLM service is available.
        
        Requirements: 7.4 - Check Ollama service availability
        """
        return self.agent.is_available()
    
    async def process_query(
        self,
        query_type: str,
        content: str,
        context: List[dict],
    ) -> LLMResponse:
        """
        Process an LLM query with context.
        
        Requirements: 7.1 - Process request using Ollama with Llama model
        Requirements: 7.2 - Include current conversation transcript as context
        
        Args:
            query_type: "chat" or "quick" (both use local LLM in Phase 1)
            content: User's query content
            context: List of transcript entries as dicts
            
        Returns:
            LLMResponse with content and model info
            
        Raises:
            OllamaUnavailableError: If Ollama is not running
            LLMError: For other errors
        """
        logger.info(f"Processing {query_type} query: {content[:50]}...")
        
        # Build conversation context from transcript
        transcript_entries = self._build_transcript_context(context)
        
        conversation_context = ConversationContext(
            transcript=transcript_entries,
            user_query=content
        )
        
        # Execute query
        response = await self.agent.query(conversation_context)
        
        logger.info(f"Query processed successfully ({response.tokens_used} tokens)")
        return response
    
    def _build_transcript_context(self, context: List[dict]) -> List[TranscriptContext]:
        """
        Build TranscriptContext list from raw context dicts.
        
        Requirements: 7.2 - Include current conversation transcript as context
        """
        entries = []
        
        for entry in context:
            try:
                transcript_entry = TranscriptContext(
                    text=entry.get("text", ""),
                    source=entry.get("source", "system"),
                    timestamp=entry.get("timestamp", 0.0)
                )
                entries.append(transcript_entry)
            except Exception as e:
                logger.warning(f"Failed to parse context entry: {e}")
                continue
        
        return entries
