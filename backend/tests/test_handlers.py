"""
Tests for Phase 2 IPC Handlers

Tests CloudLLMHandler, S3KBHandler, and KBSyncHandler.
"""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from pathlib import Path

from aws.handlers import CloudLLMHandler, S3KBHandler, KBSyncHandler
from aws.agents import (
    CloudLLMService,
    CloudLLMResponse,
    ConversationContext,
    TranscriptContext,
    CloudLLMError,
    BedrockUnavailableError,
    BedrockAccessDeniedError,
    CloudQueryTimeoutError,
)
from aws.s3_manager import (
    S3DocumentManager,
    S3Document,
    S3DocumentError,
    DocumentNotFoundError,
    DocumentExistsError,
    InvalidMarkdownError,
)
from aws.kb_service import (
    KnowledgeBaseService,
    SyncStatus,
    KBServiceError,
    KBNotFoundError,
    KBAccessDeniedError,
    KBSyncError,
)
from ipc.protocol import (
    CloudLLMQueryMessage,
    CloudLLMResponseMessage,
    CloudLLMErrorMessage,
    KBListRequestMessage,
    KBAddMessage,
    KBUpdateMessage,
    KBRemoveMessage,
    KBResponseMessage,
    KBErrorMessage,
    KBSyncStatusMessage,
)


class TestCloudLLMHandler:
    """Tests for CloudLLMHandler."""
    
    @pytest.fixture
    def mock_cloud_llm_service(self):
        """Create a mock CloudLLMService."""
        service = MagicMock(spec=CloudLLMService)
        service.query = AsyncMock()
        return service
    
    @pytest.fixture
    def handler(self, mock_cloud_llm_service):
        """Create a CloudLLMHandler with mock service."""
        return CloudLLMHandler(mock_cloud_llm_service)
    
    @pytest.mark.asyncio
    async def test_handle_cloud_llm_query_success(self, handler, mock_cloud_llm_service):
        """Test successful Cloud LLM query handling."""
        # Setup mock response
        mock_cloud_llm_service.query.return_value = CloudLLMResponse(
            content="Test response",
            model="claude-sonnet",
            sources=["doc1.md", "doc2.md"],
            tokens_used=100,
            used_rag=True,
        )
        
        # Create query message
        query_msg = CloudLLMQueryMessage(
            content="What is the architecture?",
            context=[
                {"text": "Hello", "source": "microphone", "timestamp": 1.0},
            ],
            force_rag=False,
        )
        
        # Handle query
        response = await handler.handle_cloud_llm_query(query_msg)
        
        # Verify response
        assert isinstance(response, CloudLLMResponseMessage)
        assert response.content == "Test response"
        assert response.model == "claude-sonnet"
        assert response.sources == ["doc1.md", "doc2.md"]
        assert response.tokens_used == 100
        assert response.used_rag is True
    
    @pytest.mark.asyncio
    async def test_handle_cloud_llm_query_access_denied(self, handler, mock_cloud_llm_service):
        """Test Cloud LLM query with access denied error."""
        mock_cloud_llm_service.query.side_effect = BedrockAccessDeniedError()
        
        query_msg = CloudLLMQueryMessage(
            content="Test query",
            context=[],
            force_rag=False,
        )
        
        response = await handler.handle_cloud_llm_query(query_msg)
        
        assert isinstance(response, CloudLLMErrorMessage)
        assert response.error_type == "credentials"
        assert "aws configure" in response.suggestion.lower()
    
    @pytest.mark.asyncio
    async def test_handle_cloud_llm_query_unavailable(self, handler, mock_cloud_llm_service):
        """Test Cloud LLM query with service unavailable error."""
        mock_cloud_llm_service.query.side_effect = BedrockUnavailableError()
        
        query_msg = CloudLLMQueryMessage(
            content="Test query",
            context=[],
            force_rag=False,
        )
        
        response = await handler.handle_cloud_llm_query(query_msg)
        
        assert isinstance(response, CloudLLMErrorMessage)
        assert response.error_type == "service_unavailable"
        assert "/quick" in response.suggestion
    
    @pytest.mark.asyncio
    async def test_handle_cloud_llm_query_timeout(self, handler, mock_cloud_llm_service):
        """Test Cloud LLM query with timeout error."""
        mock_cloud_llm_service.query.side_effect = CloudQueryTimeoutError(120.0)
        
        query_msg = CloudLLMQueryMessage(
            content="Test query",
            context=[],
            force_rag=False,
        )
        
        response = await handler.handle_cloud_llm_query(query_msg)
        
        assert isinstance(response, CloudLLMErrorMessage)
        assert response.error_type == "timeout"
    
    def test_build_conversation_context(self, handler):
        """Test building ConversationContext from IPC message."""
        query_msg = CloudLLMQueryMessage(
            content="What is the architecture?",
            context=[
                {"text": "Hello", "source": "microphone", "timestamp": 1.0},
                {"text": "System audio", "source": "system", "timestamp": 2.0},
            ],
            force_rag=False,
        )
        
        context = handler._build_conversation_context(query_msg)
        
        assert isinstance(context, ConversationContext)
        assert context.user_query == "What is the architecture?"
        assert len(context.transcript) == 2
        assert context.transcript[0].text == "Hello"
        assert context.transcript[0].source == "microphone"
        assert context.transcript[1].source == "system"


class TestS3KBHandler:
    """Tests for S3KBHandler."""
    
    @pytest.fixture
    def mock_s3_manager(self):
        """Create a mock S3DocumentManager."""
        manager = MagicMock(spec=S3DocumentManager)
        manager.list_documents = AsyncMock()
        manager.add_document = AsyncMock()
        manager.update_document = AsyncMock()
        manager.remove_document = AsyncMock()
        return manager
    
    @pytest.fixture
    def mock_kb_service(self):
        """Create a mock KnowledgeBaseService."""
        service = MagicMock(spec=KnowledgeBaseService)
        service.start_sync = AsyncMock()
        return service
    
    @pytest.fixture
    def handler(self, mock_s3_manager, mock_kb_service):
        """Create an S3KBHandler with mock services."""
        return S3KBHandler(mock_s3_manager, mock_kb_service)
    
    @pytest.mark.asyncio
    async def test_handle_kb_list_success(self, handler, mock_s3_manager):
        """Test successful KB list handling."""
        mock_s3_manager.list_documents.return_value = (
            [
                S3Document(
                    name="doc1.md",
                    key="kb-documents/doc1.md",
                    size_bytes=1024,
                    last_modified=1000.0,
                    etag="abc123",
                ),
            ],
            None,  # No continuation token
        )
        
        response = await handler.handle_kb_list()
        
        assert len(response.documents) == 1
        assert response.documents[0]["name"] == "doc1.md"
        assert response.has_more is False
        assert response.continuation_token is None
    
    @pytest.mark.asyncio
    async def test_handle_kb_list_with_pagination(self, handler, mock_s3_manager):
        """Test KB list with pagination."""
        mock_s3_manager.list_documents.return_value = (
            [S3Document("doc1.md", "key", 100, 1.0, "etag")],
            "next-token",
        )
        
        request = KBListRequestMessage(
            continuation_token=None,
            max_items=20,
        )
        
        response = await handler.handle_kb_list(request)
        
        assert response.has_more is True
        assert response.continuation_token == "next-token"
    
    @pytest.mark.asyncio
    async def test_handle_kb_add_success(self, handler, mock_s3_manager, tmp_path):
        """Test successful KB add handling."""
        # Create a temp markdown file
        test_file = tmp_path / "test.md"
        test_file.write_text("# Test Document")
        
        mock_s3_manager.add_document.return_value = S3Document(
            name="test.md",
            key="kb-documents/test.md",
            size_bytes=16,
            last_modified=1000.0,
            etag="abc123",
        )
        
        add_msg = KBAddMessage(
            source_path=str(test_file),
            name="test.md",
        )
        
        response = await handler.handle_kb_add(add_msg)
        
        assert isinstance(response, KBResponseMessage)
        assert response.success is True
        assert "test.md" in response.message
    
    @pytest.mark.asyncio
    async def test_handle_kb_add_file_not_found(self, handler):
        """Test KB add with non-existent file."""
        add_msg = KBAddMessage(
            source_path="/nonexistent/file.md",
            name="test.md",
        )
        
        response = await handler.handle_kb_add(add_msg)
        
        assert isinstance(response, KBErrorMessage)
        assert response.error_type == "not_found"
    
    @pytest.mark.asyncio
    async def test_handle_kb_add_document_exists(self, handler, mock_s3_manager, tmp_path):
        """Test KB add with existing document."""
        test_file = tmp_path / "test.md"
        test_file.write_text("# Test")
        
        mock_s3_manager.add_document.side_effect = DocumentExistsError("test.md")
        
        add_msg = KBAddMessage(
            source_path=str(test_file),
            name="test.md",
        )
        
        response = await handler.handle_kb_add(add_msg)
        
        assert isinstance(response, KBErrorMessage)
        assert response.error_type == "exists"
    
    @pytest.mark.asyncio
    async def test_handle_kb_remove_with_sync(self, handler, mock_s3_manager, mock_kb_service):
        """Test KB remove triggers sync."""
        mock_s3_manager.remove_document.return_value = True
        mock_kb_service.start_sync.return_value = "job-123"
        
        remove_msg = KBRemoveMessage(name="test.md")
        
        response = await handler.handle_kb_remove(remove_msg)
        
        assert isinstance(response, KBResponseMessage)
        assert response.success is True
        assert "job-123" in response.message
        mock_kb_service.start_sync.assert_called_once()
    
    @pytest.mark.asyncio
    async def test_handle_kb_remove_not_found(self, handler, mock_s3_manager):
        """Test KB remove with non-existent document."""
        mock_s3_manager.remove_document.side_effect = DocumentNotFoundError("test.md")
        
        remove_msg = KBRemoveMessage(name="test.md")
        
        response = await handler.handle_kb_remove(remove_msg)
        
        assert isinstance(response, KBErrorMessage)
        assert response.error_type == "not_found"


class TestKBSyncHandler:
    """Tests for KBSyncHandler."""
    
    @pytest.fixture
    def mock_kb_service(self):
        """Create a mock KnowledgeBaseService."""
        service = MagicMock(spec=KnowledgeBaseService)
        service.get_sync_status = AsyncMock()
        service.start_sync = AsyncMock()
        return service
    
    @pytest.fixture
    def handler(self, mock_kb_service):
        """Create a KBSyncHandler with mock service."""
        return KBSyncHandler(mock_kb_service)
    
    @pytest.mark.asyncio
    async def test_handle_sync_status_success(self, handler, mock_kb_service):
        """Test successful sync status handling."""
        mock_kb_service.get_sync_status.return_value = SyncStatus(
            status="READY",
            last_sync=1000.0,
            document_count=10,
            error_message=None,
        )
        
        response = await handler.handle_sync_status()
        
        assert isinstance(response, KBSyncStatusMessage)
        assert response.status == "READY"
        assert response.document_count == 10
        assert response.last_sync == 1000.0
    
    @pytest.mark.asyncio
    async def test_handle_sync_status_kb_not_found(self, handler, mock_kb_service):
        """Test sync status with KB not found."""
        mock_kb_service.get_sync_status.side_effect = KBNotFoundError("kb-123")
        
        response = await handler.handle_sync_status()
        
        assert isinstance(response, KBErrorMessage)
        assert response.error_type == "not_found"
    
    @pytest.mark.asyncio
    async def test_handle_sync_trigger_success(self, handler, mock_kb_service):
        """Test successful sync trigger."""
        mock_kb_service.start_sync.return_value = "job-456"
        
        response = await handler.handle_sync_trigger()
        
        assert response.success is True
        assert response.ingestion_job_id == "job-456"
    
    @pytest.mark.asyncio
    async def test_handle_sync_trigger_already_running(self, handler, mock_kb_service):
        """Test sync trigger when job already running."""
        mock_kb_service.start_sync.side_effect = KBSyncError(
            "A sync job is already in progress."
        )
        
        response = await handler.handle_sync_trigger()
        
        assert response.success is False
        assert "already in progress" in response.message
