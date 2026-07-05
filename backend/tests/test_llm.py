"""
Tests for LLM Integration Module

Tests for LocalLLMAgent, LLMService, and related components.
"""

import pytest
from unittest.mock import Mock, patch, AsyncMock

from llm import (
    LocalLLMAgent,
    LLMResponse,
    ConversationContext,
    TranscriptContext,
    LLMService,
    LLMError,
    OllamaUnavailableError,
    ModelNotFoundError,
)


class TestTranscriptContext:
    """Tests for TranscriptContext dataclass."""
    
    def test_creation(self):
        """Test TranscriptContext creation."""
        ctx = TranscriptContext(
            text="Hello world",
            source="system",
            timestamp=1234567890.0
        )
        assert ctx.text == "Hello world"
        assert ctx.source == "system"
        assert ctx.timestamp == 1234567890.0
    
    def test_microphone_source(self):
        """Test TranscriptContext with microphone source."""
        ctx = TranscriptContext(
            text="My voice",
            source="microphone",
            timestamp=1234567890.0
        )
        assert ctx.source == "microphone"


class TestConversationContext:
    """Tests for ConversationContext dataclass."""
    
    def test_empty_context(self):
        """Test ConversationContext with no transcript."""
        ctx = ConversationContext(user_query="What is this?")
        assert ctx.transcript == []
        assert ctx.user_query == "What is this?"
    
    def test_to_context_string_empty(self):
        """Test to_context_string with empty transcript."""
        ctx = ConversationContext(user_query="Test")
        assert ctx.to_context_string() == ""
    
    def test_to_context_string_with_entries(self):
        """Test to_context_string with transcript entries."""
        ctx = ConversationContext(
            transcript=[
                TranscriptContext(text="Hello", source="system", timestamp=1.0),
                TranscriptContext(text="Hi there", source="microphone", timestamp=2.0),
            ],
            user_query="Summarize"
        )
        result = ctx.to_context_string()
        
        assert "## Conversation Transcript" in result
        assert "🔊 System: Hello" in result
        assert "🎤 You: Hi there" in result


class TestLLMResponse:
    """Tests for LLMResponse dataclass."""
    
    def test_creation(self):
        """Test LLMResponse creation."""
        response = LLMResponse(
            content="This is the answer",
            model="llama3.2",
            tokens_used=100
        )
        assert response.content == "This is the answer"
        assert response.model == "llama3.2"
        assert response.tokens_used == 100
    
    def test_default_tokens(self):
        """Test LLMResponse with default tokens_used."""
        response = LLMResponse(content="Answer", model="llama3.2")
        assert response.tokens_used == 0


class TestLocalLLMAgent:
    """Tests for LocalLLMAgent class."""
    
    def test_default_configuration(self):
        """Test LocalLLMAgent default configuration."""
        agent = LocalLLMAgent()
        assert agent.model_name == "llama3.2:3b"
        assert agent.host == "http://localhost:11434"
        assert agent.timeout == 60.0
    
    def test_custom_configuration(self):
        """Test LocalLLMAgent with custom configuration."""
        agent = LocalLLMAgent(
            model_name="mistral",
            host="http://custom:11434",
            timeout=30.0
        )
        assert agent.model_name == "mistral"
        assert agent.host == "http://custom:11434"
        assert agent.timeout == 30.0
    
    def test_not_initialized_by_default(self):
        """Test that agent is not initialized by default."""
        agent = LocalLLMAgent()
        assert agent._initialized is False
        assert agent._agent is None
    
    def test_build_prompt_with_context(self):
        """Test _build_prompt includes context."""
        agent = LocalLLMAgent()
        ctx = ConversationContext(
            transcript=[
                TranscriptContext(text="Discussion", source="system", timestamp=1.0),
            ],
            user_query="What was discussed?"
        )
        
        prompt = agent._build_prompt(ctx)
        
        assert "## Conversation Transcript" in prompt
        assert "Discussion" in prompt
        assert "What was discussed?" in prompt
    
    def test_build_prompt_without_context(self):
        """Test _build_prompt without transcript context."""
        agent = LocalLLMAgent()
        ctx = ConversationContext(user_query="Hello")
        
        prompt = agent._build_prompt(ctx)
        
        assert "User Query: Hello" in prompt
        assert "## Conversation Transcript" not in prompt


class TestLLMService:
    """Tests for LLMService class."""
    
    def test_default_configuration(self):
        """Test LLMService default configuration."""
        service = LLMService()
        assert service.agent.model_name == "llama3.2:3b"
    
    def test_custom_configuration(self):
        """Test LLMService with custom configuration."""
        service = LLMService(model_name="mistral", host="http://custom:11434")
        assert service.agent.model_name == "mistral"
        assert service.agent.host == "http://custom:11434"
    
    def test_build_transcript_context(self):
        """Test _build_transcript_context method."""
        service = LLMService()
        
        context = [
            {"text": "Hello", "source": "system", "timestamp": 1.0},
            {"text": "Hi", "source": "microphone", "timestamp": 2.0},
        ]
        
        result = service._build_transcript_context(context)
        
        assert len(result) == 2
        assert result[0].text == "Hello"
        assert result[0].source == "system"
        assert result[1].text == "Hi"
        assert result[1].source == "microphone"
    
    def test_build_transcript_context_with_invalid_entry(self):
        """Test _build_transcript_context handles invalid entries."""
        service = LLMService()
        
        context = [
            {"text": "Valid", "source": "system", "timestamp": 1.0},
            {},  # Invalid entry - missing fields
            {"text": "Also valid", "source": "microphone", "timestamp": 2.0},
        ]
        
        result = service._build_transcript_context(context)
        
        # Should handle gracefully - empty dict creates entry with defaults
        assert len(result) == 3


class TestExceptions:
    """Tests for LLM exceptions."""
    
    def test_ollama_unavailable_error(self):
        """Test OllamaUnavailableError."""
        error = OllamaUnavailableError()
        assert "unavailable" in str(error).lower()
    
    def test_ollama_unavailable_error_custom_message(self):
        """Test OllamaUnavailableError with custom message."""
        error = OllamaUnavailableError("Custom message")
        assert str(error) == "Custom message"
    
    def test_model_not_found_error(self):
        """Test ModelNotFoundError."""
        error = ModelNotFoundError("llama3.2")
        assert error.model_name == "llama3.2"
        assert "llama3.2" in str(error)
        assert "ollama pull" in str(error)
