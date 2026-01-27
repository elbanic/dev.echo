"""
Tests for Cloud LLM Agents

Tests conversation memory persistence using actual Strands Agent instances.
Uses Ollama for local testing without AWS dependencies.
"""

import pytest
import asyncio
from unittest.mock import MagicMock, patch, AsyncMock

from strands import Agent

from aws.agents import (
    SimpleCloudAgent,
    RAGCloudAgent,
    CloudLLMService,
    IntentClassifier,
    QueryIntent,
    TranscriptContext,
    ConversationContext,
    CloudLLMResponse,
    CloudLLMError,
    BedrockUnavailableError,
    BedrockAccessDeniedError,
    CloudQueryTimeoutError,
)


class TestStrandsAgentMemoryPersistence:
    """
    Test that Strands Agent preserves conversation history across calls.
    
    Uses actual Strands Agent instances to verify memory behavior.
    """
    
    def test_strands_agent_preserves_messages_across_calls(self):
        """
        Verify that Strands Agent's self.messages accumulates across multiple calls.
        
        This is the core behavior we rely on for conversation memory.
        """
        # Create a real Strands Agent with a mock model
        mock_model = MagicMock()
        mock_model.converse.return_value = iter([
            {"contentBlockDelta": {"delta": {"text": "Hello!"}}},
            {"contentBlockStop": {}},
            {"messageStop": {"stopReason": "end_turn"}},
        ])
        
        agent = Agent(
            model=mock_model,
            system_prompt="You are a test assistant."
        )
        
        # Initial state - no messages
        assert len(agent.messages) == 0
        
        # First call
        agent("First message")
        
        # After first call, messages should contain user message + assistant response
        assert len(agent.messages) >= 2
        first_call_messages = len(agent.messages)
        
        # Second call
        agent("Second message")
        
        # After second call, messages should have grown
        assert len(agent.messages) > first_call_messages
        
        # Verify message content includes both user messages
        all_text = str(agent.messages)
        assert "First message" in all_text
        assert "Second message" in all_text
    
    def test_strands_agent_messages_can_be_cleared(self):
        """
        Verify that clearing agent.messages resets conversation history.
        """
        mock_model = MagicMock()
        mock_model.converse.return_value = iter([
            {"contentBlockDelta": {"delta": {"text": "Response"}}},
            {"contentBlockStop": {}},
            {"messageStop": {"stopReason": "end_turn"}},
        ])
        
        agent = Agent(
            model=mock_model,
            system_prompt="You are a test assistant."
        )
        
        # Add some messages
        agent("Test message")
        assert len(agent.messages) > 0
        
        # Clear messages
        agent.messages = []
        
        # Verify cleared
        assert len(agent.messages) == 0
    
    def test_strands_agent_messages_structure(self):
        """
        Verify the structure of messages stored by Strands Agent.
        """
        mock_model = MagicMock()
        mock_model.converse.return_value = iter([
            {"contentBlockDelta": {"delta": {"text": "I understand."}}},
            {"contentBlockStop": {}},
            {"messageStop": {"stopReason": "end_turn"}},
        ])
        
        agent = Agent(
            model=mock_model,
            system_prompt="You are a test assistant."
        )
        
        agent("Hello, remember this: my favorite color is blue.")
        
        # Check message structure
        assert len(agent.messages) >= 1
        
        # First message should be user message
        user_message = agent.messages[0]
        assert user_message["role"] == "user"
        assert "content" in user_message


class TestSimpleCloudAgentMemory:
    """Test SimpleCloudAgent conversation memory methods."""
    
    def test_initial_state(self):
        """Test initial conversation state before initialization."""
        agent = SimpleCloudAgent()
        
        assert agent.get_conversation_length() == 0
        assert agent.get_conversation_history() == []
    
    def test_clear_conversation_before_init(self):
        """Test clear_conversation works even before initialization."""
        agent = SimpleCloudAgent()
        
        # Should not raise
        agent.clear_conversation()
        
        assert agent.get_conversation_length() == 0
    
    def test_conversation_methods_with_mock_agent(self):
        """Test conversation methods with a mocked internal agent."""
        agent = SimpleCloudAgent()
        
        # Manually set up internal agent with mock messages
        mock_agent = MagicMock()
        mock_agent.messages = [
            {"role": "user", "content": [{"text": "Hello"}]},
            {"role": "assistant", "content": [{"text": "Hi there!"}]},
        ]
        agent._agent = mock_agent
        agent._initialized = True
        
        # Test get_conversation_length
        assert agent.get_conversation_length() == 2
        
        # Test get_conversation_history
        history = agent.get_conversation_history()
        assert len(history) == 2
        assert history[0]["role"] == "user"
        assert history[1]["role"] == "assistant"
        
        # Test clear_conversation
        agent.clear_conversation()
        assert mock_agent.messages == []


class TestRAGCloudAgentMemory:
    """Test RAGCloudAgent conversation memory methods."""
    
    def test_initial_state(self):
        """Test initial conversation state before initialization."""
        agent = RAGCloudAgent(knowledge_base_id="test-kb-id")
        
        assert agent.get_conversation_length() == 0
        assert agent.get_conversation_history() == []
    
    def test_clear_conversation_before_init(self):
        """Test clear_conversation works even before initialization."""
        agent = RAGCloudAgent(knowledge_base_id="test-kb-id")
        
        # Should not raise
        agent.clear_conversation()
        
        assert agent.get_conversation_length() == 0
    
    def test_conversation_methods_with_mock_agent(self):
        """Test conversation methods with a mocked internal agent."""
        agent = RAGCloudAgent(knowledge_base_id="test-kb-id")
        
        # Manually set up internal agent with mock messages
        mock_agent = MagicMock()
        mock_agent.messages = [
            {"role": "user", "content": [{"text": "What's in my docs?"}]},
            {"role": "assistant", "content": [{"text": "Based on your documents..."}]},
            {"role": "user", "content": [{"text": "Tell me more"}]},
            {"role": "assistant", "content": [{"text": "Here's more detail..."}]},
        ]
        agent._agent = mock_agent
        agent._initialized = True
        
        # Test get_conversation_length
        assert agent.get_conversation_length() == 4
        
        # Test get_conversation_history
        history = agent.get_conversation_history()
        assert len(history) == 4
        
        # Test clear_conversation
        agent.clear_conversation()
        assert mock_agent.messages == []


class TestCloudLLMServiceMemory:
    """Test CloudLLMService conversation memory management."""
    
    def test_get_conversation_info(self):
        """Test get_conversation_info returns correct structure."""
        service = CloudLLMService(knowledge_base_id="test-kb-id")
        
        info = service.get_conversation_info()
        
        assert "simple_agent" in info
        assert "rag_agent" in info
        assert "message_count" in info["simple_agent"]
        assert "initialized" in info["simple_agent"]
        assert "message_count" in info["rag_agent"]
        assert "initialized" in info["rag_agent"]
    
    def test_get_conversation_history_simple(self):
        """Test get_conversation_history for simple agent."""
        service = CloudLLMService(knowledge_base_id="test-kb-id")
        
        # Mock simple agent
        service.simple_agent._agent = MagicMock()
        service.simple_agent._agent.messages = [
            {"role": "user", "content": [{"text": "Test"}]}
        ]
        
        history = service.get_conversation_history("simple")
        assert len(history) == 1
    
    def test_get_conversation_history_rag(self):
        """Test get_conversation_history for RAG agent."""
        service = CloudLLMService(knowledge_base_id="test-kb-id")
        
        # Mock RAG agent
        service.rag_agent._agent = MagicMock()
        service.rag_agent._agent.messages = [
            {"role": "user", "content": [{"text": "RAG Test"}]},
            {"role": "assistant", "content": [{"text": "RAG Response"}]},
        ]
        
        history = service.get_conversation_history("rag")
        assert len(history) == 2
    
    def test_clear_conversation_clears_both_agents(self):
        """Test clear_conversation clears both simple and RAG agents."""
        service = CloudLLMService(knowledge_base_id="test-kb-id")
        
        # Mock both agents
        service.simple_agent._agent = MagicMock()
        service.simple_agent._agent.messages = [{"role": "user", "content": []}]
        
        service.rag_agent._agent = MagicMock()
        service.rag_agent._agent.messages = [{"role": "user", "content": []}]
        
        # Clear
        service.clear_conversation()
        
        # Both should be cleared
        assert service.simple_agent._agent.messages == []
        assert service.rag_agent._agent.messages == []


class TestIntentClassifier:
    """Test IntentClassifier keyword-based classification."""
    
    def test_simple_intent_for_general_questions(self):
        """Test that general questions are classified as SIMPLE."""
        classifier = IntentClassifier()
        
        simple_queries = [
            "What is Python?",
            "How do I write a for loop?",
            "Explain async/await",
            "What time is it?",
        ]
        
        for query in simple_queries:
            intent = classifier.classify(query)
            assert intent == QueryIntent.SIMPLE, f"Expected SIMPLE for: {query}"
    
    def test_rag_intent_for_personal_references(self):
        """Test that personal/historical references are classified as RAG."""
        classifier = IntentClassifier()
        
        rag_queries = [
            "What was our previous decision?",
            "Show me the architecture document",
            "What did we discuss last time?",
            "How did we implement the API?",
            "What's in my notes about caching?",
        ]
        
        for query in rag_queries:
            intent = classifier.classify(query)
            assert intent == QueryIntent.RAG, f"Expected RAG for: {query}"
    
    def test_rag_keywords_detection(self):
        """Test specific RAG keywords are detected."""
        classifier = IntentClassifier()
        
        keyword_queries = {
            "previous": "What was the previous approach?",
            "document": "Find the document about auth",
            "architecture": "Show me the architecture",
            "codebase": "Search the codebase for this",
            "remember": "Do you remember what we said?",
        }
        
        for keyword, query in keyword_queries.items():
            intent = classifier.classify(query)
            assert intent == QueryIntent.RAG, f"Keyword '{keyword}' not detected in: {query}"


class TestConversationContext:
    """Test ConversationContext data class."""
    
    def test_empty_context_string(self):
        """Test to_context_string with empty transcript."""
        context = ConversationContext(transcript=[], user_query="Hello")
        
        assert context.to_context_string() == ""
    
    def test_context_string_with_entries(self):
        """Test to_context_string formats transcript correctly."""
        context = ConversationContext(
            transcript=[
                TranscriptContext(text="Hello there", source="system", timestamp=1.0),
                TranscriptContext(text="Hi, how are you?", source="microphone", timestamp=2.0),
            ],
            user_query="What did we discuss?"
        )
        
        context_str = context.to_context_string()
        
        assert "🔊 System" in context_str
        assert "🎤 You" in context_str
        assert "Hello there" in context_str
        assert "Hi, how are you?" in context_str


class TestCloudLLMResponse:
    """Test CloudLLMResponse data class."""
    
    def test_response_creation(self):
        """Test CloudLLMResponse creation with all fields."""
        response = CloudLLMResponse(
            content="This is the response",
            model="claude-3",
            sources=["doc1.md", "doc2.md"],
            tokens_used=150,
            used_rag=True
        )
        
        assert response.content == "This is the response"
        assert response.model == "claude-3"
        assert len(response.sources) == 2
        assert response.tokens_used == 150
        assert response.used_rag is True
    
    def test_response_defaults(self):
        """Test CloudLLMResponse default values."""
        response = CloudLLMResponse(
            content="Response",
            model="claude-3",
            sources=[]
        )
        
        assert response.tokens_used == 0
        assert response.used_rag is False



# ============================================================================
# Cloud LLM Agent Verification Tests
# ============================================================================


class TestSimpleCloudAgentQuery:
    """
    Test SimpleCloudAgent with transcript-only queries.
    """
    
    @pytest.mark.asyncio
    async def test_query_with_transcript_context(self):
        """Test SimpleCloudAgent query with transcript context."""
        agent = SimpleCloudAgent()
        
        # Mock the internal agent
        mock_strands_agent = MagicMock()
        mock_strands_agent.return_value = "This is a summary of the conversation."
        mock_strands_agent.messages = []
        agent._agent = mock_strands_agent
        agent._initialized = True
        
        context = ConversationContext(
            transcript=[
                TranscriptContext(text="Let's discuss the API design", source="system", timestamp=1.0),
                TranscriptContext(text="I think we should use REST", source="microphone", timestamp=2.0),
            ],
            user_query="Summarize what we discussed"
        )
        
        response = await agent.query(context)
        
        assert isinstance(response, CloudLLMResponse)
        assert response.content == "This is a summary of the conversation."
        assert response.used_rag is False
        assert response.sources == []
        mock_strands_agent.assert_called_once()
    
    @pytest.mark.asyncio
    async def test_query_without_transcript(self):
        """Test SimpleCloudAgent query without transcript context."""
        agent = SimpleCloudAgent()
        
        mock_strands_agent = MagicMock()
        mock_strands_agent.return_value = "Python is a programming language."
        mock_strands_agent.messages = []
        agent._agent = mock_strands_agent
        agent._initialized = True
        
        context = ConversationContext(
            transcript=[],
            user_query="What is Python?"
        )
        
        response = await agent.query(context)
        
        assert response.content == "Python is a programming language."
        assert response.used_rag is False
    
    @pytest.mark.asyncio
    async def test_query_builds_correct_prompt(self):
        """Test that query builds prompt with transcript context."""
        agent = SimpleCloudAgent()
        
        captured_prompt = None
        def capture_prompt(prompt):
            nonlocal captured_prompt
            captured_prompt = prompt
            return "Response"
        
        mock_strands_agent = MagicMock(side_effect=capture_prompt)
        mock_strands_agent.messages = []
        agent._agent = mock_strands_agent
        agent._initialized = True
        
        context = ConversationContext(
            transcript=[
                TranscriptContext(text="Hello world", source="system", timestamp=1.0),
            ],
            user_query="What was said?"
        )
        
        await agent.query(context)
        
        assert captured_prompt is not None
        assert "Hello world" in captured_prompt
        assert "What was said?" in captured_prompt
        assert "🔊 System" in captured_prompt
    
    @pytest.mark.asyncio
    async def test_query_estimates_tokens(self):
        """Test that query estimates token usage."""
        agent = SimpleCloudAgent()
        
        mock_strands_agent = MagicMock()
        mock_strands_agent.return_value = "Short response"
        mock_strands_agent.messages = []
        agent._agent = mock_strands_agent
        agent._initialized = True
        
        context = ConversationContext(
            transcript=[],
            user_query="Hello"
        )
        
        response = await agent.query(context)
        
        assert response.tokens_used > 0


class TestRAGCloudAgentQuery:
    """
    Test RAGCloudAgent with KB retrieval.
    
    Checkpoint 8 requirement: Test RAGCloudAgent with KB retrieval
    """
    
    @pytest.mark.asyncio
    async def test_query_with_kb_retrieval(self):
        """Test RAGCloudAgent query retrieves from KB and includes sources."""
        agent = RAGCloudAgent(knowledge_base_id="test-kb-123")
        
        # Mock the internal agent
        mock_strands_agent = MagicMock()
        mock_strands_agent.return_value = "Based on your architecture document, you should use microservices."
        mock_strands_agent.messages = []
        agent._agent = mock_strands_agent
        agent._initialized = True
        
        # Mock KB retrieval
        mock_retrieval_result = {
            "retrievalResults": [
                {
                    "content": {"text": "Architecture decision: Use microservices pattern"},
                    "location": {"s3Location": {"uri": "s3://bucket/architecture.md"}},
                    "score": 0.95
                }
            ]
        }
        
        with patch.object(agent, '_retrieve_from_kb', new_callable=AsyncMock) as mock_retrieve:
            mock_retrieve.return_value = mock_retrieval_result
            
            context = ConversationContext(
                transcript=[],
                user_query="What was our architecture decision?"
            )
            
            response = await agent.query(context)
            
            assert isinstance(response, CloudLLMResponse)
            assert response.used_rag is True
            assert "architecture.md" in response.sources
            mock_retrieve.assert_called_once_with("What was our architecture decision?")
    
    @pytest.mark.asyncio
    async def test_query_graceful_fallback_no_kb_results(self):
        """Test RAGCloudAgent proceeds gracefully when KB returns no results."""
        agent = RAGCloudAgent(knowledge_base_id="test-kb-123")
        
        mock_strands_agent = MagicMock()
        mock_strands_agent.return_value = "I don't have specific information about that."
        mock_strands_agent.messages = []
        agent._agent = mock_strands_agent
        agent._initialized = True
        
        with patch.object(agent, '_retrieve_from_kb', new_callable=AsyncMock) as mock_retrieve:
            mock_retrieve.return_value = None  # No KB results
            
            context = ConversationContext(
                transcript=[
                    TranscriptContext(text="Let's talk about something new", source="microphone", timestamp=1.0),
                ],
                user_query="What about the new feature?"
            )
            
            response = await agent.query(context)
            
            assert response.content == "I don't have specific information about that."
            assert response.sources == []
            assert response.used_rag is True  # Still marked as RAG attempt
    
    @pytest.mark.asyncio
    async def test_query_includes_transcript_and_kb_context(self):
        """Test that query includes both transcript and KB documents in context."""
        agent = RAGCloudAgent(knowledge_base_id="test-kb-123")
        
        captured_context = None
        def capture_context(ctx):
            nonlocal captured_context
            captured_context = ctx
            return "Response with context"
        
        mock_strands_agent = MagicMock(side_effect=capture_context)
        mock_strands_agent.messages = []
        agent._agent = mock_strands_agent
        agent._initialized = True
        
        mock_retrieval_result = {
            "retrievalResults": [
                {
                    "content": {"text": "Document content here"},
                    "location": {"s3Location": {"uri": "s3://bucket/doc.md"}},
                    "score": 0.85
                }
            ]
        }
        
        with patch.object(agent, '_retrieve_from_kb', new_callable=AsyncMock) as mock_retrieve:
            mock_retrieve.return_value = mock_retrieval_result
            
            context = ConversationContext(
                transcript=[
                    TranscriptContext(text="Previous discussion", source="system", timestamp=1.0),
                ],
                user_query="Tell me about the document"
            )
            
            await agent.query(context)
            
            assert captured_context is not None
            assert "Previous discussion" in captured_context
            assert "Document content here" in captured_context
            assert "doc.md" in captured_context
    
    @pytest.mark.asyncio
    async def test_extract_sources_from_retrieval(self):
        """Test source extraction from retrieval results."""
        agent = RAGCloudAgent(knowledge_base_id="test-kb-123")
        
        retrieval_result = {
            "retrievalResults": [
                {
                    "content": {"text": "Content 1"},
                    "location": {"s3Location": {"uri": "s3://bucket/doc1.md"}},
                    "score": 0.9
                },
                {
                    "content": {"text": "Content 2"},
                    "location": {"s3Location": {"uri": "s3://bucket/doc2.md"}},
                    "score": 0.8
                }
            ]
        }
        
        sources = agent._extract_sources(retrieval_result)
        
        assert len(sources) == 2
        assert "doc1.md" in sources
        assert "doc2.md" in sources
    
    @pytest.mark.asyncio
    async def test_extract_sources_empty_result(self):
        """Test source extraction with empty retrieval result."""
        agent = RAGCloudAgent(knowledge_base_id="test-kb-123")
        
        sources = agent._extract_sources(None)
        assert sources == []
        
        sources = agent._extract_sources({"retrievalResults": []})
        assert sources == []


class TestCloudLLMServiceRouting:
    """
    Test CloudLLMService intent classification routing.
    
    Checkpoint 8 requirement: Test intent classification routing
    """
    
    @pytest.mark.asyncio
    async def test_routes_simple_query_to_simple_agent(self):
        """Test that simple queries are routed to SimpleCloudAgent."""
        service = CloudLLMService(knowledge_base_id="test-kb-123")
        
        # Mock simple agent
        mock_response = CloudLLMResponse(
            content="Python is great",
            model="claude-3",
            sources=[],
            used_rag=False
        )
        service.simple_agent.query = AsyncMock(return_value=mock_response)
        service.rag_agent.query = AsyncMock()
        
        context = ConversationContext(
            transcript=[],
            user_query="What is Python?"  # Simple query, no RAG keywords
        )
        
        response = await service.query(context)
        
        assert response.used_rag is False
        service.simple_agent.query.assert_called_once()
        service.rag_agent.query.assert_not_called()
    
    @pytest.mark.asyncio
    async def test_routes_rag_query_to_rag_agent(self):
        """Test that RAG queries are routed to RAGCloudAgent."""
        service = CloudLLMService(knowledge_base_id="test-kb-123")
        
        # Mock RAG agent
        mock_response = CloudLLMResponse(
            content="Based on your documents...",
            model="claude-3",
            sources=["architecture.md"],
            used_rag=True
        )
        service.simple_agent.query = AsyncMock()
        service.rag_agent.query = AsyncMock(return_value=mock_response)
        
        context = ConversationContext(
            transcript=[],
            user_query="What was our previous architecture decision?"  # Contains RAG keywords
        )
        
        response = await service.query(context)
        
        assert response.used_rag is True
        assert "architecture.md" in response.sources
        service.rag_agent.query.assert_called_once()
        service.simple_agent.query.assert_not_called()
    
    @pytest.mark.asyncio
    async def test_force_rag_overrides_classification(self):
        """Test that force_rag=True always uses RAG agent."""
        service = CloudLLMService(knowledge_base_id="test-kb-123")
        
        mock_response = CloudLLMResponse(
            content="RAG response",
            model="claude-3",
            sources=[],
            used_rag=True
        )
        service.simple_agent.query = AsyncMock()
        service.rag_agent.query = AsyncMock(return_value=mock_response)
        
        context = ConversationContext(
            transcript=[],
            user_query="What is Python?"  # Would normally be SIMPLE
        )
        
        response = await service.query(context, force_rag=True)
        
        assert response.used_rag is True
        service.rag_agent.query.assert_called_once()
        service.simple_agent.query.assert_not_called()
    
    @pytest.mark.asyncio
    async def test_fallback_to_simple_on_rag_failure(self):
        """Test fallback to simple agent when RAG agent fails."""
        service = CloudLLMService(knowledge_base_id="test-kb-123")
        
        # RAG agent fails
        service.rag_agent.query = AsyncMock(side_effect=CloudLLMError("KB unavailable"))
        
        # Simple agent succeeds
        mock_response = CloudLLMResponse(
            content="Fallback response",
            model="claude-3",
            sources=[],
            used_rag=False
        )
        service.simple_agent.query = AsyncMock(return_value=mock_response)
        
        context = ConversationContext(
            transcript=[],
            user_query="What was our previous decision?"  # RAG query
        )
        
        response = await service.query(context)
        
        # Should fallback to simple agent
        assert response.content == "Fallback response"
        service.rag_agent.query.assert_called_once()
        service.simple_agent.query.assert_called_once()


class TestIntentClassifierExtended:
    """
    Extended tests for IntentClassifier.
    
    Checkpoint 8 requirement: Test intent classification routing
    """
    
    def test_all_rag_keywords_detected(self):
        """Test that all defined RAG keywords are properly detected."""
        classifier = IntentClassifier()
        
        # Test each keyword category
        test_cases = [
            # Personal/historical references
            ("What was the previous approach?", QueryIntent.RAG),
            ("Last time we discussed this", QueryIntent.RAG),
            ("Before we had a different design", QueryIntent.RAG),
            ("Earlier we decided on REST", QueryIntent.RAG),
            
            # Possessive references
            ("What's in our codebase?", QueryIntent.RAG),
            ("Show me my documents", QueryIntent.RAG),
            ("What did we implement?", QueryIntent.RAG),
            
            # Document references
            ("Find the document about auth", QueryIntent.RAG),
            ("Check my notes on caching", QueryIntent.RAG),
            
            # Architecture references
            ("What's the architecture?", QueryIntent.RAG),
            ("Show me the design decisions", QueryIntent.RAG),
            
            # Memory references
            ("Do you remember what we said?", QueryIntent.RAG),
            ("Recall the discussion", QueryIntent.RAG),
        ]
        
        for query, expected_intent in test_cases:
            intent = classifier.classify(query)
            assert intent == expected_intent, f"Failed for query: {query}"
    
    def test_case_insensitive_matching(self):
        """Test that keyword matching is case-insensitive."""
        classifier = IntentClassifier()
        
        queries = [
            "What was the PREVIOUS decision?",
            "Show me OUR architecture",
            "Check the DOCUMENT",
        ]
        
        for query in queries:
            intent = classifier.classify(query)
            assert intent == QueryIntent.RAG, f"Case-insensitive match failed for: {query}"
    
    def test_simple_queries_not_misclassified(self):
        """Test that simple queries are not misclassified as RAG."""
        classifier = IntentClassifier()
        
        simple_queries = [
            "What is a REST API?",
            "How do I write a for loop?",
            "Explain async/await in Python",
            "What are the benefits of microservices?",
            "How does HTTP work?",
        ]
        
        for query in simple_queries:
            intent = classifier.classify(query)
            assert intent == QueryIntent.SIMPLE, f"Misclassified as RAG: {query}"
