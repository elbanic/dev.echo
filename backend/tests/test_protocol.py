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
