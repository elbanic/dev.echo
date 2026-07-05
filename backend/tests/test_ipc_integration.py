"""
Tests for IPC Server Integration with Phase 2 Handlers

Validates that IPC server correctly routes Phase 2 messages to handlers.
"""

import pytest
import asyncio
from unittest.mock import AsyncMock, MagicMock, patch

from ipc.server import IPCServer
from ipc.protocol import (
    MessageType,
    IPCMessage,
    CloudLLMQueryMessage,
    CloudLLMResponseMessage,
    CloudLLMErrorMessage,
    KBListRequestMessage,
    KBListResponseWithPaginationMessage,
    KBAddMessage,
    KBUpdateMessage,
    KBRemoveMessage,
    KBResponseMessage,
    KBErrorMessage,
    KBSyncStatusMessage,
    KBSyncTriggerResponseMessage,
)


class TestIPCServerPhase2Registration:
    """Tests for Phase 2 handler registration."""
    
    def test_cloud_llm_handler_registration(self):
        """Test Cloud LLM handler can be registered."""
        server = IPCServer()
        handler = AsyncMock()
        
        server.on_cloud_llm_query(handler)
        
        assert server._cloud_llm_query_handler is handler
    
    def test_kb_list_paginated_handler_registration(self):
        """Test paginated KB list handler can be registered."""
        server = IPCServer()
        handler = AsyncMock()
        
        server.on_kb_list_paginated(handler)
        
        assert server._kb_list_paginated_handler is handler
    
    def test_s3_kb_handlers_registration(self):
        """Test S3 KB handlers can be registered."""
        server = IPCServer()
        add_handler = AsyncMock()
        update_handler = AsyncMock()
        remove_handler = AsyncMock()
        
        server.on_s3_kb_add(add_handler)
        server.on_s3_kb_update(update_handler)
        server.on_s3_kb_remove(remove_handler)
        
        assert server._s3_kb_add_handler is add_handler
        assert server._s3_kb_update_handler is update_handler
        assert server._s3_kb_remove_handler is remove_handler
    
    def test_kb_sync_handlers_registration(self):
        """Test KB sync handlers can be registered."""
        server = IPCServer()
        status_handler = AsyncMock()
        trigger_handler = AsyncMock()
        
        server.on_kb_sync_status(status_handler)
        server.on_kb_sync_trigger(trigger_handler)
        
        assert server._kb_sync_status_handler is status_handler
        assert server._kb_sync_trigger_handler is trigger_handler


class TestIPCServerPhase2MessageRouting:
    """Tests for Phase 2 message routing in IPC server."""
    
    @pytest.fixture
    def server(self):
        """Create an IPC server instance."""
        return IPCServer()
    
    @pytest.fixture
    def mock_writer(self):
        """Create a mock StreamWriter."""
        writer = MagicMock()
        writer.write = MagicMock()
        writer.drain = AsyncMock()
        return writer
    
    @pytest.mark.asyncio
    async def test_cloud_llm_query_routing(self, server, mock_writer):
        """Test CLOUD_LLM_QUERY message routes to handler."""
        # Setup handler
        handler = AsyncMock(return_value=CloudLLMResponseMessage(
            content="Test response",
            model="claude-sonnet",
            sources=["doc.md"],
            tokens_used=100,
            used_rag=True,
        ))
        server.on_cloud_llm_query(handler)
        
        # Create message
        message = IPCMessage(
            type=MessageType.CLOUD_LLM_QUERY,
            payload={
                "content": "Test query",
                "context": [],
                "force_rag": False,
            }
        )
        
        # Process message
        await server._process_message(message, mock_writer)
        
        # Verify handler was called
        handler.assert_called_once()
        call_args = handler.call_args[0][0]
        assert isinstance(call_args, CloudLLMQueryMessage)
        assert call_args.content == "Test query"
        
        # Verify response was written
        mock_writer.write.assert_called_once()
        mock_writer.drain.assert_called_once()
    
    @pytest.mark.asyncio
    async def test_kb_list_routes_to_paginated_handler(self, server, mock_writer):
        """Test KB_LIST routes to paginated handler when registered."""
        # Setup paginated handler (Phase 2)
        paginated_handler = AsyncMock(return_value=KBListResponseWithPaginationMessage(
            documents=[{"name": "doc.md"}],
            has_more=False,
            continuation_token=None,
        ))
        server.on_kb_list_paginated(paginated_handler)
        
        # Also register Phase 1 handler
        phase1_handler = AsyncMock()
        server.on_kb_list(phase1_handler)
        
        # Create message
        message = IPCMessage(
            type=MessageType.KB_LIST,
            payload={"max_items": 20}
        )
        
        # Process message
        await server._process_message(message, mock_writer)
        
        # Verify paginated handler was called (not Phase 1)
        paginated_handler.assert_called_once()
        phase1_handler.assert_not_called()
    
    @pytest.mark.asyncio
    async def test_kb_add_routes_to_s3_handler(self, server, mock_writer):
        """Test KB_ADD routes to S3 handler when registered."""
        # Setup S3 handler (Phase 2)
        s3_handler = AsyncMock(return_value=KBResponseMessage(
            success=True,
            message="Added: test.md",
            document={"name": "test.md"},
        ))
        server.on_s3_kb_add(s3_handler)
        
        # Also register Phase 1 handler
        phase1_handler = AsyncMock()
        server.on_kb_add(phase1_handler)
        
        # Create message
        message = IPCMessage(
            type=MessageType.KB_ADD,
            payload={"source_path": "/path/to/file.md", "name": "test.md"}
        )
        
        # Process message
        await server._process_message(message, mock_writer)
        
        # Verify S3 handler was called (not Phase 1)
        s3_handler.assert_called_once()
        phase1_handler.assert_not_called()
    
    @pytest.mark.asyncio
    async def test_kb_update_routes_to_s3_handler(self, server, mock_writer):
        """Test KB_UPDATE routes to S3 handler when registered."""
        # Setup S3 handler (Phase 2)
        s3_handler = AsyncMock(return_value=KBResponseMessage(
            success=True,
            message="Updated: test.md",
            document={"name": "test.md"},
        ))
        server.on_s3_kb_update(s3_handler)
        
        # Also register Phase 1 handler
        phase1_handler = AsyncMock()
        server.on_kb_update(phase1_handler)
        
        # Create message
        message = IPCMessage(
            type=MessageType.KB_UPDATE,
            payload={"source_path": "/path/to/file.md", "name": "test.md"}
        )
        
        # Process message
        await server._process_message(message, mock_writer)
        
        # Verify S3 handler was called (not Phase 1)
        s3_handler.assert_called_once()
        phase1_handler.assert_not_called()
    
    @pytest.mark.asyncio
    async def test_kb_remove_routes_to_s3_handler(self, server, mock_writer):
        """Test KB_REMOVE routes to S3 handler when registered."""
        # Setup S3 handler (Phase 2)
        s3_handler = AsyncMock(return_value=KBResponseMessage(
            success=True,
            message="Removed: test.md",
            document=None,
        ))
        server.on_s3_kb_remove(s3_handler)
        
        # Also register Phase 1 handler
        phase1_handler = AsyncMock()
        server.on_kb_remove(phase1_handler)
        
        # Create message
        message = IPCMessage(
            type=MessageType.KB_REMOVE,
            payload={"name": "test.md"}
        )
        
        # Process message
        await server._process_message(message, mock_writer)
        
        # Verify S3 handler was called (not Phase 1)
        s3_handler.assert_called_once()
        phase1_handler.assert_not_called()
    
    @pytest.mark.asyncio
    async def test_kb_sync_status_routing(self, server, mock_writer):
        """Test KB_SYNC_STATUS message routes to handler."""
        # Setup handler
        handler = AsyncMock(return_value=KBSyncStatusMessage(
            status="READY",
            document_count=10,
            last_sync=1234567890.0,
            error_message=None,
        ))
        server.on_kb_sync_status(handler)
        
        # Create message
        message = IPCMessage(
            type=MessageType.KB_SYNC_STATUS,
            payload={}
        )
        
        # Process message
        await server._process_message(message, mock_writer)
        
        # Verify handler was called
        handler.assert_called_once()
        mock_writer.write.assert_called_once()
    
    @pytest.mark.asyncio
    async def test_kb_sync_trigger_routing(self, server, mock_writer):
        """Test KB_SYNC_TRIGGER message routes to handler."""
        # Setup handler
        handler = AsyncMock(return_value=KBSyncTriggerResponseMessage(
            success=True,
            ingestion_job_id="job-123",
            message="Sync started",
        ))
        server.on_kb_sync_trigger(handler)
        
        # Create message
        message = IPCMessage(
            type=MessageType.KB_SYNC_TRIGGER,
            payload={}
        )
        
        # Process message
        await server._process_message(message, mock_writer)
        
        # Verify handler was called
        handler.assert_called_once()
        mock_writer.write.assert_called_once()


class TestIPCServerPhase1Fallback:
    """Tests for Phase 1 fallback when Phase 2 handlers not registered."""
    
    @pytest.fixture
    def server(self):
        """Create an IPC server instance."""
        return IPCServer()
    
    @pytest.fixture
    def mock_writer(self):
        """Create a mock StreamWriter."""
        writer = MagicMock()
        writer.write = MagicMock()
        writer.drain = AsyncMock()
        return writer
    
    @pytest.mark.asyncio
    async def test_kb_list_falls_back_to_phase1(self, server, mock_writer):
        """Test KB_LIST falls back to Phase 1 handler when Phase 2 not registered."""
        # Only register Phase 1 handler
        phase1_handler = AsyncMock(return_value=MagicMock(
            to_ipc_message=MagicMock(return_value=MagicMock(
                to_json=MagicMock(return_value='{"type":"kb_list_response","payload":{}}')
            ))
        ))
        server.on_kb_list(phase1_handler)
        
        # Create message
        message = IPCMessage(
            type=MessageType.KB_LIST,
            payload={}
        )
        
        # Process message
        await server._process_message(message, mock_writer)
        
        # Verify Phase 1 handler was called
        phase1_handler.assert_called_once()
    
    @pytest.mark.asyncio
    async def test_kb_add_falls_back_to_phase1(self, server, mock_writer):
        """Test KB_ADD falls back to Phase 1 handler when Phase 2 not registered."""
        # Only register Phase 1 handler
        phase1_handler = AsyncMock(return_value=MagicMock(
            to_ipc_message=MagicMock(return_value=MagicMock(
                to_json=MagicMock(return_value='{"type":"kb_response","payload":{}}')
            ))
        ))
        server.on_kb_add(phase1_handler)
        
        # Create message
        message = IPCMessage(
            type=MessageType.KB_ADD,
            payload={"source_path": "/path/to/file.md", "name": "test.md"}
        )
        
        # Process message
        await server._process_message(message, mock_writer)
        
        # Verify Phase 1 handler was called
        phase1_handler.assert_called_once()


class TestIPCServerErrorHandling:
    """Tests for error handling in Phase 2 message processing."""
    
    @pytest.fixture
    def server(self):
        """Create an IPC server instance."""
        return IPCServer()
    
    @pytest.fixture
    def mock_writer(self):
        """Create a mock StreamWriter."""
        writer = MagicMock()
        writer.write = MagicMock()
        writer.drain = AsyncMock()
        return writer
    
    @pytest.mark.asyncio
    async def test_cloud_llm_error_response(self, server, mock_writer):
        """Test Cloud LLM error response is properly sent."""
        # Setup handler that returns error
        handler = AsyncMock(return_value=CloudLLMErrorMessage(
            error="Service unavailable",
            error_type="service_unavailable",
            suggestion="Try /quick for local LLM",
        ))
        server.on_cloud_llm_query(handler)
        
        # Create message
        message = IPCMessage(
            type=MessageType.CLOUD_LLM_QUERY,
            payload={"content": "Test", "context": [], "force_rag": False}
        )
        
        # Process message
        await server._process_message(message, mock_writer)
        
        # Verify error response was written
        mock_writer.write.assert_called_once()
        written_data = mock_writer.write.call_args[0][0].decode()
        assert "cloud_llm_error" in written_data
        assert "service_unavailable" in written_data
