"""
Tests for Task 23: Backend TTS Integration

Tests IPC Server TTS handler registration + message routing (Task 23.1)
and DevEchoBackend TTS service wiring (Task 23.2).

All tests are designed to FAIL because:
  - IPCServer does not yet have on_tts_speak(), on_tts_stop(), on_tts_set_voice(),
    send_tts_status(), or send_tts_voice_config() methods.
  - IPCServer._process_message() does not yet route TTS_SPEAK, TTS_STOP,
    or TTS_SET_VOICE messages.
  - DevEchoBackend does not yet have _tts_service, _init_tts_service(),
    or TTS handler registration / shutdown logic.

Feature: dev-echo-phase2, Property 16: TTS Playback Lifecycle
Feature: dev-echo-phase2, Property 17: TTS Configuration Persistence
"""

import asyncio
import pytest
from unittest.mock import AsyncMock, MagicMock, Mock, patch

from ipc.server import IPCServer
from ipc.protocol import (
    MessageType,
    IPCMessage,
    TTSSpeakMessage,
    TTSStopMessage,
    TTSStatusMessage,
    TTSSetVoiceMessage,
    TTSVoiceConfigMessage,
)


# ===========================================================================
# Task 23.1: IPC Server TTS Handler Registration
# ===========================================================================


class TestIPCServerTTSHandlerRegistration:
    """Tests for TTS handler registration methods on IPCServer.

    The IPCServer should expose on_tts_speak(), on_tts_stop(), and
    on_tts_set_voice() methods that follow the same pattern as existing
    handler registration methods (on_audio_data, on_llm_query, etc.).

    These tests will FAIL with AttributeError because the methods do not
    exist yet on IPCServer.
    """

    def test_on_tts_speak_stores_handler(self):
        """on_tts_speak() should store the handler callable on the server."""
        server = IPCServer(socket_path="/tmp/test_tts.sock")
        handler = AsyncMock()

        server.on_tts_speak(handler)

        assert server._tts_speak_handler is handler

    def test_on_tts_stop_stores_handler(self):
        """on_tts_stop() should store the handler callable on the server."""
        server = IPCServer(socket_path="/tmp/test_tts.sock")
        handler = AsyncMock()

        server.on_tts_stop(handler)

        assert server._tts_stop_handler is handler

    def test_on_tts_set_voice_stores_handler(self):
        """on_tts_set_voice() should store the handler callable on the server."""
        server = IPCServer(socket_path="/tmp/test_tts.sock")
        handler = AsyncMock()

        server.on_tts_set_voice(handler)

        assert server._tts_set_voice_handler is handler

    def test_tts_speak_handler_initially_none(self):
        """_tts_speak_handler should be None before registration."""
        server = IPCServer(socket_path="/tmp/test_tts.sock")

        assert server._tts_speak_handler is None

    def test_tts_stop_handler_initially_none(self):
        """_tts_stop_handler should be None before registration."""
        server = IPCServer(socket_path="/tmp/test_tts.sock")

        assert server._tts_stop_handler is None

    def test_tts_set_voice_handler_initially_none(self):
        """_tts_set_voice_handler should be None before registration."""
        server = IPCServer(socket_path="/tmp/test_tts.sock")

        assert server._tts_set_voice_handler is None

    def test_on_tts_speak_replaces_previous_handler(self):
        """Calling on_tts_speak() twice should replace the first handler."""
        server = IPCServer(socket_path="/tmp/test_tts.sock")
        handler_a = AsyncMock()
        handler_b = AsyncMock()

        server.on_tts_speak(handler_a)
        server.on_tts_speak(handler_b)

        assert server._tts_speak_handler is handler_b

    def test_on_tts_stop_replaces_previous_handler(self):
        """Calling on_tts_stop() twice should replace the first handler."""
        server = IPCServer(socket_path="/tmp/test_tts.sock")
        handler_a = AsyncMock()
        handler_b = AsyncMock()

        server.on_tts_stop(handler_a)
        server.on_tts_stop(handler_b)

        assert server._tts_stop_handler is handler_b

    def test_on_tts_set_voice_replaces_previous_handler(self):
        """Calling on_tts_set_voice() twice should replace the first handler."""
        server = IPCServer(socket_path="/tmp/test_tts.sock")
        handler_a = AsyncMock()
        handler_b = AsyncMock()

        server.on_tts_set_voice(handler_a)
        server.on_tts_set_voice(handler_b)

        assert server._tts_set_voice_handler is handler_b


# ===========================================================================
# Task 23.1: IPC Server TTS Message Routing
# ===========================================================================


class TestIPCServerTTSMessageRouting:
    """Tests for TTS message routing in IPCServer._process_message().

    The _process_message() method should recognize TTS_SPEAK, TTS_STOP,
    and TTS_SET_VOICE message types and dispatch them to the registered
    handler callables.

    These tests will FAIL because _process_message() does not yet have
    TTS routing branches.
    """

    @pytest.fixture
    def server(self):
        """Create an IPCServer for testing."""
        return IPCServer(socket_path="/tmp/test_tts_routing.sock")

    @pytest.fixture
    def mock_writer(self):
        """Create a mock StreamWriter for response sending."""
        writer = MagicMock()
        writer.write = MagicMock()
        writer.drain = AsyncMock()
        return writer

    @pytest.mark.asyncio
    async def test_routes_tts_speak_to_handler(self, server, mock_writer):
        """TTS_SPEAK message should be routed to the registered handler."""
        handler = AsyncMock()
        server.on_tts_speak(handler)

        message = IPCMessage(
            type=MessageType.TTS_SPEAK,
            payload={"text": "Hello world", "language": "English"},
        )

        await server._process_message(message, mock_writer)

        handler.assert_called_once()
        # The handler should receive a TTSSpeakMessage
        speak_msg = handler.call_args[0][0]
        assert isinstance(speak_msg, TTSSpeakMessage)
        assert speak_msg.text == "Hello world"
        assert speak_msg.language == "English"

    @pytest.mark.asyncio
    async def test_routes_tts_speak_with_korean_text(self, server, mock_writer):
        """TTS_SPEAK should correctly pass Korean text to handler."""
        handler = AsyncMock()
        server.on_tts_speak(handler)

        message = IPCMessage(
            type=MessageType.TTS_SPEAK,
            payload={"text": "안녕하세요", "language": "Korean"},
        )

        await server._process_message(message, mock_writer)

        speak_msg = handler.call_args[0][0]
        assert speak_msg.text == "안녕하세요"
        assert speak_msg.language == "Korean"

    @pytest.mark.asyncio
    async def test_routes_tts_speak_without_language(self, server, mock_writer):
        """TTS_SPEAK with no language should still route correctly."""
        handler = AsyncMock()
        server.on_tts_speak(handler)

        message = IPCMessage(
            type=MessageType.TTS_SPEAK,
            payload={"text": "No language specified"},
        )

        await server._process_message(message, mock_writer)

        speak_msg = handler.call_args[0][0]
        assert speak_msg.text == "No language specified"
        assert speak_msg.language is None

    @pytest.mark.asyncio
    async def test_routes_tts_stop_to_handler(self, server, mock_writer):
        """TTS_STOP message should be routed to the registered handler."""
        handler = AsyncMock()
        server.on_tts_stop(handler)

        message = IPCMessage(
            type=MessageType.TTS_STOP,
            payload={},
        )

        await server._process_message(message, mock_writer)

        handler.assert_called_once()

    @pytest.mark.asyncio
    async def test_routes_tts_set_voice_to_handler(self, server, mock_writer):
        """TTS_SET_VOICE message should be routed to the registered handler."""
        handler = AsyncMock()
        server.on_tts_set_voice(handler)

        message = IPCMessage(
            type=MessageType.TTS_SET_VOICE,
            payload={"preset_name": "english_male"},
        )

        await server._process_message(message, mock_writer)

        handler.assert_called_once()
        # The handler should receive a TTSSetVoiceMessage
        set_voice_msg = handler.call_args[0][0]
        assert isinstance(set_voice_msg, TTSSetVoiceMessage)
        assert set_voice_msg.preset_name == "english_male"

    @pytest.mark.asyncio
    async def test_tts_set_voice_sends_response(self, server, mock_writer):
        """TTS_SET_VOICE handler response should be sent back to the client.

        When the handler returns a TTSVoiceConfigMessage, the server should
        write that response to the client writer.
        """
        voice_config_response = TTSVoiceConfigMessage(
            language="English",
            voice_instruct="A deep male English voice",
            preset_name="english_male",
            available_presets=["korean_female", "korean_male", "english_female", "english_male"],
        )

        handler = AsyncMock(return_value=voice_config_response)
        server.on_tts_set_voice(handler)

        message = IPCMessage(
            type=MessageType.TTS_SET_VOICE,
            payload={"preset_name": "english_male"},
        )

        await server._process_message(message, mock_writer)

        # The response should be written to the client
        mock_writer.write.assert_called()
        mock_writer.drain.assert_called()

        # Verify the response content
        written_data = mock_writer.write.call_args[0][0]
        assert b"tts_voice_config" in written_data

    @pytest.mark.asyncio
    async def test_tts_speak_without_handler_does_not_crash(self, server, mock_writer):
        """TTS_SPEAK without a registered handler should not raise."""
        # Do NOT register any handler
        message = IPCMessage(
            type=MessageType.TTS_SPEAK,
            payload={"text": "Hello", "language": None},
        )

        # Should not raise
        await server._process_message(message, mock_writer)

    @pytest.mark.asyncio
    async def test_tts_stop_without_handler_does_not_crash(self, server, mock_writer):
        """TTS_STOP without a registered handler should not raise."""
        message = IPCMessage(
            type=MessageType.TTS_STOP,
            payload={},
        )

        # Should not raise
        await server._process_message(message, mock_writer)

    @pytest.mark.asyncio
    async def test_tts_set_voice_without_handler_does_not_crash(self, server, mock_writer):
        """TTS_SET_VOICE without a registered handler should not raise."""
        message = IPCMessage(
            type=MessageType.TTS_SET_VOICE,
            payload={"preset_name": "korean_female"},
        )

        # Should not raise
        await server._process_message(message, mock_writer)


# ===========================================================================
# Task 23.1: IPC Server TTS Broadcast Methods
# ===========================================================================


class TestIPCServerTTSBroadcast:
    """Tests for TTS broadcast methods on IPCServer.

    send_tts_status() and send_tts_voice_config() should broadcast
    messages to all connected clients, following the same pattern as
    the existing send_transcription() method.

    These tests will FAIL with AttributeError because the methods
    do not exist yet.
    """

    @pytest.mark.asyncio
    async def test_send_tts_status_broadcasts_to_clients(self):
        """send_tts_status() should broadcast TTSStatusMessage to all clients."""
        server = IPCServer(socket_path="/tmp/test_tts_broadcast.sock")

        # Mock the broadcast method
        server.broadcast = AsyncMock()

        status_msg = TTSStatusMessage(
            state="playing",
            text="Hello world",
            elapsed=2.5,
            error=None,
        )

        await server.send_tts_status(status_msg)

        server.broadcast.assert_called_once()
        # Verify the broadcast argument is an IPCMessage
        broadcast_arg = server.broadcast.call_args[0][0]
        assert isinstance(broadcast_arg, IPCMessage)
        assert broadcast_arg.type == MessageType.TTS_STATUS
        assert broadcast_arg.payload["state"] == "playing"
        assert broadcast_arg.payload["text"] == "Hello world"
        assert broadcast_arg.payload["elapsed"] == 2.5

    @pytest.mark.asyncio
    async def test_send_tts_status_with_error(self):
        """send_tts_status() should broadcast error state correctly."""
        server = IPCServer(socket_path="/tmp/test_tts_broadcast2.sock")
        server.broadcast = AsyncMock()

        status_msg = TTSStatusMessage(
            state="idle",
            text=None,
            elapsed=None,
            error="Model failed to load",
        )

        await server.send_tts_status(status_msg)

        broadcast_arg = server.broadcast.call_args[0][0]
        assert broadcast_arg.payload["state"] == "idle"
        assert broadcast_arg.payload["error"] == "Model failed to load"

    @pytest.mark.asyncio
    async def test_send_tts_status_with_all_engine_states(self):
        """send_tts_status() should work with all valid engine states."""
        server = IPCServer(socket_path="/tmp/test_tts_broadcast3.sock")
        server.broadcast = AsyncMock()

        states = ["idle", "loading_model", "generating", "playing", "stopping"]
        for state in states:
            server.broadcast.reset_mock()
            status_msg = TTSStatusMessage(state=state)
            await server.send_tts_status(status_msg)
            server.broadcast.assert_called_once()

    @pytest.mark.asyncio
    async def test_send_tts_voice_config_broadcasts_to_clients(self):
        """send_tts_voice_config() should broadcast TTSVoiceConfigMessage."""
        server = IPCServer(socket_path="/tmp/test_tts_broadcast4.sock")
        server.broadcast = AsyncMock()

        config_msg = TTSVoiceConfigMessage(
            language="Korean",
            voice_instruct="A young Korean female voice, clear and natural.",
            preset_name="korean_female",
            available_presets=["korean_female", "korean_male", "english_female", "english_male"],
        )

        await server.send_tts_voice_config(config_msg)

        server.broadcast.assert_called_once()
        broadcast_arg = server.broadcast.call_args[0][0]
        assert isinstance(broadcast_arg, IPCMessage)
        assert broadcast_arg.type == MessageType.TTS_VOICE_CONFIG
        assert broadcast_arg.payload["language"] == "Korean"
        assert broadcast_arg.payload["preset_name"] == "korean_female"
        assert len(broadcast_arg.payload["available_presets"]) == 4

    @pytest.mark.asyncio
    async def test_send_tts_voice_config_minimal(self):
        """send_tts_voice_config() should work with minimal config data."""
        server = IPCServer(socket_path="/tmp/test_tts_broadcast5.sock")
        server.broadcast = AsyncMock()

        config_msg = TTSVoiceConfigMessage(
            language="English",
            voice_instruct="A clear English voice.",
            preset_name=None,
            available_presets=None,
        )

        await server.send_tts_voice_config(config_msg)

        broadcast_arg = server.broadcast.call_args[0][0]
        assert broadcast_arg.payload["language"] == "English"
        assert broadcast_arg.payload["preset_name"] is None

    @pytest.mark.asyncio
    async def test_send_tts_status_uses_to_ipc_message(self):
        """send_tts_status() should use TTSStatusMessage.to_ipc_message() for conversion.

        This ensures the broadcast uses the same serialization path as other messages.
        """
        server = IPCServer(socket_path="/tmp/test_tts_broadcast6.sock")
        server.broadcast = AsyncMock()

        status_msg = TTSStatusMessage(
            state="generating",
            text="Some text",
            elapsed=1.0,
        )

        await server.send_tts_status(status_msg)

        # The argument to broadcast should equal status_msg.to_ipc_message()
        expected_ipc = status_msg.to_ipc_message()
        actual_ipc = server.broadcast.call_args[0][0]
        assert actual_ipc.type == expected_ipc.type
        assert actual_ipc.payload == expected_ipc.payload


# ===========================================================================
# Task 23.2: DevEchoBackend TTS Service Wiring
# ===========================================================================


class TestDevEchoBackendTTSWiring:
    """Tests for TTS service wiring in DevEchoBackend (backend/main.py).

    DevEchoBackend should:
    - Have a _tts_service attribute
    - Create TTSService in _init_tts_service() method
    - Always initialize TTS (not gated by AWS config)
    - Register TTS handlers with IPC server during start()
    - Shut down TTS service during stop()
    - Wire status callback so TTSService changes broadcast via IPC

    These tests will FAIL because the TTS wiring has not been
    implemented in DevEchoBackend yet.
    """

    @pytest.fixture
    def mock_dependencies(self):
        """Patch all heavyweight dependencies to avoid real service init."""
        with patch("main.TranscriptionService") as mock_ts, \
             patch("main.LLMService") as mock_llm, \
             patch("main.KnowledgeBaseManager") as mock_kb, \
             patch("main.IPCServer") as mock_ipc:

            mock_ts_instance = MagicMock()
            mock_ts_instance.start = AsyncMock()
            mock_ts_instance.stop = AsyncMock()
            mock_ts_instance.set_transcription_callback = MagicMock()
            mock_ts.return_value = mock_ts_instance

            mock_llm_instance = MagicMock()
            mock_llm_instance.start = AsyncMock()
            mock_llm_instance.stop = AsyncMock()
            mock_llm.return_value = mock_llm_instance

            mock_kb.return_value = MagicMock()

            mock_ipc_instance = MagicMock()
            mock_ipc_instance.start = AsyncMock()
            mock_ipc_instance.stop = AsyncMock()
            mock_ipc_instance.broadcast = AsyncMock()
            mock_ipc_instance.on_audio_data = MagicMock()
            mock_ipc_instance.on_llm_query = MagicMock()
            mock_ipc_instance.on_kb_list = MagicMock()
            mock_ipc_instance.on_kb_add = MagicMock()
            mock_ipc_instance.on_kb_update = MagicMock()
            mock_ipc_instance.on_kb_remove = MagicMock()
            mock_ipc_instance.on_tts_speak = MagicMock()
            mock_ipc_instance.on_tts_stop = MagicMock()
            mock_ipc_instance.on_tts_set_voice = MagicMock()
            mock_ipc_instance.send_tts_status = AsyncMock()
            mock_ipc.return_value = mock_ipc_instance

            yield {
                "TranscriptionService": mock_ts,
                "LLMService": mock_llm,
                "KnowledgeBaseManager": mock_kb,
                "IPCServer": mock_ipc,
                "ipc_server": mock_ipc_instance,
                "transcription_service": mock_ts_instance,
                "llm_service": mock_llm_instance,
            }

    def _create_backend(self, mock_deps):
        """Create a DevEchoBackend with all dependencies mocked.

        Import is done inside the function to ensure patches are active.
        """
        from main import DevEchoBackend
        backend = DevEchoBackend(socket_path="/tmp/test_tts_backend.sock")
        return backend

    def test_backend_has_tts_service_attribute(self, mock_dependencies):
        """DevEchoBackend should have a _tts_service attribute after init."""
        backend = self._create_backend(mock_dependencies)

        # _tts_service should exist (may be None before _init_tts_service)
        assert hasattr(backend, "_tts_service")

    @pytest.mark.asyncio
    async def test_init_tts_service_creates_service(self, mock_dependencies):
        """_init_tts_service() should create a TTSService instance."""
        with patch("main.TTSService") as MockTTSService:
            mock_tts_instance = MagicMock()
            MockTTSService.return_value = mock_tts_instance

            backend = self._create_backend(mock_dependencies)
            backend._init_tts_service()

            MockTTSService.assert_called_once()
            assert backend._tts_service is mock_tts_instance

    @pytest.mark.asyncio
    async def test_init_tts_service_passes_status_callback(self, mock_dependencies):
        """_init_tts_service() should pass a status_callback to TTSService.

        The callback should eventually broadcast status changes via IPC.
        """
        with patch("main.TTSService") as MockTTSService:
            mock_tts_instance = MagicMock()
            MockTTSService.return_value = mock_tts_instance

            backend = self._create_backend(mock_dependencies)
            backend._init_tts_service()

            # TTSService constructor should have been called with status_callback
            call_kwargs = MockTTSService.call_args
            # Check either positional or keyword argument
            has_callback = (
                (call_kwargs[1] and "status_callback" in call_kwargs[1])
                or (call_kwargs[0] and len(call_kwargs[0]) > 0)
            )
            assert has_callback, (
                "TTSService should be constructed with a status_callback parameter"
            )

    @pytest.mark.asyncio
    async def test_start_calls_init_tts_service(self, mock_dependencies):
        """start() should call _init_tts_service() to create the TTS service.

        TTS initialization should NOT be gated by AWS config; it should
        always be called.
        """
        with patch("main.TTSService") as MockTTSService:
            mock_tts_instance = MagicMock()
            mock_tts_instance.shutdown = AsyncMock()
            MockTTSService.return_value = mock_tts_instance

            backend = self._create_backend(mock_dependencies)

            # Ensure Phase 2 is disabled so we can verify TTS is still initialized
            with patch.object(backend, "_init_phase2_services", return_value=False):
                await backend.start()

            # TTSService should have been created regardless of AWS config
            MockTTSService.assert_called_once()

    @pytest.mark.asyncio
    async def test_start_registers_tts_handlers(self, mock_dependencies):
        """start() should register TTS handlers with the IPC server."""
        with patch("main.TTSService") as MockTTSService:
            mock_tts_instance = MagicMock()
            mock_tts_instance.shutdown = AsyncMock()
            MockTTSService.return_value = mock_tts_instance

            backend = self._create_backend(mock_dependencies)
            ipc = mock_dependencies["ipc_server"]

            with patch.object(backend, "_init_phase2_services", return_value=False):
                await backend.start()

            # All three TTS handlers should be registered
            ipc.on_tts_speak.assert_called_once()
            ipc.on_tts_stop.assert_called_once()
            ipc.on_tts_set_voice.assert_called_once()

    @pytest.mark.asyncio
    async def test_start_registers_tts_handlers_even_without_aws(self, mock_dependencies):
        """TTS handler registration should happen even when Phase 2 is disabled.

        TTS is always available, unlike Cloud LLM or S3 KB services which
        require AWS configuration.
        """
        with patch("main.TTSService") as MockTTSService:
            mock_tts_instance = MagicMock()
            mock_tts_instance.shutdown = AsyncMock()
            MockTTSService.return_value = mock_tts_instance

            backend = self._create_backend(mock_dependencies)
            ipc = mock_dependencies["ipc_server"]

            # Explicitly disable Phase 2
            with patch.object(backend, "_init_phase2_services", return_value=False):
                await backend.start()

            assert backend._phase2_enabled is False
            ipc.on_tts_speak.assert_called_once()
            ipc.on_tts_stop.assert_called_once()
            ipc.on_tts_set_voice.assert_called_once()

    @pytest.mark.asyncio
    async def test_stop_shuts_down_tts_service(self, mock_dependencies):
        """stop() should call shutdown() on the TTS service."""
        with patch("main.TTSService") as MockTTSService:
            mock_tts_instance = MagicMock()
            mock_tts_instance.shutdown = AsyncMock()
            MockTTSService.return_value = mock_tts_instance

            backend = self._create_backend(mock_dependencies)

            with patch.object(backend, "_init_phase2_services", return_value=False):
                await backend.start()

            await backend.stop()

            mock_tts_instance.shutdown.assert_called_once()

    @pytest.mark.asyncio
    async def test_stop_handles_no_tts_service_gracefully(self, mock_dependencies):
        """stop() should not crash if _tts_service is None."""
        backend = self._create_backend(mock_dependencies)
        backend._tts_service = None

        # Should not raise
        await backend.stop()

    @pytest.mark.asyncio
    async def test_tts_status_callback_broadcasts_via_ipc(self, mock_dependencies):
        """When TTSService status changes, it should broadcast via IPC.

        The status_callback provided to TTSService should convert the
        TTSStatus to a TTSStatusMessage and call send_tts_status() on
        the IPC server.
        """
        captured_callback = None

        with patch("main.TTSService") as MockTTSService:
            def capture_constructor(**kwargs):
                nonlocal captured_callback
                captured_callback = kwargs.get("status_callback")
                return MagicMock(shutdown=AsyncMock())

            MockTTSService.side_effect = capture_constructor

            backend = self._create_backend(mock_dependencies)

            with patch.object(backend, "_init_phase2_services", return_value=False):
                await backend.start()

        # The callback should have been captured
        assert captured_callback is not None, (
            "TTSService should be constructed with a status_callback"
        )

        # Simulate a status change from TTSService
        from tts import TTSStatus
        status = TTSStatus(state="playing", text="Hello", elapsed=1.5)
        ipc = mock_dependencies["ipc_server"]

        # Call the captured callback
        # The callback might be sync or async depending on implementation
        result = captured_callback(status)
        if asyncio.iscoroutine(result):
            await result

        # The IPC server's send_tts_status should have been called
        ipc.send_tts_status.assert_called_once()


# ===========================================================================
# Task 23.2: DevEchoBackend TTS Handler Methods
# ===========================================================================


class TestDevEchoBackendTTSHandlers:
    """Tests for the TTS handler methods wired into DevEchoBackend.

    These methods are registered with the IPC server and invoked when
    the Swift CLI sends TTS messages. They delegate to TTSService.

    These tests will FAIL because the handler methods (_on_tts_speak,
    _on_tts_stop, _on_tts_set_voice) do not exist yet.
    """

    @pytest.fixture
    def mock_dependencies(self):
        """Patch all heavyweight dependencies."""
        with patch("main.TranscriptionService") as mock_ts, \
             patch("main.LLMService") as mock_llm, \
             patch("main.KnowledgeBaseManager") as mock_kb, \
             patch("main.IPCServer") as mock_ipc, \
             patch("main.TTSService") as mock_tts:

            mock_ts_instance = MagicMock()
            mock_ts_instance.start = AsyncMock()
            mock_ts_instance.stop = AsyncMock()
            mock_ts_instance.set_transcription_callback = MagicMock()
            mock_ts.return_value = mock_ts_instance

            mock_llm_instance = MagicMock()
            mock_llm_instance.start = AsyncMock()
            mock_llm_instance.stop = AsyncMock()
            mock_llm.return_value = mock_llm_instance

            mock_kb.return_value = MagicMock()

            mock_ipc_instance = MagicMock()
            mock_ipc_instance.start = AsyncMock()
            mock_ipc_instance.stop = AsyncMock()
            mock_ipc_instance.broadcast = AsyncMock()
            mock_ipc_instance.on_audio_data = MagicMock()
            mock_ipc_instance.on_llm_query = MagicMock()
            mock_ipc_instance.on_kb_list = MagicMock()
            mock_ipc_instance.on_kb_add = MagicMock()
            mock_ipc_instance.on_kb_update = MagicMock()
            mock_ipc_instance.on_kb_remove = MagicMock()
            mock_ipc_instance.on_tts_speak = MagicMock()
            mock_ipc_instance.on_tts_stop = MagicMock()
            mock_ipc_instance.on_tts_set_voice = MagicMock()
            mock_ipc_instance.send_tts_status = AsyncMock()
            mock_ipc_instance.send_tts_voice_config = AsyncMock()
            mock_ipc.return_value = mock_ipc_instance

            mock_tts_instance = MagicMock()
            mock_tts_instance.speak = AsyncMock()
            mock_tts_instance.stop_speech = AsyncMock()
            mock_tts_instance.set_preset = MagicMock(return_value=True)
            mock_tts_instance.get_voice_config = MagicMock(return_value={
                "language": "Korean",
                "voice_instruct": "A young Korean female voice",
            })
            mock_tts_instance.list_presets = MagicMock(
                return_value=["korean_female", "korean_male", "english_female", "english_male"]
            )
            mock_tts_instance.shutdown = AsyncMock()
            mock_tts.return_value = mock_tts_instance

            yield {
                "TranscriptionService": mock_ts,
                "LLMService": mock_llm,
                "KnowledgeBaseManager": mock_kb,
                "IPCServer": mock_ipc,
                "TTSService": mock_tts,
                "ipc_server": mock_ipc_instance,
                "tts_service": mock_tts_instance,
            }

    def _create_backend(self, mock_deps):
        """Create a DevEchoBackend with all dependencies mocked."""
        from main import DevEchoBackend
        return DevEchoBackend(socket_path="/tmp/test_tts_handlers.sock")

    @pytest.mark.asyncio
    async def test_on_tts_speak_delegates_to_service(self, mock_dependencies):
        """_on_tts_speak handler should call tts_service.speak()."""
        backend = self._create_backend(mock_dependencies)
        tts = mock_dependencies["tts_service"]

        with patch.object(backend, "_init_phase2_services", return_value=False):
            await backend.start()

        # Extract the handler that was registered with on_tts_speak
        ipc = mock_dependencies["ipc_server"]
        registered_handler = ipc.on_tts_speak.call_args[0][0]

        speak_msg = TTSSpeakMessage(text="Read this aloud", language="English")
        await registered_handler(speak_msg)

        tts.speak.assert_called_once_with("Read this aloud", "English")

    @pytest.mark.asyncio
    async def test_on_tts_speak_with_none_language(self, mock_dependencies):
        """_on_tts_speak handler should pass None language to service."""
        backend = self._create_backend(mock_dependencies)
        tts = mock_dependencies["tts_service"]

        with patch.object(backend, "_init_phase2_services", return_value=False):
            await backend.start()

        ipc = mock_dependencies["ipc_server"]
        registered_handler = ipc.on_tts_speak.call_args[0][0]

        speak_msg = TTSSpeakMessage(text="No language", language=None)
        await registered_handler(speak_msg)

        tts.speak.assert_called_once_with("No language", None)

    @pytest.mark.asyncio
    async def test_on_tts_stop_delegates_to_service(self, mock_dependencies):
        """_on_tts_stop handler should call tts_service.stop_speech()."""
        backend = self._create_backend(mock_dependencies)
        tts = mock_dependencies["tts_service"]

        with patch.object(backend, "_init_phase2_services", return_value=False):
            await backend.start()

        ipc = mock_dependencies["ipc_server"]
        registered_handler = ipc.on_tts_stop.call_args[0][0]

        stop_msg = TTSStopMessage()
        await registered_handler(stop_msg)

        tts.stop_speech.assert_called_once()

    @pytest.mark.asyncio
    async def test_on_tts_set_voice_delegates_to_service(self, mock_dependencies):
        """_on_tts_set_voice handler should call tts_service.set_preset()."""
        backend = self._create_backend(mock_dependencies)
        tts = mock_dependencies["tts_service"]

        with patch.object(backend, "_init_phase2_services", return_value=False):
            await backend.start()

        ipc = mock_dependencies["ipc_server"]
        registered_handler = ipc.on_tts_set_voice.call_args[0][0]

        set_voice_msg = TTSSetVoiceMessage(preset_name="english_male")
        result = await registered_handler(set_voice_msg)

        tts.set_preset.assert_called_once_with("english_male")

    @pytest.mark.asyncio
    async def test_on_tts_set_voice_returns_voice_config(self, mock_dependencies):
        """_on_tts_set_voice handler should return TTSVoiceConfigMessage."""
        backend = self._create_backend(mock_dependencies)

        with patch.object(backend, "_init_phase2_services", return_value=False):
            await backend.start()

        ipc = mock_dependencies["ipc_server"]
        registered_handler = ipc.on_tts_set_voice.call_args[0][0]

        set_voice_msg = TTSSetVoiceMessage(preset_name="korean_female")
        result = await registered_handler(set_voice_msg)

        # The result should be a TTSVoiceConfigMessage
        assert isinstance(result, TTSVoiceConfigMessage)
        assert result.language == "Korean"
        assert result.available_presets == [
            "korean_female", "korean_male", "english_female", "english_male"
        ]

    @pytest.mark.asyncio
    async def test_on_tts_set_voice_invalid_preset(self, mock_dependencies):
        """_on_tts_set_voice should handle invalid preset names gracefully."""
        backend = self._create_backend(mock_dependencies)
        tts = mock_dependencies["tts_service"]
        tts.set_preset.return_value = False  # Invalid preset

        with patch.object(backend, "_init_phase2_services", return_value=False):
            await backend.start()

        ipc = mock_dependencies["ipc_server"]
        registered_handler = ipc.on_tts_set_voice.call_args[0][0]

        set_voice_msg = TTSSetVoiceMessage(preset_name="nonexistent_voice")
        result = await registered_handler(set_voice_msg)

        # Should still return a response (even if preset was invalid)
        assert result is not None
