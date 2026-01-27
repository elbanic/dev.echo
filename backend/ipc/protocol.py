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
    
    # LLM messages (Phase 1 - Local LLM)
    LLM_QUERY = "llm_query"
    LLM_RESPONSE = "llm_response"
    LLM_ERROR = "llm_error"
    
    # Cloud LLM messages (Phase 2)
    CLOUD_LLM_QUERY = "cloud_llm_query"
    CLOUD_LLM_RESPONSE = "cloud_llm_response"
    CLOUD_LLM_ERROR = "cloud_llm_error"
    
    # Knowledge Base messages
    KB_LIST = "kb_list"
    KB_LIST_RESPONSE = "kb_list_response"
    KB_ADD = "kb_add"
    KB_UPDATE = "kb_update"
    KB_REMOVE = "kb_remove"
    KB_RESPONSE = "kb_response"
    KB_ERROR = "kb_error"
    
    # Knowledge Base sync messages (Phase 2)
    KB_SYNC_STATUS = "kb_sync_status"
    KB_SYNC_TRIGGER = "kb_sync_trigger"
    
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


# Knowledge Base Messages

@dataclass
class KBListMessage:
    """Request to list KB documents."""
    
    def to_ipc_message(self) -> IPCMessage:
        return IPCMessage(
            type=MessageType.KB_LIST,
            payload={}
        )
    
    @classmethod
    def from_payload(cls, payload: dict) -> "KBListMessage":
        return cls()


@dataclass
class KBListResponseMessage:
    """Response with list of KB documents."""
    
    documents: List[dict]  # List of KBDocument dicts
    
    def to_ipc_message(self) -> IPCMessage:
        return IPCMessage(
            type=MessageType.KB_LIST_RESPONSE,
            payload={"documents": self.documents}
        )
    
    @classmethod
    def from_payload(cls, payload: dict) -> "KBListResponseMessage":
        return cls(documents=payload.get("documents", []))


@dataclass
class KBAddMessage:
    """Request to add a document to KB."""
    
    source_path: str
    name: str
    
    def to_ipc_message(self) -> IPCMessage:
        return IPCMessage(
            type=MessageType.KB_ADD,
            payload={"source_path": self.source_path, "name": self.name}
        )
    
    @classmethod
    def from_payload(cls, payload: dict) -> "KBAddMessage":
        return cls(
            source_path=payload["source_path"],
            name=payload["name"]
        )


@dataclass
class KBUpdateMessage:
    """Request to update a document in KB."""
    
    source_path: str
    name: str
    
    def to_ipc_message(self) -> IPCMessage:
        return IPCMessage(
            type=MessageType.KB_UPDATE,
            payload={"source_path": self.source_path, "name": self.name}
        )
    
    @classmethod
    def from_payload(cls, payload: dict) -> "KBUpdateMessage":
        return cls(
            source_path=payload["source_path"],
            name=payload["name"]
        )


@dataclass
class KBRemoveMessage:
    """Request to remove a document from KB."""
    
    name: str
    
    def to_ipc_message(self) -> IPCMessage:
        return IPCMessage(
            type=MessageType.KB_REMOVE,
            payload={"name": self.name}
        )
    
    @classmethod
    def from_payload(cls, payload: dict) -> "KBRemoveMessage":
        return cls(name=payload["name"])


@dataclass
class KBResponseMessage:
    """Response for KB operations (add, update, remove)."""
    
    success: bool
    message: str
    document: Optional[dict] = None  # KBDocument dict for add/update
    
    def to_ipc_message(self) -> IPCMessage:
        return IPCMessage(
            type=MessageType.KB_RESPONSE,
            payload={
                "success": self.success,
                "message": self.message,
                "document": self.document
            }
        )
    
    @classmethod
    def from_payload(cls, payload: dict) -> "KBResponseMessage":
        return cls(
            success=payload["success"],
            message=payload["message"],
            document=payload.get("document")
        )


@dataclass
class KBErrorMessage:
    """Error response for KB operations."""
    
    error: str
    error_type: str  # "not_found", "invalid_markdown", "exists", "other"
    
    def to_ipc_message(self) -> IPCMessage:
        return IPCMessage(
            type=MessageType.KB_ERROR,
            payload={"error": self.error, "error_type": self.error_type}
        )
    
    @classmethod
    def from_payload(cls, payload: dict) -> "KBErrorMessage":
        return cls(
            error=payload["error"],
            error_type=payload.get("error_type", "other")
        )



# Phase 2: Cloud LLM Messages

@dataclass
class CloudLLMQueryMessage:
    """Cloud LLM query with RAG support (Phase 2)."""
    
    content: str
    context: List[dict]  # List of TranscriptionMessage dicts
    force_rag: bool = False  # Force RAG even if intent classifier says otherwise
    
    def to_ipc_message(self) -> IPCMessage:
        return IPCMessage(
            type=MessageType.CLOUD_LLM_QUERY,
            payload=asdict(self)
        )
    
    @classmethod
    def from_payload(cls, payload: dict) -> "CloudLLMQueryMessage":
        return cls(
            content=payload["content"],
            context=payload.get("context", []),
            force_rag=payload.get("force_rag", False)
        )


@dataclass
class CloudLLMResponseMessage:
    """Cloud LLM response with sources (Phase 2)."""
    
    content: str
    model: str
    sources: List[str]  # Document names used from KB
    tokens_used: int = 0
    used_rag: bool = False
    
    def to_ipc_message(self) -> IPCMessage:
        return IPCMessage(
            type=MessageType.CLOUD_LLM_RESPONSE,
            payload=asdict(self)
        )
    
    @classmethod
    def from_payload(cls, payload: dict) -> "CloudLLMResponseMessage":
        return cls(
            content=payload["content"],
            model=payload["model"],
            sources=payload.get("sources", []),
            tokens_used=payload.get("tokens_used", 0),
            used_rag=payload.get("used_rag", False)
        )


@dataclass
class CloudLLMErrorMessage:
    """Error response for Cloud LLM operations (Phase 2)."""
    
    error: str
    error_type: str  # "credentials", "service_unavailable", "throttling", "model_error", "other"
    suggestion: Optional[str] = None  # e.g., "Try /quick for local LLM"
    
    def to_ipc_message(self) -> IPCMessage:
        return IPCMessage(
            type=MessageType.CLOUD_LLM_ERROR,
            payload=asdict(self)
        )
    
    @classmethod
    def from_payload(cls, payload: dict) -> "CloudLLMErrorMessage":
        return cls(
            error=payload["error"],
            error_type=payload.get("error_type", "other"),
            suggestion=payload.get("suggestion")
        )


# Phase 2: Extended KB Messages with S3 Pagination

@dataclass
class KBListRequestMessage:
    """Request to list KB documents with pagination (Phase 2)."""
    
    continuation_token: Optional[str] = None
    max_items: int = 20
    
    def to_ipc_message(self) -> IPCMessage:
        return IPCMessage(
            type=MessageType.KB_LIST,
            payload=asdict(self)
        )
    
    @classmethod
    def from_payload(cls, payload: dict) -> "KBListRequestMessage":
        return cls(
            continuation_token=payload.get("continuation_token"),
            max_items=payload.get("max_items", 20)
        )


@dataclass
class KBListResponseWithPaginationMessage:
    """Response with list of KB documents and pagination info (Phase 2)."""
    
    documents: List[dict]  # List of S3Document dicts
    has_more: bool
    continuation_token: Optional[str] = None
    
    def to_ipc_message(self) -> IPCMessage:
        return IPCMessage(
            type=MessageType.KB_LIST_RESPONSE,
            payload={
                "documents": self.documents,
                "has_more": self.has_more,
                "continuation_token": self.continuation_token
            }
        )
    
    @classmethod
    def from_payload(cls, payload: dict) -> "KBListResponseWithPaginationMessage":
        return cls(
            documents=payload.get("documents", []),
            has_more=payload.get("has_more", False),
            continuation_token=payload.get("continuation_token")
        )


# Phase 2: KB Sync Messages

@dataclass
class KBSyncStatusMessage:
    """Bedrock KB sync status (Phase 2)."""
    
    status: str  # "SYNCING", "READY", "FAILED", "UNKNOWN"
    document_count: int
    last_sync: Optional[float] = None
    error_message: Optional[str] = None
    
    def to_ipc_message(self) -> IPCMessage:
        return IPCMessage(
            type=MessageType.KB_SYNC_STATUS,
            payload=asdict(self)
        )
    
    @classmethod
    def from_payload(cls, payload: dict) -> "KBSyncStatusMessage":
        return cls(
            status=payload["status"],
            document_count=payload.get("document_count", 0),
            last_sync=payload.get("last_sync"),
            error_message=payload.get("error_message")
        )


@dataclass
class KBSyncTriggerMessage:
    """Request to trigger KB sync/reindexing (Phase 2)."""
    
    def to_ipc_message(self) -> IPCMessage:
        return IPCMessage(
            type=MessageType.KB_SYNC_TRIGGER,
            payload={}
        )
    
    @classmethod
    def from_payload(cls, payload: dict) -> "KBSyncTriggerMessage":
        return cls()


@dataclass
class KBSyncTriggerResponseMessage:
    """Response for KB sync trigger (Phase 2)."""
    
    success: bool
    ingestion_job_id: Optional[str] = None
    message: str = ""
    
    def to_ipc_message(self) -> IPCMessage:
        return IPCMessage(
            type=MessageType.KB_RESPONSE,
            payload=asdict(self)
        )
    
    @classmethod
    def from_payload(cls, payload: dict) -> "KBSyncTriggerResponseMessage":
        return cls(
            success=payload["success"],
            ingestion_job_id=payload.get("ingestion_job_id"),
            message=payload.get("message", "")
        )
