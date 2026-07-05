"""
Tests for TTS Service Module (Task 21.3)

Tests for TTSService and TTSStatus dataclass.
All tests are designed to FAIL until implementation exists.

Feature: dev-echo-phase2, Property 16: TTS Playback Lifecycle
Feature: dev-echo-phase2, Property 17: TTS Configuration Persistence
"""

import pytest
from unittest.mock import Mock, patch, AsyncMock, MagicMock, PropertyMock
import time

from tts import (
    TTSService,
    TTSStatus,
    TTSEngine,
    TTSEngineState,
    VoiceConfig,
    VOICE_PRESETS,
)


# ---------------------------------------------------------------------------
# Task 21.3: TTSStatus dataclass
# ---------------------------------------------------------------------------


class TestTTSStatus:
    """Tests for TTSStatus dataclass."""

    def test_creation_with_all_fields(self):
        """TTSStatus should store state, text, elapsed, and error."""
        status = TTSStatus(
            state="generating",
            text="Hello world",
            elapsed=1.5,
            error=None,
        )
        assert status.state == "generating"
        assert status.text == "Hello world"
        assert status.elapsed == 1.5
        assert status.error is None

    def test_creation_with_defaults(self):
        """TTSStatus should have sensible defaults for optional fields."""
        status = TTSStatus(state="idle")
        assert status.state == "idle"
        assert status.text is None
        assert status.elapsed is None
        assert status.error is None

    def test_creation_with_error(self):
        """TTSStatus should store error messages."""
        status = TTSStatus(
            state="idle",
            error="Model failed to load",
        )
        assert status.error == "Model failed to load"

    def test_state_reflects_engine_state_values(self):
        """TTSStatus.state should accept all TTSEngineState string values."""
        for state_enum in TTSEngineState:
            status = TTSStatus(state=state_enum.value)
            assert status.state == state_enum.value


# ---------------------------------------------------------------------------
# Task 21.3: TTSService - initialization
# ---------------------------------------------------------------------------


class TestTTSServiceInit:
    """Tests for TTSService initialization."""

    def test_initializes_without_engine(self):
        """TTSService should start with no engine (lazy init)."""
        service = TTSService()
        assert service._engine is None

    def test_accepts_status_callback(self):
        """TTSService should accept a status_callback parameter."""
        callback = Mock()
        service = TTSService(status_callback=callback)
        assert service._status_callback is callback

    def test_no_status_callback_by_default(self):
        """TTSService status_callback should default to None."""
        service = TTSService()
        assert service._status_callback is None


# ---------------------------------------------------------------------------
# Task 21.3: TTSService - speak()
# ---------------------------------------------------------------------------


class TestTTSServiceSpeak:
    """Tests for TTSService.speak() method."""

    @pytest.mark.asyncio
    async def test_speak_creates_engine_on_first_call(self):
        """speak() should create TTSEngine on first call (lazy init)."""
        service = TTSService()
        assert service._engine is None

        with patch("tts.service.TTSEngine") as MockEngine:
            mock_engine_instance = MagicMock()
            mock_engine_instance.speak = AsyncMock()
            MockEngine.return_value = mock_engine_instance

            await service.speak("Hello")

            MockEngine.assert_called_once()
            assert service._engine is mock_engine_instance

    @pytest.mark.asyncio
    async def test_speak_reuses_engine_on_subsequent_calls(self):
        """speak() should reuse the same engine on subsequent calls."""
        service = TTSService()

        with patch("tts.service.TTSEngine") as MockEngine:
            mock_engine_instance = MagicMock()
            mock_engine_instance.speak = AsyncMock()
            MockEngine.return_value = mock_engine_instance

            await service.speak("First")
            await service.speak("Second")

            # Engine should be created only once
            MockEngine.assert_called_once()
            assert mock_engine_instance.speak.call_count == 2

    @pytest.mark.asyncio
    async def test_speak_delegates_to_engine(self):
        """speak() should delegate to engine.speak() with the text."""
        service = TTSService()

        with patch("tts.service.TTSEngine") as MockEngine:
            mock_engine_instance = MagicMock()
            mock_engine_instance.speak = AsyncMock()
            MockEngine.return_value = mock_engine_instance

            await service.speak("Read this text")

            mock_engine_instance.speak.assert_called_once_with("Read this text")

    @pytest.mark.asyncio
    async def test_speak_records_start_time(self):
        """speak() should record the start time for elapsed calculation."""
        service = TTSService()

        with patch("tts.service.TTSEngine") as MockEngine:
            mock_engine_instance = MagicMock()
            mock_engine_instance.speak = AsyncMock()
            MockEngine.return_value = mock_engine_instance

            before = time.time()
            await service.speak("Hello")
            after = time.time()

            assert service._speak_start_time is not None
            assert before <= service._speak_start_time <= after


# ---------------------------------------------------------------------------
# Task 21.3: TTSService - stop_speech()
# ---------------------------------------------------------------------------


class TestTTSServiceStop:
    """Tests for TTSService.stop_speech() method."""

    @pytest.mark.asyncio
    async def test_stop_speech_delegates_to_engine(self):
        """stop_speech() should delegate to engine.stop()."""
        service = TTSService()
        mock_engine = MagicMock()
        mock_engine.stop = AsyncMock()
        service._engine = mock_engine

        await service.stop_speech()

        mock_engine.stop.assert_called_once()

    @pytest.mark.asyncio
    async def test_stop_speech_when_no_engine(self):
        """stop_speech() should be safe to call when no engine exists."""
        service = TTSService()
        assert service._engine is None
        # Should not raise
        await service.stop_speech()

    @pytest.mark.asyncio
    async def test_stop_speech_clears_start_time(self):
        """stop_speech() should clear _speak_start_time."""
        service = TTSService()
        service._speak_start_time = time.time()
        mock_engine = MagicMock()
        mock_engine.stop = AsyncMock()
        service._engine = mock_engine

        await service.stop_speech()

        assert service._speak_start_time is None


# ---------------------------------------------------------------------------
# Task 21.3: TTSService - get_status()
# ---------------------------------------------------------------------------


class TestTTSServiceGetStatus:
    """Tests for TTSService.get_status() method."""

    def test_get_status_returns_tts_status(self):
        """get_status() should return a TTSStatus instance."""
        service = TTSService()
        status = service.get_status()
        assert isinstance(status, TTSStatus)

    def test_get_status_idle_when_no_engine(self):
        """get_status() should return idle state when no engine exists."""
        service = TTSService()
        status = service.get_status()
        assert status.state == "idle"

    def test_get_status_reflects_engine_state(self):
        """get_status() should reflect the engine's current state."""
        service = TTSService()
        mock_engine = MagicMock()
        mock_engine.state = TTSEngineState.GENERATING
        service._engine = mock_engine

        status = service.get_status()
        assert status.state == "generating"

    def test_get_status_includes_elapsed_time(self):
        """get_status() should include elapsed time when speaking."""
        service = TTSService()
        mock_engine = MagicMock()
        mock_engine.state = TTSEngineState.PLAYING
        service._engine = mock_engine
        service._speak_start_time = time.time() - 5.0  # 5 seconds ago

        status = service.get_status()
        assert status.elapsed is not None
        assert status.elapsed >= 4.5  # Allow some timing slack


# ---------------------------------------------------------------------------
# Task 21.3: TTSService - get_voice_config()
# ---------------------------------------------------------------------------


class TestTTSServiceGetVoiceConfig:
    """Tests for TTSService.get_voice_config() method."""

    def test_get_voice_config_returns_dict(self):
        """get_voice_config() should return a dict with config fields."""
        service = TTSService()
        config = service.get_voice_config()
        assert isinstance(config, dict)

    def test_get_voice_config_has_language(self):
        """get_voice_config() dict should include 'language' key."""
        service = TTSService()
        config = service.get_voice_config()
        assert "language" in config

    def test_get_voice_config_has_voice_instruct(self):
        """get_voice_config() dict should include 'voice_instruct' key."""
        service = TTSService()
        config = service.get_voice_config()
        assert "voice_instruct" in config

    def test_get_voice_config_default_is_korean_female(self):
        """Default voice config should match korean_female preset."""
        service = TTSService()
        config = service.get_voice_config()
        expected = VOICE_PRESETS["korean_female"]
        assert config["language"] == expected.language
        assert config["voice_instruct"] == expected.voice_instruct

    def test_get_voice_config_delegates_to_engine(self):
        """get_voice_config() should use engine config if engine exists."""
        service = TTSService()
        mock_engine = MagicMock()
        mock_engine.get_voice_config.return_value = VoiceConfig(
            language="English",
            voice_instruct="A clear voice",
        )
        service._engine = mock_engine

        config = service.get_voice_config()
        assert config["language"] == "English"
        assert config["voice_instruct"] == "A clear voice"


# ---------------------------------------------------------------------------
# Task 21.3: TTSService - set_preset()
# ---------------------------------------------------------------------------


class TestTTSServiceSetPreset:
    """Tests for TTSService.set_preset() method."""

    def test_set_preset_valid_returns_true(self):
        """set_preset() with a valid preset name should return True."""
        service = TTSService()
        result = service.set_preset("korean_female")
        assert result is True

    def test_set_preset_invalid_returns_false(self):
        """set_preset() with an invalid preset name should return False."""
        service = TTSService()
        result = service.set_preset("nonexistent_voice")
        assert result is False

    def test_set_preset_updates_engine_config(self):
        """set_preset() should update the engine's voice config."""
        service = TTSService()
        mock_engine = MagicMock()
        service._engine = mock_engine

        service.set_preset("english_male")

        mock_engine.set_voice_config.assert_called_once()
        passed_config = mock_engine.set_voice_config.call_args[0][0]
        assert passed_config.language == "English"

    def test_set_preset_all_valid_presets(self):
        """set_preset() should accept all four preset names."""
        service = TTSService()
        for name in ("korean_female", "korean_male", "english_female", "english_male"):
            result = service.set_preset(name)
            assert result is True, f"Preset '{name}' should be valid"

    def test_set_preset_empty_string_returns_false(self):
        """set_preset() with empty string should return False."""
        service = TTSService()
        result = service.set_preset("")
        assert result is False

    def test_set_preset_case_sensitive(self):
        """set_preset() should be case-sensitive (preset names are lowercase)."""
        service = TTSService()
        result = service.set_preset("Korean_Female")
        assert result is False

    def test_set_preset_works_without_engine(self):
        """set_preset() should work even before engine is created.

        The preset should be stored and applied when engine is created.
        """
        service = TTSService()
        assert service._engine is None
        result = service.set_preset("english_female")
        assert result is True


# ---------------------------------------------------------------------------
# Task 21.3: TTSService - list_presets()
# ---------------------------------------------------------------------------


class TestTTSServiceListPresets:
    """Tests for TTSService.list_presets() method."""

    def test_list_presets_returns_list(self):
        """list_presets() should return a list."""
        service = TTSService()
        presets = service.list_presets()
        assert isinstance(presets, list)

    def test_list_presets_contains_all_four(self):
        """list_presets() should contain all four preset names."""
        service = TTSService()
        presets = service.list_presets()
        assert set(presets) == {"korean_female", "korean_male", "english_female", "english_male"}

    def test_list_presets_returns_strings(self):
        """list_presets() should return a list of strings."""
        service = TTSService()
        presets = service.list_presets()
        for p in presets:
            assert isinstance(p, str)


# ---------------------------------------------------------------------------
# Task 21.3: TTSService - shutdown()
# ---------------------------------------------------------------------------


class TestTTSServiceShutdown:
    """Tests for TTSService.shutdown() method."""

    @pytest.mark.asyncio
    async def test_shutdown_delegates_to_engine(self):
        """shutdown() should call engine.shutdown()."""
        service = TTSService()
        mock_engine = MagicMock()
        mock_engine.shutdown = AsyncMock()
        service._engine = mock_engine

        await service.shutdown()

        mock_engine.shutdown.assert_called_once()

    @pytest.mark.asyncio
    async def test_shutdown_safe_when_no_engine(self):
        """shutdown() should be safe to call when no engine exists."""
        service = TTSService()
        assert service._engine is None
        # Should not raise
        await service.shutdown()


# ---------------------------------------------------------------------------
# Task 21.3: TTSService - status callback
# ---------------------------------------------------------------------------


class TestTTSServiceStatusCallback:
    """Tests for TTSService status_callback integration."""

    @pytest.mark.asyncio
    async def test_engine_status_propagates_to_service_callback(self):
        """When engine reports a status change, service callback should fire."""
        service_callback = Mock()
        service = TTSService(status_callback=service_callback)

        # Simulate engine creation with the service's internal callback
        with patch("tts.service.TTSEngine") as MockEngine:
            mock_engine_instance = MagicMock()
            mock_engine_instance.speak = AsyncMock()

            def capture_callback(**kwargs):
                # Store the status_callback passed to TTSEngine
                captured = kwargs.get("status_callback")
                mock_engine_instance._captured_callback = captured
                return mock_engine_instance

            MockEngine.side_effect = capture_callback

            await service.speak("trigger engine creation")

            # The engine should have been given a callback
            MockEngine.assert_called_once()
            call_kwargs = MockEngine.call_args[1] if MockEngine.call_args[1] else {}
            assert "status_callback" in call_kwargs or len(MockEngine.call_args[0]) > 0

    def test_on_engine_status_calls_service_callback(self):
        """_on_engine_status() should invoke service's status_callback with TTSStatus."""
        service_callback = Mock()
        service = TTSService(status_callback=service_callback)

        service._on_engine_status(TTSEngineState.GENERATING)

        service_callback.assert_called_once()
        status_arg = service_callback.call_args[0][0]
        assert isinstance(status_arg, TTSStatus)
        assert status_arg.state == "generating"

    def test_on_engine_status_includes_elapsed(self):
        """_on_engine_status() should include elapsed time when speaking."""
        service_callback = Mock()
        service = TTSService(status_callback=service_callback)
        service._speak_start_time = time.time() - 3.0  # 3 seconds ago

        service._on_engine_status(TTSEngineState.PLAYING)

        status_arg = service_callback.call_args[0][0]
        assert status_arg.elapsed is not None
        assert status_arg.elapsed >= 2.5  # Allow timing slack

    def test_on_engine_status_no_callback_no_error(self):
        """_on_engine_status() without callback should not raise."""
        service = TTSService()
        # Should not raise
        service._on_engine_status(TTSEngineState.IDLE)
