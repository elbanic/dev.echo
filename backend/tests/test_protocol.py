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
    # TTS messages (Task 22 - RED phase: these do not exist yet)
    TTSSpeakMessage,
    TTSStopMessage,
    TTSStatusMessage,
    TTSSetVoiceMessage,
    TTSVoiceConfigMessage,
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


# TTS Protocol Tests (Task 22 - RED phase)
# These tests validate the TTS IPC message types that need to be added to protocol.py.
# All tests are expected to FAIL with ImportError until the implementation is added.

class TestTTSMessageTypeEnum:
    """Tests for TTS MessageType enum values.

    Validates that the MessageType enum contains all 5 TTS message types
    with correct string values.

    Feature: dev-echo-phase2, Property 16: TTS Playback Lifecycle
    """

    def test_tts_speak_enum_value(self):
        """Test TTS_SPEAK enum has correct string value."""
        assert MessageType.TTS_SPEAK == "tts_speak"
        assert MessageType.TTS_SPEAK.value == "tts_speak"

    def test_tts_stop_enum_value(self):
        """Test TTS_STOP enum has correct string value."""
        assert MessageType.TTS_STOP == "tts_stop"
        assert MessageType.TTS_STOP.value == "tts_stop"

    def test_tts_status_enum_value(self):
        """Test TTS_STATUS enum has correct string value."""
        assert MessageType.TTS_STATUS == "tts_status"
        assert MessageType.TTS_STATUS.value == "tts_status"

    def test_tts_set_voice_enum_value(self):
        """Test TTS_SET_VOICE enum has correct string value."""
        assert MessageType.TTS_SET_VOICE == "tts_set_voice"
        assert MessageType.TTS_SET_VOICE.value == "tts_set_voice"

    def test_tts_voice_config_enum_value(self):
        """Test TTS_VOICE_CONFIG enum has correct string value."""
        assert MessageType.TTS_VOICE_CONFIG == "tts_voice_config"
        assert MessageType.TTS_VOICE_CONFIG.value == "tts_voice_config"

    def test_tts_message_types_are_valid_message_type_instances(self):
        """Test all TTS enum members are valid MessageType instances."""
        tts_types = [
            MessageType.TTS_SPEAK,
            MessageType.TTS_STOP,
            MessageType.TTS_STATUS,
            MessageType.TTS_SET_VOICE,
            MessageType.TTS_VOICE_CONFIG,
        ]
        for mt in tts_types:
            assert isinstance(mt, MessageType)

    def test_tts_message_types_can_be_constructed_from_string(self):
        """Test TTS message types can be instantiated from string values."""
        assert MessageType("tts_speak") == MessageType.TTS_SPEAK
        assert MessageType("tts_stop") == MessageType.TTS_STOP
        assert MessageType("tts_status") == MessageType.TTS_STATUS
        assert MessageType("tts_set_voice") == MessageType.TTS_SET_VOICE
        assert MessageType("tts_voice_config") == MessageType.TTS_VOICE_CONFIG


class TestTTSSpeakMessage:
    """Tests for TTSSpeakMessage.

    Validates the TTS speak request message that the Swift CLI sends
    to the Python backend when the user enters text in Reading Mode.

    Feature: dev-echo-phase2, Property 16: TTS Playback Lifecycle
    """

    def test_from_payload_with_full_data(self):
        """Test creating TTSSpeakMessage from payload with all fields."""
        payload = {
            "text": "Hello, this is a test of text-to-speech.",
            "language": "English",
        }

        msg = TTSSpeakMessage.from_payload(payload)

        assert msg.text == "Hello, this is a test of text-to-speech."
        assert msg.language == "English"

    def test_from_payload_with_minimal_data(self):
        """Test creating TTSSpeakMessage from payload with only required fields."""
        payload = {
            "text": "Minimal test",
        }

        msg = TTSSpeakMessage.from_payload(payload)

        assert msg.text == "Minimal test"
        assert msg.language is None

    def test_from_payload_with_korean_text(self):
        """Test creating TTSSpeakMessage from payload with Korean text."""
        payload = {
            "text": "안녕하세요, 텍스트 음성 변환 테스트입니다.",
            "language": "Korean",
        }

        msg = TTSSpeakMessage.from_payload(payload)

        assert msg.text == "안녕하세요, 텍스트 음성 변환 테스트입니다."
        assert msg.language == "Korean"

    def test_to_ipc_message(self):
        """Test TTSSpeakMessage to IPCMessage conversion."""
        speak_msg = TTSSpeakMessage(
            text="Read this text aloud",
            language="English",
        )

        ipc_msg = speak_msg.to_ipc_message()

        assert ipc_msg.type == MessageType.TTS_SPEAK
        assert ipc_msg.payload["text"] == "Read this text aloud"
        assert ipc_msg.payload["language"] == "English"

    def test_to_ipc_message_with_none_language(self):
        """Test TTSSpeakMessage to IPCMessage with None language."""
        speak_msg = TTSSpeakMessage(
            text="No language specified",
            language=None,
        )

        ipc_msg = speak_msg.to_ipc_message()

        assert ipc_msg.type == MessageType.TTS_SPEAK
        assert ipc_msg.payload["text"] == "No language specified"
        assert ipc_msg.payload["language"] is None


class TestTTSStopMessage:
    """Tests for TTSStopMessage.

    Validates the TTS stop request message that the Swift CLI sends
    to the Python backend to stop current speech playback.

    Feature: dev-echo-phase2, Property 16: TTS Playback Lifecycle
    """

    def test_from_payload(self):
        """Test creating TTSStopMessage from empty payload."""
        payload = {}

        msg = TTSStopMessage.from_payload(payload)

        assert msg is not None

    def test_to_ipc_message(self):
        """Test TTSStopMessage to IPCMessage conversion."""
        stop_msg = TTSStopMessage()

        ipc_msg = stop_msg.to_ipc_message()

        assert ipc_msg.type == MessageType.TTS_STOP
        # The payload should be an empty dict or equivalent
        assert isinstance(ipc_msg.payload, dict)


class TestTTSStatusMessage:
    """Tests for TTSStatusMessage.

    Validates the TTS status update message that the Python backend sends
    to the Swift CLI to report engine state changes.

    Feature: dev-echo-phase2, Property 16: TTS Playback Lifecycle
    """

    def test_from_payload_with_full_data(self):
        """Test creating TTSStatusMessage from payload with all fields."""
        payload = {
            "state": "playing",
            "text": "Currently reading this text",
            "elapsed": 3.5,
            "error": None,
        }

        msg = TTSStatusMessage.from_payload(payload)

        assert msg.state == "playing"
        assert msg.text == "Currently reading this text"
        assert msg.elapsed == 3.5
        assert msg.error is None

    def test_from_payload_with_minimal_data(self):
        """Test creating TTSStatusMessage with only required state field."""
        payload = {
            "state": "idle",
        }

        msg = TTSStatusMessage.from_payload(payload)

        assert msg.state == "idle"
        assert msg.text is None
        assert msg.elapsed is None
        assert msg.error is None

    def test_from_payload_with_error(self):
        """Test creating TTSStatusMessage with error information."""
        payload = {
            "state": "idle",
            "error": "Model failed to load: out of memory",
        }

        msg = TTSStatusMessage.from_payload(payload)

        assert msg.state == "idle"
        assert msg.error == "Model failed to load: out of memory"

    def test_from_payload_loading_model_state(self):
        """Test creating TTSStatusMessage with loading_model state."""
        payload = {
            "state": "loading_model",
        }

        msg = TTSStatusMessage.from_payload(payload)

        assert msg.state == "loading_model"

    def test_from_payload_generating_state(self):
        """Test creating TTSStatusMessage with generating state."""
        payload = {
            "state": "generating",
            "text": "Generating audio for this text",
            "elapsed": 1.2,
        }

        msg = TTSStatusMessage.from_payload(payload)

        assert msg.state == "generating"
        assert msg.text == "Generating audio for this text"
        assert msg.elapsed == 1.2

    def test_from_payload_stopping_state(self):
        """Test creating TTSStatusMessage with stopping state."""
        payload = {
            "state": "stopping",
            "elapsed": 5.0,
        }

        msg = TTSStatusMessage.from_payload(payload)

        assert msg.state == "stopping"
        assert msg.elapsed == 5.0

    def test_to_ipc_message(self):
        """Test TTSStatusMessage to IPCMessage conversion."""
        status_msg = TTSStatusMessage(
            state="playing",
            text="Hello world",
            elapsed=2.5,
            error=None,
        )

        ipc_msg = status_msg.to_ipc_message()

        assert ipc_msg.type == MessageType.TTS_STATUS
        assert ipc_msg.payload["state"] == "playing"
        assert ipc_msg.payload["text"] == "Hello world"
        assert ipc_msg.payload["elapsed"] == 2.5
        assert ipc_msg.payload["error"] is None

    def test_to_ipc_message_minimal(self):
        """Test TTSStatusMessage to IPCMessage with minimal data."""
        status_msg = TTSStatusMessage(
            state="idle",
        )

        ipc_msg = status_msg.to_ipc_message()

        assert ipc_msg.type == MessageType.TTS_STATUS
        assert ipc_msg.payload["state"] == "idle"


class TestTTSSetVoiceMessage:
    """Tests for TTSSetVoiceMessage.

    Validates the TTS voice preset change request that the Swift CLI sends
    to the Python backend when the user runs /voice <preset_name>.

    Feature: dev-echo-phase2, Property 17: TTS Configuration Persistence
    """

    def test_from_payload(self):
        """Test creating TTSSetVoiceMessage from payload."""
        payload = {
            "preset_name": "korean_female",
        }

        msg = TTSSetVoiceMessage.from_payload(payload)

        assert msg.preset_name == "korean_female"

    def test_from_payload_english_male(self):
        """Test creating TTSSetVoiceMessage with english_male preset."""
        payload = {
            "preset_name": "english_male",
        }

        msg = TTSSetVoiceMessage.from_payload(payload)

        assert msg.preset_name == "english_male"

    def test_to_ipc_message(self):
        """Test TTSSetVoiceMessage to IPCMessage conversion."""
        set_voice_msg = TTSSetVoiceMessage(
            preset_name="korean_male",
        )

        ipc_msg = set_voice_msg.to_ipc_message()

        assert ipc_msg.type == MessageType.TTS_SET_VOICE
        assert ipc_msg.payload["preset_name"] == "korean_male"


class TestTTSVoiceConfigMessage:
    """Tests for TTSVoiceConfigMessage.

    Validates the TTS voice configuration response that the Python backend
    sends to the Swift CLI with current voice settings and available presets.

    Feature: dev-echo-phase2, Property 17: TTS Configuration Persistence
    """

    def test_from_payload_with_full_data(self):
        """Test creating TTSVoiceConfigMessage from payload with all fields."""
        payload = {
            "language": "Korean",
            "voice_instruct": "A young Korean female voice, clear and natural.",
            "preset_name": "korean_female",
            "available_presets": [
                "korean_female",
                "korean_male",
                "english_female",
                "english_male",
            ],
        }

        msg = TTSVoiceConfigMessage.from_payload(payload)

        assert msg.language == "Korean"
        assert msg.voice_instruct == "A young Korean female voice, clear and natural."
        assert msg.preset_name == "korean_female"
        assert msg.available_presets == [
            "korean_female",
            "korean_male",
            "english_female",
            "english_male",
        ]

    def test_from_payload_with_minimal_data(self):
        """Test creating TTSVoiceConfigMessage with only required fields."""
        payload = {
            "language": "English",
            "voice_instruct": "A clear English voice.",
        }

        msg = TTSVoiceConfigMessage.from_payload(payload)

        assert msg.language == "English"
        assert msg.voice_instruct == "A clear English voice."
        assert msg.preset_name is None
        assert msg.available_presets is None

    def test_from_payload_with_empty_presets_list(self):
        """Test creating TTSVoiceConfigMessage with empty presets list."""
        payload = {
            "language": "Korean",
            "voice_instruct": "A Korean voice.",
            "preset_name": "custom",
            "available_presets": [],
        }

        msg = TTSVoiceConfigMessage.from_payload(payload)

        assert msg.available_presets == []

    def test_to_ipc_message(self):
        """Test TTSVoiceConfigMessage to IPCMessage conversion."""
        config_msg = TTSVoiceConfigMessage(
            language="Korean",
            voice_instruct="A young Korean female voice, clear and natural.",
            preset_name="korean_female",
            available_presets=["korean_female", "korean_male"],
        )

        ipc_msg = config_msg.to_ipc_message()

        assert ipc_msg.type == MessageType.TTS_VOICE_CONFIG
        assert ipc_msg.payload["language"] == "Korean"
        assert ipc_msg.payload["voice_instruct"] == "A young Korean female voice, clear and natural."
        assert ipc_msg.payload["preset_name"] == "korean_female"
        assert ipc_msg.payload["available_presets"] == ["korean_female", "korean_male"]

    def test_to_ipc_message_with_none_optional_fields(self):
        """Test TTSVoiceConfigMessage to IPCMessage with None optional fields."""
        config_msg = TTSVoiceConfigMessage(
            language="English",
            voice_instruct="An English voice.",
            preset_name=None,
            available_presets=None,
        )

        ipc_msg = config_msg.to_ipc_message()

        assert ipc_msg.type == MessageType.TTS_VOICE_CONFIG
        assert ipc_msg.payload["language"] == "English"
        assert ipc_msg.payload["preset_name"] is None
        assert ipc_msg.payload["available_presets"] is None


class TestTTSMessageRoundtrip:
    """Tests for TTS message roundtrip serialization.

    Validates that all TTS messages survive the full roundtrip:
    dataclass -> to_ipc_message() -> to_json() -> from_json() -> from_payload()

    Feature: dev-echo-phase2, Property 16: TTS Playback Lifecycle
    """

    def test_tts_speak_roundtrip(self):
        """Test TTSSpeakMessage survives roundtrip serialization."""
        original = TTSSpeakMessage(
            text="Read this text aloud please",
            language="English",
        )

        ipc_msg = original.to_ipc_message()
        json_str = ipc_msg.to_json()
        restored_ipc = IPCMessage.from_json(json_str)
        restored = TTSSpeakMessage.from_payload(restored_ipc.payload)

        assert restored.text == original.text
        assert restored.language == original.language

    def test_tts_speak_roundtrip_with_none_language(self):
        """Test TTSSpeakMessage roundtrip with None language."""
        original = TTSSpeakMessage(
            text="No language specified",
            language=None,
        )

        ipc_msg = original.to_ipc_message()
        json_str = ipc_msg.to_json()
        restored_ipc = IPCMessage.from_json(json_str)
        restored = TTSSpeakMessage.from_payload(restored_ipc.payload)

        assert restored.text == original.text
        assert restored.language is None

    def test_tts_speak_roundtrip_with_korean(self):
        """Test TTSSpeakMessage roundtrip with Korean text and language."""
        original = TTSSpeakMessage(
            text="안녕하세요, 이것은 한국어 테스트입니다.",
            language="Korean",
        )

        ipc_msg = original.to_ipc_message()
        json_str = ipc_msg.to_json()
        restored_ipc = IPCMessage.from_json(json_str)
        restored = TTSSpeakMessage.from_payload(restored_ipc.payload)

        assert restored.text == original.text
        assert restored.language == original.language

    def test_tts_stop_roundtrip(self):
        """Test TTSStopMessage survives roundtrip serialization."""
        original = TTSStopMessage()

        ipc_msg = original.to_ipc_message()
        json_str = ipc_msg.to_json()
        restored_ipc = IPCMessage.from_json(json_str)
        restored = TTSStopMessage.from_payload(restored_ipc.payload)

        assert restored is not None

    def test_tts_status_roundtrip_full(self):
        """Test TTSStatusMessage roundtrip with all fields populated."""
        original = TTSStatusMessage(
            state="playing",
            text="Some text being spoken",
            elapsed=5.75,
            error=None,
        )

        ipc_msg = original.to_ipc_message()
        json_str = ipc_msg.to_json()
        restored_ipc = IPCMessage.from_json(json_str)
        restored = TTSStatusMessage.from_payload(restored_ipc.payload)

        assert restored.state == original.state
        assert restored.text == original.text
        assert restored.elapsed == original.elapsed
        assert restored.error == original.error

    def test_tts_status_roundtrip_with_error(self):
        """Test TTSStatusMessage roundtrip with error field."""
        original = TTSStatusMessage(
            state="idle",
            text=None,
            elapsed=None,
            error="Model failed to load",
        )

        ipc_msg = original.to_ipc_message()
        json_str = ipc_msg.to_json()
        restored_ipc = IPCMessage.from_json(json_str)
        restored = TTSStatusMessage.from_payload(restored_ipc.payload)

        assert restored.state == original.state
        assert restored.text is None
        assert restored.elapsed is None
        assert restored.error == original.error

    def test_tts_set_voice_roundtrip(self):
        """Test TTSSetVoiceMessage survives roundtrip serialization."""
        original = TTSSetVoiceMessage(
            preset_name="english_female",
        )

        ipc_msg = original.to_ipc_message()
        json_str = ipc_msg.to_json()
        restored_ipc = IPCMessage.from_json(json_str)
        restored = TTSSetVoiceMessage.from_payload(restored_ipc.payload)

        assert restored.preset_name == original.preset_name

    def test_tts_voice_config_roundtrip_full(self):
        """Test TTSVoiceConfigMessage roundtrip with all fields populated."""
        original = TTSVoiceConfigMessage(
            language="Korean",
            voice_instruct="A young Korean female voice, clear and natural.",
            preset_name="korean_female",
            available_presets=["korean_female", "korean_male", "english_female", "english_male"],
        )

        ipc_msg = original.to_ipc_message()
        json_str = ipc_msg.to_json()
        restored_ipc = IPCMessage.from_json(json_str)
        restored = TTSVoiceConfigMessage.from_payload(restored_ipc.payload)

        assert restored.language == original.language
        assert restored.voice_instruct == original.voice_instruct
        assert restored.preset_name == original.preset_name
        assert restored.available_presets == original.available_presets

    def test_tts_voice_config_roundtrip_minimal(self):
        """Test TTSVoiceConfigMessage roundtrip with only required fields."""
        original = TTSVoiceConfigMessage(
            language="English",
            voice_instruct="A clear English voice.",
            preset_name=None,
            available_presets=None,
        )

        ipc_msg = original.to_ipc_message()
        json_str = ipc_msg.to_json()
        restored_ipc = IPCMessage.from_json(json_str)
        restored = TTSVoiceConfigMessage.from_payload(restored_ipc.payload)

        assert restored.language == original.language
        assert restored.voice_instruct == original.voice_instruct
        assert restored.preset_name is None
        assert restored.available_presets is None


class TestTTSMessageJsonDeserialization:
    """Tests for TTS message deserialization from raw JSON strings.

    Validates that the full pipeline works when starting from a raw JSON
    string (as received over the Unix Domain Socket).

    Feature: dev-echo-phase2, Property 16: TTS Playback Lifecycle
    """

    def test_tts_speak_from_raw_json(self):
        """Test deserializing tts_speak from raw JSON string."""
        json_str = json.dumps({
            "type": "tts_speak",
            "payload": {
                "text": "Hello from JSON",
                "language": "English",
            }
        })

        ipc_msg = IPCMessage.from_json(json_str)

        assert ipc_msg.type == MessageType.TTS_SPEAK
        msg = TTSSpeakMessage.from_payload(ipc_msg.payload)
        assert msg.text == "Hello from JSON"
        assert msg.language == "English"

    def test_tts_stop_from_raw_json(self):
        """Test deserializing tts_stop from raw JSON string."""
        json_str = json.dumps({
            "type": "tts_stop",
            "payload": {}
        })

        ipc_msg = IPCMessage.from_json(json_str)

        assert ipc_msg.type == MessageType.TTS_STOP
        msg = TTSStopMessage.from_payload(ipc_msg.payload)
        assert msg is not None

    def test_tts_status_from_raw_json(self):
        """Test deserializing tts_status from raw JSON string."""
        json_str = json.dumps({
            "type": "tts_status",
            "payload": {
                "state": "generating",
                "text": "Processing text",
                "elapsed": 1.5,
                "error": None,
            }
        })

        ipc_msg = IPCMessage.from_json(json_str)

        assert ipc_msg.type == MessageType.TTS_STATUS
        msg = TTSStatusMessage.from_payload(ipc_msg.payload)
        assert msg.state == "generating"
        assert msg.elapsed == 1.5

    def test_tts_set_voice_from_raw_json(self):
        """Test deserializing tts_set_voice from raw JSON string."""
        json_str = json.dumps({
            "type": "tts_set_voice",
            "payload": {
                "preset_name": "english_male",
            }
        })

        ipc_msg = IPCMessage.from_json(json_str)

        assert ipc_msg.type == MessageType.TTS_SET_VOICE
        msg = TTSSetVoiceMessage.from_payload(ipc_msg.payload)
        assert msg.preset_name == "english_male"

    def test_tts_voice_config_from_raw_json(self):
        """Test deserializing tts_voice_config from raw JSON string."""
        json_str = json.dumps({
            "type": "tts_voice_config",
            "payload": {
                "language": "Korean",
                "voice_instruct": "A Korean voice.",
                "preset_name": "korean_female",
                "available_presets": ["korean_female", "korean_male"],
            }
        })

        ipc_msg = IPCMessage.from_json(json_str)

        assert ipc_msg.type == MessageType.TTS_VOICE_CONFIG
        msg = TTSVoiceConfigMessage.from_payload(ipc_msg.payload)
        assert msg.language == "Korean"
        assert msg.preset_name == "korean_female"
        assert len(msg.available_presets) == 2


class TestTTSPreloadMessage:
    """Tests for TTSPreloadMessage.

    Validates the TTS preload request message that warms up the TTS model
    when entering Reading Mode, avoiding delay on first speak request.
    """

    def test_tts_preload_enum_value(self):
        """Test TTS_PRELOAD enum has correct string value."""
        assert MessageType.TTS_PRELOAD == "tts_preload"
        assert MessageType.TTS_PRELOAD.value == "tts_preload"

    def test_from_payload(self):
        """Test creating TTSPreloadMessage from payload."""
        from ipc.protocol import TTSPreloadMessage

        payload = {}
        msg = TTSPreloadMessage.from_payload(payload)
        assert msg is not None

    def test_to_ipc_message(self):
        """Test TTSPreloadMessage to IPCMessage conversion."""
        from ipc.protocol import TTSPreloadMessage

        preload_msg = TTSPreloadMessage()
        ipc_msg = preload_msg.to_ipc_message()

        assert ipc_msg.type == MessageType.TTS_PRELOAD
        assert ipc_msg.payload == {}

    def test_tts_preload_roundtrip(self):
        """Test TTSPreloadMessage survives roundtrip serialization."""
        from ipc.protocol import TTSPreloadMessage

        original = TTSPreloadMessage()
        ipc_msg = original.to_ipc_message()
        json_str = ipc_msg.to_json()
        restored_ipc = IPCMessage.from_json(json_str)

        assert restored_ipc.type == MessageType.TTS_PRELOAD
        restored = TTSPreloadMessage.from_payload(restored_ipc.payload)
        assert restored is not None

    def test_tts_preload_from_raw_json(self):
        """Test deserializing tts_preload from raw JSON string."""
        from ipc.protocol import TTSPreloadMessage

        json_str = json.dumps({
            "type": "tts_preload",
            "payload": {}
        })

        ipc_msg = IPCMessage.from_json(json_str)

        assert ipc_msg.type == MessageType.TTS_PRELOAD
        msg = TTSPreloadMessage.from_payload(ipc_msg.payload)
        assert msg is not None
