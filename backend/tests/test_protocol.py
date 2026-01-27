"""
Tests for IPC Protocol

Validates message serialization/deserialization and type handling.
"""

import pytest
import json
from ipc.protocol import (
    MessageType,
    IPCMessage,
    AudioDataMessage,
    TranscriptionMessage,
    LLMQueryMessage,
    LLMResponseMessage,
    # Phase 2 messages
    CloudLLMQueryMessage,
    CloudLLMResponseMessage,
    CloudLLMErrorMessage,
    KBListRequestMessage,
    KBListResponseWithPaginationMessage,
    KBSyncStatusMessage,
    KBSyncTriggerMessage,
    KBSyncTriggerResponseMessage,
)


class TestIPCMessage:
    """Tests for base IPCMessage class."""
    
    def test_to_json_serialization(self):
        """Test message serializes to valid JSON."""
        msg = IPCMessage(
            type=MessageType.PING,
            payload={"data": "test"}
        )
        
        json_str = msg.to_json()
        parsed = json.loads(json_str)
        
        assert parsed["type"] == "ping"
        assert parsed["payload"]["data"] == "test"
    
    def test_from_json_deserialization(self):
        """Test message deserializes from JSON."""
        json_str = '{"type": "pong", "payload": {"status": "ok"}}'
        
        msg = IPCMessage.from_json(json_str)
        
        assert msg.type == MessageType.PONG
        assert msg.payload["status"] == "ok"
    
    def test_roundtrip_serialization(self):
        """Test message survives roundtrip serialization."""
        original = IPCMessage(
            type=MessageType.TRANSCRIPTION,
            payload={"text": "Hello world", "source": "system"}
        )
        
        json_str = original.to_json()
        restored = IPCMessage.from_json(json_str)
        
        assert restored.type == original.type
        assert restored.payload == original.payload


class TestAudioDataMessage:
    """Tests for AudioDataMessage."""
    
    def test_from_payload_with_samples(self):
        """Test creating AudioDataMessage from raw samples."""
        payload = {
            "samples": [0.1, 0.2, 0.3],
            "sample_rate": 16000,
            "timestamp": 1234567890.0,
            "source": "microphone"
        }
        
        msg = AudioDataMessage.from_payload(payload)
        
        assert msg.samples == [0.1, 0.2, 0.3]
        assert msg.sample_rate == 16000
        assert msg.source == "microphone"
    
    def test_to_ipc_message(self):
        """Test converting to IPCMessage."""
        audio_msg = AudioDataMessage(
            samples=[0.5, -0.5],
            sample_rate=16000,
            timestamp=1234567890.0,
            source="system"
        )
        
        ipc_msg = audio_msg.to_ipc_message()
        
        assert ipc_msg.type == MessageType.AUDIO_DATA
        assert ipc_msg.payload["source"] == "system"


class TestTranscriptionMessage:
    """Tests for TranscriptionMessage."""
    
    def test_from_payload(self):
        """Test creating TranscriptionMessage from payload."""
        payload = {
            "text": "Hello world",
            "source": "system",
            "timestamp": 1234567890.0,
            "confidence": 0.95
        }
        
        msg = TranscriptionMessage.from_payload(payload)
        
        assert msg.text == "Hello world"
        assert msg.source == "system"
        assert msg.confidence == 0.95
    
    def test_default_confidence(self):
        """Test default confidence value."""
        payload = {
            "text": "Test",
            "source": "microphone",
            "timestamp": 1234567890.0
        }
        
        msg = TranscriptionMessage.from_payload(payload)
        
        assert msg.confidence == 1.0


class TestLLMMessages:
    """Tests for LLM query and response messages."""
    
    def test_llm_query_from_payload(self):
        """Test creating LLMQueryMessage from payload."""
        payload = {
            "query_type": "quick",
            "content": "Explain this code",
            "context": [{"text": "Previous message", "source": "system"}]
        }
        
        msg = LLMQueryMessage.from_payload(payload)
        
        assert msg.query_type == "quick"
        assert msg.content == "Explain this code"
        assert len(msg.context) == 1
    
    def test_llm_response_to_ipc(self):
        """Test LLMResponseMessage to IPCMessage conversion."""
        response = LLMResponseMessage(
            content="Here is the explanation...",
            model="llama3.2",
            tokens_used=150
        )
        
        ipc_msg = response.to_ipc_message()
        
        assert ipc_msg.type == MessageType.LLM_RESPONSE
        assert ipc_msg.payload["model"] == "llama3.2"


# Phase 2 Protocol Tests

class TestCloudLLMMessages:
    """Tests for Phase 2 Cloud LLM messages."""
    
    def test_cloud_llm_query_from_payload(self):
        """Test creating CloudLLMQueryMessage from payload."""
        payload = {
            "content": "What is our architecture?",
            "context": [
                {"text": "Hello", "source": "microphone", "timestamp": 1.0},
                {"text": "System audio", "source": "system", "timestamp": 2.0},
            ],
            "force_rag": True,
        }
        
        msg = CloudLLMQueryMessage.from_payload(payload)
        
        assert msg.content == "What is our architecture?"
        assert len(msg.context) == 2
        assert msg.force_rag is True
    
    def test_cloud_llm_query_default_force_rag(self):
        """Test CloudLLMQueryMessage default force_rag value."""
        payload = {
            "content": "Test query",
            "context": [],
        }
        
        msg = CloudLLMQueryMessage.from_payload(payload)
        
        assert msg.force_rag is False
    
    def test_cloud_llm_query_to_ipc(self):
        """Test CloudLLMQueryMessage to IPCMessage conversion."""
        query = CloudLLMQueryMessage(
            content="Test query",
            context=[{"text": "Context", "source": "system", "timestamp": 1.0}],
            force_rag=False,
        )
        
        ipc_msg = query.to_ipc_message()
        
        assert ipc_msg.type == MessageType.CLOUD_LLM_QUERY
        assert ipc_msg.payload["content"] == "Test query"
    
    def test_cloud_llm_response_from_payload(self):
        """Test creating CloudLLMResponseMessage from payload."""
        payload = {
            "content": "Here is the answer...",
            "model": "claude-sonnet",
            "sources": ["doc1.md", "doc2.md"],
            "tokens_used": 150,
            "used_rag": True,
        }
        
        msg = CloudLLMResponseMessage.from_payload(payload)
        
        assert msg.content == "Here is the answer..."
        assert msg.model == "claude-sonnet"
        assert msg.sources == ["doc1.md", "doc2.md"]
        assert msg.tokens_used == 150
        assert msg.used_rag is True
    
    def test_cloud_llm_response_to_ipc(self):
        """Test CloudLLMResponseMessage to IPCMessage conversion."""
        response = CloudLLMResponseMessage(
            content="Response content",
            model="claude-sonnet",
            sources=["source.md"],
            tokens_used=100,
            used_rag=True,
        )
        
        ipc_msg = response.to_ipc_message()
        
        assert ipc_msg.type == MessageType.CLOUD_LLM_RESPONSE
        assert ipc_msg.payload["sources"] == ["source.md"]
    
    def test_cloud_llm_error_from_payload(self):
        """Test creating CloudLLMErrorMessage from payload."""
        payload = {
            "error": "Service unavailable",
            "error_type": "service_unavailable",
            "suggestion": "Try /quick for local LLM",
        }
        
        msg = CloudLLMErrorMessage.from_payload(payload)
        
        assert msg.error == "Service unavailable"
        assert msg.error_type == "service_unavailable"
        assert msg.suggestion == "Try /quick for local LLM"
    
    def test_cloud_llm_error_to_ipc(self):
        """Test CloudLLMErrorMessage to IPCMessage conversion."""
        error = CloudLLMErrorMessage(
            error="Access denied",
            error_type="credentials",
            suggestion="Check AWS credentials",
        )
        
        ipc_msg = error.to_ipc_message()
        
        assert ipc_msg.type == MessageType.CLOUD_LLM_ERROR
        assert ipc_msg.payload["error_type"] == "credentials"


class TestKBPaginationMessages:
    """Tests for Phase 2 KB pagination messages."""
    
    def test_kb_list_request_from_payload(self):
        """Test creating KBListRequestMessage from payload."""
        payload = {
            "continuation_token": "token123",
            "max_items": 50,
        }
        
        msg = KBListRequestMessage.from_payload(payload)
        
        assert msg.continuation_token == "token123"
        assert msg.max_items == 50
    
    def test_kb_list_request_defaults(self):
        """Test KBListRequestMessage default values."""
        payload = {}
        
        msg = KBListRequestMessage.from_payload(payload)
        
        assert msg.continuation_token is None
        assert msg.max_items == 20
    
    def test_kb_list_request_to_ipc(self):
        """Test KBListRequestMessage to IPCMessage conversion."""
        request = KBListRequestMessage(
            continuation_token="next-page",
            max_items=30,
        )
        
        ipc_msg = request.to_ipc_message()
        
        assert ipc_msg.type == MessageType.KB_LIST
        assert ipc_msg.payload["continuation_token"] == "next-page"
    
    def test_kb_list_response_with_pagination_from_payload(self):
        """Test creating KBListResponseWithPaginationMessage from payload."""
        payload = {
            "documents": [
                {"name": "doc1.md", "key": "kb/doc1.md", "size_bytes": 100},
            ],
            "has_more": True,
            "continuation_token": "next-token",
        }
        
        msg = KBListResponseWithPaginationMessage.from_payload(payload)
        
        assert len(msg.documents) == 1
        assert msg.has_more is True
        assert msg.continuation_token == "next-token"
    
    def test_kb_list_response_with_pagination_to_ipc(self):
        """Test KBListResponseWithPaginationMessage to IPCMessage conversion."""
        response = KBListResponseWithPaginationMessage(
            documents=[{"name": "test.md"}],
            has_more=False,
            continuation_token=None,
        )
        
        ipc_msg = response.to_ipc_message()
        
        assert ipc_msg.type == MessageType.KB_LIST_RESPONSE
        assert ipc_msg.payload["has_more"] is False


class TestKBSyncMessages:
    """Tests for Phase 2 KB sync messages."""
    
    def test_kb_sync_status_from_payload(self):
        """Test creating KBSyncStatusMessage from payload."""
        payload = {
            "status": "READY",
            "document_count": 10,
            "last_sync": 1234567890.0,
            "error_message": None,
        }
        
        msg = KBSyncStatusMessage.from_payload(payload)
        
        assert msg.status == "READY"
        assert msg.document_count == 10
        assert msg.last_sync == 1234567890.0
        assert msg.error_message is None
    
    def test_kb_sync_status_to_ipc(self):
        """Test KBSyncStatusMessage to IPCMessage conversion."""
        status = KBSyncStatusMessage(
            status="SYNCING",
            document_count=5,
            last_sync=None,
            error_message=None,
        )
        
        ipc_msg = status.to_ipc_message()
        
        assert ipc_msg.type == MessageType.KB_SYNC_STATUS
        assert ipc_msg.payload["status"] == "SYNCING"
    
    def test_kb_sync_trigger_from_payload(self):
        """Test creating KBSyncTriggerMessage from payload."""
        payload = {}
        
        msg = KBSyncTriggerMessage.from_payload(payload)
        
        assert msg is not None
    
    def test_kb_sync_trigger_to_ipc(self):
        """Test KBSyncTriggerMessage to IPCMessage conversion."""
        trigger = KBSyncTriggerMessage()
        
        ipc_msg = trigger.to_ipc_message()
        
        assert ipc_msg.type == MessageType.KB_SYNC_TRIGGER
    
    def test_kb_sync_trigger_response_from_payload(self):
        """Test creating KBSyncTriggerResponseMessage from payload."""
        payload = {
            "success": True,
            "ingestion_job_id": "job-123",
            "message": "Sync started",
        }
        
        msg = KBSyncTriggerResponseMessage.from_payload(payload)
        
        assert msg.success is True
        assert msg.ingestion_job_id == "job-123"
        assert msg.message == "Sync started"
    
    def test_kb_sync_trigger_response_to_ipc(self):
        """Test KBSyncTriggerResponseMessage to IPCMessage conversion."""
        response = KBSyncTriggerResponseMessage(
            success=False,
            ingestion_job_id=None,
            message="Sync already in progress",
        )
        
        ipc_msg = response.to_ipc_message()
        
        assert ipc_msg.type == MessageType.KB_RESPONSE
        assert ipc_msg.payload["success"] is False


class TestPhase2MessageRoundtrip:
    """Tests for Phase 2 message roundtrip serialization."""
    
    def test_cloud_llm_query_roundtrip(self):
        """Test CloudLLMQueryMessage survives roundtrip."""
        original = CloudLLMQueryMessage(
            content="Test query",
            context=[{"text": "Context", "source": "system", "timestamp": 1.0}],
            force_rag=True,
        )
        
        ipc_msg = original.to_ipc_message()
        json_str = ipc_msg.to_json()
        restored_ipc = IPCMessage.from_json(json_str)
        restored = CloudLLMQueryMessage.from_payload(restored_ipc.payload)
        
        assert restored.content == original.content
        assert restored.force_rag == original.force_rag
        assert len(restored.context) == len(original.context)
    
    def test_cloud_llm_response_roundtrip(self):
        """Test CloudLLMResponseMessage survives roundtrip."""
        original = CloudLLMResponseMessage(
            content="Response",
            model="claude-sonnet",
            sources=["doc1.md", "doc2.md"],
            tokens_used=100,
            used_rag=True,
        )
        
        ipc_msg = original.to_ipc_message()
        json_str = ipc_msg.to_json()
        restored_ipc = IPCMessage.from_json(json_str)
        restored = CloudLLMResponseMessage.from_payload(restored_ipc.payload)
        
        assert restored.content == original.content
        assert restored.model == original.model
        assert restored.sources == original.sources
        assert restored.used_rag == original.used_rag
    
    def test_kb_sync_status_roundtrip(self):
        """Test KBSyncStatusMessage survives roundtrip."""
        original = KBSyncStatusMessage(
            status="READY",
            document_count=15,
            last_sync=1234567890.0,
            error_message=None,
        )
        
        ipc_msg = original.to_ipc_message()
        json_str = ipc_msg.to_json()
        restored_ipc = IPCMessage.from_json(json_str)
        restored = KBSyncStatusMessage.from_payload(restored_ipc.payload)
        
        assert restored.status == original.status
        assert restored.document_count == original.document_count
        assert restored.last_sync == original.last_sync
