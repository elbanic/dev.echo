"""
IPC Message Protocol

JSON-based message protocol for Swift-Python communication.
All messages follow a common structure with type discrimination.
"""

from dataclasses import dataclass, asdict
from enum import Enum
from typing import Optional, List, Any
import json


class MessageType(str, Enum):
    """Message types for IPC communication."""
    
    # Audio messages
    AUDIO_DATA = "audio_data"
    
    # Transcription messages
    TRANSCRIPTION = "transcription"
    TRANSCRIPTION_ERROR = "transcription_error"
    
    # LLM messages
    LLM_QUERY = "llm_query"
    LLM_RESPONSE = "llm_response"
    LLM_ERROR = "llm_error"
    
    # Control messages
    PING = "ping"
    PONG = "pong"
    SHUTDOWN = "shutdown"
    ACK = "ack"


@dataclass
class IPCMessage:
    """Base IPC message structure."""
    
    type: MessageType
    payload: dict
    
    def to_json(self) -> str:
        """Serialize message to JSON string."""
        return json.dumps({
            "type": self.type.value,
            "payload": self.payload
        })
    
    @classmethod
    def from_json(cls, json_str: str) -> "IPCMessage":
        """Deserialize message from JSON string."""
        data = json.loads(json_str)
        return cls(
            type=MessageType(data["type"]),
            payload=data.get("payload", {})
        )


@dataclass
class AudioDataMessage:
    """Audio data message from Swift to Python."""
    
    samples: List[float]
    sample_rate: int
    timestamp: float
    source: str  # "system" or "microphone"
    
    def to_ipc_message(self) -> IPCMessage:
        return IPCMessage(
            type=MessageType.AUDIO_DATA,
            payload=asdict(self)
        )
    
    @classmethod
    def from_payload(cls, payload: dict) -> "AudioDataMessage":
        # Handle Base64 encoded samples (preferred)
        if "samples_base64" in payload:
            import base64
            import struct
            
            samples_bytes = base64.b64decode(payload["samples_base64"])
            # Unpack as float32 array
            num_samples = len(samples_bytes) // 4
            samples = list(struct.unpack(f'{num_samples}f', samples_bytes))
        elif "samples" in payload:
            # Fallback to raw samples array
            samples = payload["samples"]
        else:
            samples = []
        
        return cls(
            samples=samples,
            sample_rate=payload["sample_rate"],
            timestamp=payload["timestamp"],
            source=payload["source"]
        )


@dataclass
class TranscriptionMessage:
    """Transcription result message from Python to Swift."""
    
    text: str
    source: str  # "system" or "microphone"
    timestamp: float
    confidence: float = 1.0
    
    def to_ipc_message(self) -> IPCMessage:
        return IPCMessage(
            type=MessageType.TRANSCRIPTION,
            payload=asdict(self)
        )
    
    @classmethod
    def from_payload(cls, payload: dict) -> "TranscriptionMessage":
        return cls(
            text=payload["text"],
            source=payload["source"],
            timestamp=payload["timestamp"],
            confidence=payload.get("confidence", 1.0)
        )


@dataclass
class LLMQueryMessage:
    """LLM query message from Swift to Python."""
    
    query_type: str  # "chat" or "quick"
    content: str
    context: List[dict]  # List of TranscriptionMessage dicts
    
    def to_ipc_message(self) -> IPCMessage:
        return IPCMessage(
            type=MessageType.LLM_QUERY,
            payload=asdict(self)
        )
    
    @classmethod
    def from_payload(cls, payload: dict) -> "LLMQueryMessage":
        return cls(
            query_type=payload["query_type"],
            content=payload["content"],
            context=payload.get("context", [])
        )


@dataclass
class LLMResponseMessage:
    """LLM response message from Python to Swift."""
    
    content: str
    model: str
    tokens_used: int = 0
    
    def to_ipc_message(self) -> IPCMessage:
        return IPCMessage(
            type=MessageType.LLM_RESPONSE,
            payload=asdict(self)
        )
    
    @classmethod
    def from_payload(cls, payload: dict) -> "LLMResponseMessage":
        return cls(
            content=payload["content"],
            model=payload["model"],
            tokens_used=payload.get("tokens_used", 0)
        )
