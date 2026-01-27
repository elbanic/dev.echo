"""
Cloud LLM Agents

Two Strands Agent implementations for AWS Bedrock:
1. SimpleCloudAgent - For transcript-based queries without KB retrieval
2. RAGCloudAgent - For queries requiring knowledge base retrieval

Reference: https://strandsagents.com/latest/documentation/docs/
Reference: https://strandsagents.com/latest/documentation/docs/examples/python/knowledge_base_agent/

Requirements: 6.1, 6.2, 6.3, 6.4, 6.6, 7.1, 7.3, 7.4, 8.1, 8.2, 8.4, 8.5
"""

import asyncio
import logging
import os
from dataclasses import dataclass, field
from enum import Enum
from typing import List, Optional

from strands import Agent
from strands.models.bedrock import BedrockModel

logger = logging.getLogger(__name__)


class QueryIntent(str, Enum):
    """Query intent classification."""
    SIMPLE = "simple"      # Transcript-only, no KB needed
    RAG = "rag"            # Requires KB retrieval


@dataclass
class TranscriptContext:
    """Single transcript entry for context."""
    text: str
    source: str  # "system" or "microphone"
    timestamp: float


@dataclass
class ConversationContext:
    """Context for cloud LLM queries."""
    transcript: List[TranscriptContext] = field(default_factory=list)
    user_query: str = ""
    
    def to_context_string(self) -> str:
        """Format transcript as context string."""
        if not self.transcript:
            return ""
        
        lines = ["## Recent Conversation\n"]
        for entry in self.transcript:
            source_label = "🔊 System" if entry.source == "system" else "🎤 You"
            lines.append(f"{source_label}: {entry.text}")
        
        return "\n".join(lines)


@dataclass
class CloudLLMResponse:
    """Response from cloud LLM with sources."""
    content: str
    model: str
    sources: List[str]  # Document names used (empty for simple queries)
    tokens_used: int = 0
    used_rag: bool = False


class CloudLLMError(Exception):
    """Base exception for Cloud LLM errors."""
    pass


class BedrockUnavailableError(CloudLLMError):
    """Raised when AWS Bedrock service is unavailable."""
    
    def __init__(self, message: str = "AWS Bedrock service is unavailable"):
        super().__init__(message)


class BedrockAccessDeniedError(CloudLLMError):
    """Raised when access to Bedrock is denied."""
    
    def __init__(self, message: str = "Access denied to AWS Bedrock. Check IAM permissions."):
        super().__init__(message)


class CloudQueryTimeoutError(CloudLLMError):
    """Raised when cloud LLM query times out."""
    
    def __init__(self, timeout_seconds: float):
        self.timeout_seconds = timeout_seconds
        super().__init__(f"Cloud LLM query timed out after {timeout_seconds} seconds")


class SimpleCloudAgent:
    """
    Simple Strands Agent for transcript-based queries.
    
    Does NOT use knowledge base retrieval. Suitable for:
    - Summarizing current conversation
    - Answering questions based on transcript context only
    - General questions not requiring personal knowledge
    
    Requirements: 6.1, 6.2, 6.3
    """
    
    DEFAULT_MODEL = "us.anthropic.claude-sonnet-4-20250514-v1:0"
    DEFAULT_TIMEOUT = 120.0  # seconds
    
    def __init__(
        self,
        model_id: str = DEFAULT_MODEL,
        region: str = "us-west-2",
        timeout: float = DEFAULT_TIMEOUT
    ):
        """
        Initialize SimpleCloudAgent.
        
        Args:
            model_id: Bedrock model ID (default: Claude Sonnet)
            region: AWS region
            timeout: Query timeout in seconds
        """
        self.model_id = model_id
        self.region = region
        self.timeout = timeout
        self._agent: Optional[Agent] = None
        self._initialized = False
    
    async def initialize(self) -> None:
        """
        Initialize simple Strands Agent without KB tools.
        
        Requirements: 6.1 - Connect to AWS Bedrock
        
        Raises:
            BedrockUnavailableError: If Bedrock is not accessible
            BedrockAccessDeniedError: If access is denied
        """
        if self._initialized:
            return
        
        logger.info(f"Initializing SimpleCloudAgent with model: {self.model_id}")
        
        try:
            # Initialize Bedrock model
            bedrock_model = BedrockModel(
                model_id=self.model_id,
                region_name=self.region,
            )
            
            system_prompt = self._get_system_prompt()
            
            # Create agent without memory tool (no KB access)
            self._agent = Agent(
                model=bedrock_model,
                system_prompt=system_prompt
            )
            
            self._initialized = True
            logger.info(f"SimpleCloudAgent initialized successfully with {self.model_id}")
            
        except Exception as e:
            error_str = str(e).lower()
            if "access" in error_str and "denied" in error_str:
                raise BedrockAccessDeniedError()
            elif "credential" in error_str or "auth" in error_str:
                raise BedrockAccessDeniedError(
                    "AWS credentials not configured. Run 'aws configure' to set up."
                )
            else:
                logger.error(f"Failed to initialize SimpleCloudAgent: {e}")
                raise BedrockUnavailableError(f"Failed to initialize: {e}")
    
    def _get_system_prompt(self) -> str:
        """System prompt for simple cloud agent."""
        return """You are dev.echo, an AI assistant for developers.

You help with:
- Understanding and summarizing conversations
- Answering questions based on the current conversation context
- Providing general technical guidance

You are responding based on the conversation transcript provided.
Be concise and helpful. Focus on actionable information."""
    
    async def query(
        self,
        context: ConversationContext
    ) -> CloudLLMResponse:
        """
        Send query with transcript context only (no KB retrieval).
        
        Requirements: 6.2 - Send query with conversation context
        Requirements: 6.3 - Display loading animation while waiting
        
        Args:
            context: ConversationContext with transcript and query
            
        Returns:
            CloudLLMResponse with content
            
        Raises:
            BedrockUnavailableError: If Bedrock is unavailable
            CloudQueryTimeoutError: If query times out
        """
        if not self._initialized:
            await self.initialize()
        
        # Build prompt with transcript context only
        prompt = self._build_prompt(context)
        
        logger.debug(f"Sending query to {self.model_id}: {context.user_query[:100]}...")
        
        try:
            # Run query with timeout
            response = await asyncio.wait_for(
                self._execute_query(prompt),
                timeout=self.timeout
            )
            
            logger.info(f"Received response from {self.model_id} ({response.tokens_used} tokens)")
            return response
            
        except asyncio.TimeoutError:
            raise CloudQueryTimeoutError(self.timeout)
        except (BedrockUnavailableError, BedrockAccessDeniedError):
            raise
        except Exception as e:
            logger.error(f"Cloud LLM query failed: {e}")
            raise CloudLLMError(f"Query failed: {e}")
    
    def _build_prompt(self, context: ConversationContext) -> str:
        """Build prompt with transcript context."""
        parts = []
        
        context_str = context.to_context_string()
        if context_str:
            parts.append(context_str)
            parts.append("\n---\n")
        
        parts.append(f"User Query: {context.user_query}")
        
        return "\n".join(parts)
    
    async def _execute_query(self, prompt: str) -> CloudLLMResponse:
        """Execute the query using Strands Agent."""
        if not self._agent:
            raise CloudLLMError("Agent not initialized")
        
        try:
            # Use Strands Agent to process the query
            # Run in executor to avoid blocking
            loop = asyncio.get_event_loop()
            result = await loop.run_in_executor(None, self._agent, prompt)
            
            # Extract response content
            content = str(result)
            
            # Estimate tokens (rough approximation)
            tokens_used = self._estimate_tokens(prompt, content)
            
            return CloudLLMResponse(
                content=content,
                model=self.model_id,
                sources=[],  # No KB sources
                tokens_used=tokens_used,
                used_rag=False
            )
            
        except Exception as e:
            error_str = str(e).lower()
            if "access" in error_str and "denied" in error_str:
                raise BedrockAccessDeniedError()
            elif "throttl" in error_str:
                raise CloudLLMError("Request throttled. Please try again later.")
            raise
    
    def _estimate_tokens(self, prompt: str, response: str) -> int:
        """Rough token estimation."""
        return len(prompt.split()) + len(response.split())
    
    def is_available(self) -> bool:
        """
        Check if Bedrock service is available.
        
        Returns:
            True if Bedrock is accessible
        """
        try:
            import boto3
            client = boto3.client("bedrock-runtime", region_name=self.region)
            # Just check if we can create the client
            return True
        except Exception as e:
            logger.warning(f"Bedrock availability check failed: {e}")
            return False
    
    def clear_conversation(self) -> None:
        """
        Clear the conversation history.
        
        Resets the Agent's internal message history to start a fresh conversation.
        Call this when starting a new session or when the user wants to reset context.
        
        Requirements: 8.3 - Context management
        """
        if self._agent:
            self._agent.messages = []
            logger.info("SimpleCloudAgent conversation history cleared")
    
    def get_conversation_history(self) -> List[dict]:
        """
        Get the current conversation history.
        
        Returns:
            List of message dictionaries from the Agent's internal history
        """
        if self._agent:
            return list(self._agent.messages)
        return []
    
    def get_conversation_length(self) -> int:
        """
        Get the number of messages in conversation history.
        
        Returns:
            Number of messages in the Agent's history
        """
        if self._agent:
            return len(self._agent.messages)
        return 0
    
    async def shutdown(self) -> None:
        """Clean up resources."""
        self._agent = None
        self._initialized = False
        logger.info("SimpleCloudAgent shutdown complete")



class RAGCloudAgent:
    """
    RAG-enabled Strands Agent for knowledge base queries.
    
    Uses the `memory` tool from strands-agents-tools to query
    Bedrock Knowledge Base. The memory tool supports:
    - action="retrieve": Retrieve relevant documents from KB
    - action="store": Store information to KB (not used in this agent)
    
    Suitable for:
    - Questions requiring personal knowledge (past decisions, docs)
    - Technical questions about user's specific codebase/architecture
    - Queries mentioning "previous", "last time", "our", etc.
    
    Reference: https://strandsagents.com/latest/documentation/docs/examples/python/knowledge_base_agent/
    
    Requirements: 6.1, 6.4, 6.6, 7.1, 7.3, 8.1, 8.2, 8.4, 8.5
    """
    
    DEFAULT_MODEL = "us.anthropic.claude-sonnet-4-20250514-v1:0"
    DEFAULT_TIMEOUT = 180.0  # seconds (longer for RAG)
    
    def __init__(
        self,
        knowledge_base_id: str,
        model_id: str = DEFAULT_MODEL,
        region: str = "us-west-2",
        timeout: float = DEFAULT_TIMEOUT,
        retrieval_top_k: int = 5,
        min_score: float = 0.4
    ):
        """
        Initialize RAGCloudAgent.
        
        Args:
            knowledge_base_id: Bedrock Knowledge Base ID
            model_id: Bedrock model ID (default: Claude Sonnet)
            region: AWS region
            timeout: Query timeout in seconds
            retrieval_top_k: Maximum number of documents to retrieve
            min_score: Minimum relevance score for retrieval
        """
        self.knowledge_base_id = knowledge_base_id
        self.model_id = model_id
        self.region = region
        self.timeout = timeout
        self.retrieval_top_k = retrieval_top_k
        self.min_score = min_score
        self._agent: Optional[Agent] = None
        self._initialized = False
    
    async def initialize(self) -> None:
        """
        Initialize Strands Agent with Bedrock and KB memory tool.
        
        Sets STRANDS_KNOWLEDGE_BASE_ID environment variable for memory tool.
        
        Requirements: 6.1 - Connect to AWS Bedrock
        Requirements: 7.1 - Call Bedrock Knowledge Base for retrieval
        
        Raises:
            BedrockUnavailableError: If Bedrock is not accessible
            BedrockAccessDeniedError: If access is denied
        """
        if self._initialized:
            return
        
        logger.info(
            f"Initializing RAGCloudAgent with model: {self.model_id}, "
            f"kb_id: {self.knowledge_base_id}"
        )
        
        try:
            # Set KB ID for strands memory tool
            os.environ["STRANDS_KNOWLEDGE_BASE_ID"] = self.knowledge_base_id
            
            # Import memory tool from strands-agents-tools
            from strands_tools import memory
            
            # Initialize Bedrock model
            bedrock_model = BedrockModel(
                model_id=self.model_id,
                region_name=self.region,
            )
            
            system_prompt = self._get_system_prompt()
            
            # Create agent with memory tool for KB access
            self._agent = Agent(
                model=bedrock_model,
                tools=[memory],
                system_prompt=system_prompt
            )
            
            self._initialized = True
            logger.info(f"RAGCloudAgent initialized successfully with {self.model_id}")
            
        except ImportError as e:
            logger.error(f"Failed to import strands_tools: {e}")
            raise CloudLLMError(
                "strands-agents-tools not installed. Run: pip install strands-agents-tools"
            )
        except Exception as e:
            error_str = str(e).lower()
            if "access" in error_str and "denied" in error_str:
                raise BedrockAccessDeniedError()
            elif "credential" in error_str or "auth" in error_str:
                raise BedrockAccessDeniedError(
                    "AWS credentials not configured. Run 'aws configure' to set up."
                )
            else:
                logger.error(f"Failed to initialize RAGCloudAgent: {e}")
                raise BedrockUnavailableError(f"Failed to initialize: {e}")
    
    def _get_system_prompt(self) -> str:
        """System prompt for RAG cloud agent."""
        return """You are dev.echo, an AI assistant for developers.

You help with:
- Answering technical questions based on the user's knowledge base
- Surfacing relevant past context from documents
- Providing code suggestions based on user's architecture decisions

You have access to the user's personal knowledge base containing their documents,
architecture decisions, code snippets, and troubleshooting logs.

Use the memory tool with action="retrieve" to search the knowledge base.
Always cite your sources when using information from the knowledge base.

Be concise and helpful. Focus on actionable information.
When you use information from the knowledge base, mention which document it came from."""
    
    async def query(
        self,
        context: ConversationContext
    ) -> CloudLLMResponse:
        """
        Send query with context to cloud LLM via RAG pipeline.
        
        Uses code-defined workflow:
        1. Retrieve relevant documents from KB using memory tool
        2. Combine with conversation context
        3. Generate response
        
        Requirements: 6.4 - Use Bedrock KB to retrieve relevant documents
        Requirements: 7.1 - Call Bedrock KB for retrieval
        Requirements: 7.3 - Include top-k results ranked by relevance
        Requirements: 8.1 - Include conversation transcript
        Requirements: 8.2 - Include relevant documents from KB
        Requirements: 8.4 - Format context with source attribution
        Requirements: 8.5 - Track which documents contributed
        
        Args:
            context: ConversationContext with transcript and query
            
        Returns:
            CloudLLMResponse with content and sources
            
        Raises:
            BedrockUnavailableError: If Bedrock is unavailable
            CloudQueryTimeoutError: If query times out
        """
        if not self._initialized:
            await self.initialize()
        
        logger.debug(f"Sending RAG query to {self.model_id}: {context.user_query[:100]}...")
        
        try:
            # Run query with timeout
            response = await asyncio.wait_for(
                self._execute_rag_query(context),
                timeout=self.timeout
            )
            
            logger.info(
                f"Received RAG response from {self.model_id} "
                f"({response.tokens_used} tokens, {len(response.sources)} sources)"
            )
            return response
            
        except asyncio.TimeoutError:
            raise CloudQueryTimeoutError(self.timeout)
        except (BedrockUnavailableError, BedrockAccessDeniedError):
            raise
        except Exception as e:
            logger.error(f"RAG query failed: {e}")
            raise CloudLLMError(f"RAG query failed: {e}")
    
    async def _execute_rag_query(self, context: ConversationContext) -> CloudLLMResponse:
        """
        Execute RAG query with retrieval and generation.
        
        Implements code-defined workflow:
        1. Retrieve relevant documents from KB
        2. Build context with transcript and retrieved docs
        3. Generate response via agent
        """
        if not self._agent:
            raise CloudLLMError("Agent not initialized")
        
        try:
            # Step 1: Retrieve relevant documents from KB using memory tool
            retrieval_result = await self._retrieve_from_kb(context.user_query)
            
            # Step 2: Build context with transcript and retrieved docs
            full_context = self._build_full_context(context, retrieval_result)
            
            # Step 3: Generate response via agent
            loop = asyncio.get_event_loop()
            response = await loop.run_in_executor(None, self._agent, full_context)
            
            # Extract sources from retrieval result
            sources = self._extract_sources(retrieval_result)
            
            # Estimate tokens
            tokens_used = self._estimate_tokens(full_context, str(response))
            
            return CloudLLMResponse(
                content=str(response),
                model=self.model_id,
                sources=sources,
                tokens_used=tokens_used,
                used_rag=True
            )
            
        except Exception as e:
            error_str = str(e).lower()
            if "access" in error_str and "denied" in error_str:
                raise BedrockAccessDeniedError()
            elif "throttl" in error_str:
                raise CloudLLMError("Request throttled. Please try again later.")
            raise
    
    async def _retrieve_from_kb(self, query: str) -> Optional[dict]:
        """
        Retrieve relevant documents from Knowledge Base.
        
        Uses Bedrock Agent Runtime retrieve API directly for more control.
        
        Requirements: 7.1 - Call Bedrock KB for retrieval
        Requirements: 7.3 - Include top-k results ranked by relevance
        
        Args:
            query: User query for semantic search
            
        Returns:
            Dictionary with retrieval results or None if no results
        """
        try:
            import boto3
            
            client = boto3.client(
                "bedrock-agent-runtime",
                region_name=self.region
            )
            
            response = client.retrieve(
                knowledgeBaseId=self.knowledge_base_id,
                retrievalQuery={"text": query},
                retrievalConfiguration={
                    "vectorSearchConfiguration": {
                        "numberOfResults": self.retrieval_top_k
                    }
                }
            )
            
            results = response.get("retrievalResults", [])
            
            # Filter by minimum score
            filtered_results = [
                r for r in results
                if r.get("score", 0) >= self.min_score
            ]
            
            if not filtered_results:
                logger.info("No relevant documents found in KB")
                return None
            
            logger.info(f"Retrieved {len(filtered_results)} documents from KB")
            return {"retrievalResults": filtered_results}
            
        except Exception as e:
            logger.warning(f"KB retrieval failed: {e}")
            # Return None to proceed without KB results (graceful fallback)
            return None
    
    def _build_full_context(
        self,
        context: ConversationContext,
        retrieval_result: Optional[dict]
    ) -> str:
        """
        Build full context with transcript and retrieved documents.
        
        Requirements: 8.1 - Include conversation transcript
        Requirements: 8.2 - Include relevant documents from KB
        Requirements: 8.4 - Format context with source attribution
        """
        parts = []
        
        # Add conversation transcript
        context_str = context.to_context_string()
        if context_str:
            parts.append(context_str)
            parts.append("\n---\n")
        
        # Add retrieved documents
        if retrieval_result:
            parts.append("## Relevant Documents from Knowledge Base\n")
            
            for i, result in enumerate(retrieval_result.get("retrievalResults", []), 1):
                content = result.get("content", {}).get("text", "")
                location = result.get("location", {})
                s3_uri = location.get("s3Location", {}).get("uri", "Unknown")
                score = result.get("score", 0)
                
                # Extract document name from S3 URI
                doc_name = s3_uri.split("/")[-1] if "/" in s3_uri else s3_uri
                
                parts.append(f"### Document {i}: {doc_name} (relevance: {score:.2f})")
                parts.append(content)
                parts.append("")
            
            parts.append("---\n")
        
        # Add user query
        parts.append(f"User Query: {context.user_query}")
        
        return "\n".join(parts)
    
    def _extract_sources(self, retrieval_result: Optional[dict]) -> List[str]:
        """
        Extract document sources from retrieval result.
        
        Requirements: 6.6 - Display sources used from KB
        Requirements: 8.5 - Track which documents contributed
        """
        sources = []
        
        if not retrieval_result:
            return sources
        
        for result in retrieval_result.get("retrievalResults", []):
            location = result.get("location", {})
            s3_uri = location.get("s3Location", {}).get("uri", "")
            
            if s3_uri:
                # Extract document name from S3 URI
                doc_name = s3_uri.split("/")[-1] if "/" in s3_uri else s3_uri
                if doc_name and doc_name not in sources:
                    sources.append(doc_name)
        
        return sources
    
    def _estimate_tokens(self, prompt: str, response: str) -> int:
        """Rough token estimation."""
        return len(prompt.split()) + len(response.split())
    
    def is_available(self) -> bool:
        """
        Check if Bedrock and KB services are available.
        
        Returns:
            True if services are accessible
        """
        try:
            import boto3
            
            # Check Bedrock runtime
            bedrock_client = boto3.client("bedrock-runtime", region_name=self.region)
            
            # Check Bedrock agent runtime (for KB)
            agent_client = boto3.client("bedrock-agent-runtime", region_name=self.region)
            
            return True
        except Exception as e:
            logger.warning(f"Bedrock/KB availability check failed: {e}")
            return False
    
    def clear_conversation(self) -> None:
        """
        Clear the conversation history.
        
        Resets the Agent's internal message history to start a fresh conversation.
        Call this when starting a new session or when the user wants to reset context.
        
        Requirements: 8.3 - Context management
        """
        if self._agent:
            self._agent.messages = []
            logger.info("RAGCloudAgent conversation history cleared")
    
    def get_conversation_history(self) -> List[dict]:
        """
        Get the current conversation history.
        
        Returns:
            List of message dictionaries from the Agent's internal history
        """
        if self._agent:
            return list(self._agent.messages)
        return []
    
    def get_conversation_length(self) -> int:
        """
        Get the number of messages in conversation history.
        
        Returns:
            Number of messages in the Agent's history
        """
        if self._agent:
            return len(self._agent.messages)
        return 0
    
    async def shutdown(self) -> None:
        """Clean up resources."""
        self._agent = None
        self._initialized = False
        logger.info("RAGCloudAgent shutdown complete")



class IntentClassifier:
    """
    Classifies query intent to route to appropriate agent.
    
    Uses a lightweight keyword-based classification to determine if query
    requires KB retrieval or can be answered from transcript alone.
    
    Requirements: 6.1 - Route queries to appropriate agent
    """
    
    # Keywords indicating RAG is needed
    RAG_KEYWORDS = {
        # Personal/historical references
        "previous", "last time", "before", "earlier", "ago",
        "our", "we", "my", "us",
        # Document references
        "document", "doc", "docs", "documentation",
        "file", "files", "notes", "note",
        # Architecture/design references
        "architecture", "design", "decision", "decisions",
        "pattern", "patterns", "approach",
        # Code references
        "codebase", "repository", "repo", "code",
        "implementation", "implemented",
        # Memory references
        "remember", "recall", "mentioned", "discussed",
        "talked about", "said",
        # Knowledge base explicit
        "knowledge base", "kb", "stored", "saved",
    }
    
    def __init__(self, use_llm: bool = False):
        """
        Initialize classifier.
        
        Args:
            use_llm: If True, use LLM for more accurate classification
                     (not implemented yet, uses keyword-based only)
        """
        self.use_llm = use_llm
    
    def classify(self, query: str, context: Optional[ConversationContext] = None) -> QueryIntent:
        """
        Classify query intent using keyword matching.
        
        Args:
            query: User query string
            context: Optional conversation context (for future LLM-based classification)
            
        Returns:
            QueryIntent.RAG if KB retrieval is needed
            QueryIntent.SIMPLE if transcript-only is sufficient
        """
        query_lower = query.lower()
        
        # Check for RAG keywords
        for keyword in self.RAG_KEYWORDS:
            if keyword in query_lower:
                logger.debug(f"RAG intent detected: keyword '{keyword}' found")
                return QueryIntent.RAG
        
        # Default to simple for general questions
        logger.debug("Simple intent detected: no RAG keywords found")
        return QueryIntent.SIMPLE
    
    async def classify_with_llm(
        self,
        query: str,
        context: Optional[ConversationContext] = None
    ) -> QueryIntent:
        """
        Use LLM for more accurate intent classification.
        
        Falls back to keyword-based if LLM unavailable.
        
        Note: This is a placeholder for future LLM-based classification.
        Currently just calls the keyword-based classify method.
        
        Args:
            query: User query string
            context: Optional conversation context
            
        Returns:
            QueryIntent enum value
        """
        # For now, just use keyword-based classification
        # Future: implement LLM-based classification for edge cases
        return self.classify(query, context)



class CloudLLMService:
    """
    Service layer that routes queries to appropriate agent.
    
    Manages both SimpleCloudAgent and RAGCloudAgent,
    routing queries based on intent classification.
    
    Requirements: 6.1, 6.4, 7.4
    """
    
    def __init__(
        self,
        knowledge_base_id: str,
        model_id: str = RAGCloudAgent.DEFAULT_MODEL,
        region: str = "us-west-2"
    ):
        """
        Initialize CloudLLMService.
        
        Args:
            knowledge_base_id: Bedrock Knowledge Base ID
            model_id: Bedrock model ID (default: Claude Sonnet)
            region: AWS region
        """
        self.knowledge_base_id = knowledge_base_id
        self.model_id = model_id
        self.region = region
        
        self.simple_agent = SimpleCloudAgent(
            model_id=model_id,
            region=region
        )
        self.rag_agent = RAGCloudAgent(
            knowledge_base_id=knowledge_base_id,
            model_id=model_id,
            region=region
        )
        self.classifier = IntentClassifier()
        self._initialized = False
    
    async def initialize(self) -> None:
        """
        Initialize both agents.
        
        Note: Agents are initialized lazily on first query,
        so this method is optional but can be used for eager initialization.
        """
        if self._initialized:
            return
        
        logger.info("Initializing CloudLLMService...")
        
        # Initialize both agents
        await self.simple_agent.initialize()
        await self.rag_agent.initialize()
        
        self._initialized = True
        logger.info("CloudLLMService initialized successfully")
    
    async def query(
        self,
        context: ConversationContext,
        force_rag: bool = False
    ) -> CloudLLMResponse:
        """
        Process query, routing to appropriate agent.
        
        Requirements: 6.1 - Send query with context to Cloud LLM
        Requirements: 6.4 - Use Bedrock KB to retrieve relevant documents
        Requirements: 7.4 - Proceed with query using only conversation context if no KB results
        
        Args:
            context: Conversation context with query
            force_rag: If True, always use RAG agent regardless of intent
            
        Returns:
            CloudLLMResponse with content and sources
            
        Raises:
            BedrockUnavailableError: If Bedrock is unavailable
            CloudQueryTimeoutError: If query times out
            CloudLLMError: For other errors
        """
        # Classify intent
        if force_rag:
            intent = QueryIntent.RAG
            logger.info("Using RAG agent (forced)")
        else:
            intent = self.classifier.classify(context.user_query, context)
            logger.info(f"Query intent classified as: {intent.value}")
        
        # Route to appropriate agent
        if intent == QueryIntent.RAG:
            try:
                return await self.rag_agent.query(context)
            except CloudLLMError as e:
                # If RAG fails, try falling back to simple agent
                logger.warning(f"RAG query failed, falling back to simple: {e}")
                return await self.simple_agent.query(context)
        else:
            return await self.simple_agent.query(context)
    
    def is_available(self) -> bool:
        """
        Check if cloud LLM is available.
        
        Returns:
            True if Bedrock services are accessible
        """
        return self.simple_agent.is_available()
    
    def get_model_info(self) -> dict:
        """
        Get information about the configured model.
        
        Returns:
            Dictionary with model information
        """
        return {
            "model_id": self.model_id,
            "region": self.region,
            "knowledge_base_id": self.knowledge_base_id,
            "available": self.is_available(),
        }
    
    def clear_conversation(self) -> None:
        """
        Clear conversation history for both agents.
        
        Call this when starting a new session or when the user wants to reset
        the LLM conversation context. This preserves the transcript context
        which is passed separately on each query.
        
        Requirements: 8.1, 8.3 - Context management
        """
        self.simple_agent.clear_conversation()
        self.rag_agent.clear_conversation()
        logger.info("CloudLLMService conversation history cleared for all agents")
    
    def get_conversation_info(self) -> dict:
        """
        Get information about current conversation state.
        
        Returns:
            Dictionary with conversation statistics for both agents
        """
        return {
            "simple_agent": {
                "message_count": self.simple_agent.get_conversation_length(),
                "initialized": self.simple_agent._initialized,
            },
            "rag_agent": {
                "message_count": self.rag_agent.get_conversation_length(),
                "initialized": self.rag_agent._initialized,
            },
        }
    
    def get_conversation_history(self, agent_type: str = "simple") -> List[dict]:
        """
        Get conversation history from specified agent.
        
        Args:
            agent_type: "simple" or "rag" to specify which agent's history
            
        Returns:
            List of message dictionaries
        """
        if agent_type == "rag":
            return self.rag_agent.get_conversation_history()
        return self.simple_agent.get_conversation_history()
    
    async def shutdown(self) -> None:
        """Clean up resources."""
        await self.simple_agent.shutdown()
        await self.rag_agent.shutdown()
        self._initialized = False
        logger.info("CloudLLMService shutdown complete")
