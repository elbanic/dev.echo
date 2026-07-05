"""
Tests for TTS Engine Module (Task 21.1 + 21.2)

Tests for TTSEngine, TTSEngineState, VoiceConfig, VOICE_PRESETS,
and TTS exception classes.

All tests are designed to FAIL until implementation exists.
Mock mlx_audio imports since the model won't be available in test.

Feature: dev-echo-phase2, Property 16: TTS Playback Lifecycle
Feature: dev-echo-phase2, Property 17: TTS Configuration Persistence
"""

import pytest
from unittest.mock import Mock, patch, AsyncMock, MagicMock
import threading

from tts import (
    TTSEngine,
    TTSEngineState,
    ModelType,
    VoiceConfig,
    VOICE_PRESETS,
    TTSError,
    ModelInitializationError,
    GenerationError,
    PlaybackError,
)


# ---------------------------------------------------------------------------
# Task 21.1: TTS Exceptions
# ---------------------------------------------------------------------------


class TestTTSExceptions:
    """Tests for TTS exception hierarchy (backend/tts/exceptions.py)."""

    def test_tts_error_is_base_exception(self):
        """TTSError should be a subclass of Exception."""
        error = TTSError("something went wrong")
        assert isinstance(error, Exception)
        assert str(error) == "something went wrong"

    def test_tts_error_default_message(self):
        """TTSError can be instantiated without arguments."""
        error = TTSError()
        assert isinstance(error, Exception)

    def test_model_initialization_error_inherits_tts_error(self):
        """ModelInitializationError should be a subclass of TTSError."""
        error = ModelInitializationError("failed to load model")
        assert isinstance(error, TTSError)
        assert isinstance(error, Exception)
        assert "failed to load model" in str(error)

    def test_model_initialization_error_message(self):
        """ModelInitializationError should store the provided message."""
        msg = "Model load timeout after 300s"
        error = ModelInitializationError(msg)
        assert str(error) == msg

    def test_generation_error_inherits_tts_error(self):
        """GenerationError should be a subclass of TTSError."""
        error = GenerationError("generation failed for input text")
        assert isinstance(error, TTSError)
        assert isinstance(error, Exception)
        assert "generation failed" in str(error)

    def test_generation_error_message(self):
        """GenerationError should store the provided message."""
        msg = "Audio generation failed: empty output"
        error = GenerationError(msg)
        assert str(error) == msg

    def test_playback_error_inherits_tts_error(self):
        """PlaybackError should be a subclass of TTSError."""
        error = PlaybackError("audio output device not found")
        assert isinstance(error, TTSError)
        assert isinstance(error, Exception)
        assert "audio output device not found" in str(error)

    def test_playback_error_message(self):
        """PlaybackError should store the provided message."""
        msg = "Playback interrupted by system"
        error = PlaybackError(msg)
        assert str(error) == msg

    def test_exception_hierarchy_catch_all(self):
        """Catching TTSError should catch all TTS-specific exceptions."""
        exceptions = [
            ModelInitializationError("init fail"),
            GenerationError("gen fail"),
            PlaybackError("play fail"),
        ]
        for exc in exceptions:
            with pytest.raises(TTSError):
                raise exc


# ---------------------------------------------------------------------------
# Task 21.2: TTSEngineState enum
# ---------------------------------------------------------------------------


class TestTTSEngineState:
    """Tests for TTSEngineState enum values."""

    def test_idle_value(self):
        """IDLE state should have value 'idle'."""
        assert TTSEngineState.IDLE.value == "idle"

    def test_loading_model_value(self):
        """LOADING_MODEL state should have value 'loading_model'."""
        assert TTSEngineState.LOADING_MODEL.value == "loading_model"

    def test_generating_value(self):
        """GENERATING state should have value 'generating'."""
        assert TTSEngineState.GENERATING.value == "generating"

    def test_playing_value(self):
        """PLAYING state should have value 'playing'."""
        assert TTSEngineState.PLAYING.value == "playing"

    def test_stopping_value(self):
        """STOPPING state should have value 'stopping'."""
        assert TTSEngineState.STOPPING.value == "stopping"

    def test_all_states_present(self):
        """All five states should be defined."""
        state_values = {s.value for s in TTSEngineState}
        expected = {"idle", "loading_model", "generating", "playing", "stopping"}
        assert state_values == expected

    def test_state_is_string_enum(self):
        """TTSEngineState should be a string enum (str, Enum)."""
        assert isinstance(TTSEngineState.IDLE, str)
        assert TTSEngineState.IDLE == "idle"


# ---------------------------------------------------------------------------
# Task 21.2: VoiceConfig dataclass
# ---------------------------------------------------------------------------


class TestVoiceConfig:
    """Tests for VoiceConfig dataclass."""

    def test_creation_with_all_fields(self):
        """VoiceConfig should store language and voice_instruct."""
        config = VoiceConfig(
            language="Korean",
            voice_instruct="A warm, friendly Korean female voice"
        )
        assert config.language == "Korean"
        assert config.voice_instruct == "A warm, friendly Korean female voice"

    def test_creation_english(self):
        """VoiceConfig should work with English language."""
        config = VoiceConfig(
            language="English",
            voice_instruct="A clear, professional male voice"
        )
        assert config.language == "English"
        assert "male" in config.voice_instruct

    def test_equality(self):
        """Two VoiceConfigs with the same fields should be equal."""
        a = VoiceConfig(language="Korean", voice_instruct="desc")
        b = VoiceConfig(language="Korean", voice_instruct="desc")
        assert a == b

    def test_inequality(self):
        """Two VoiceConfigs with different fields should not be equal."""
        a = VoiceConfig(language="Korean", voice_instruct="desc A")
        b = VoiceConfig(language="Korean", voice_instruct="desc B")
        assert a != b


# ---------------------------------------------------------------------------
# Task 21.2: VOICE_PRESETS dictionary
# ---------------------------------------------------------------------------


class TestVoicePresets:
    """Tests for VOICE_PRESETS dictionary."""

    def test_has_korean_female(self):
        """VOICE_PRESETS should contain 'korean_female' key."""
        assert "korean_female" in VOICE_PRESETS

    def test_has_korean_male(self):
        """VOICE_PRESETS should contain 'korean_male' key."""
        assert "korean_male" in VOICE_PRESETS

    def test_has_english_female(self):
        """VOICE_PRESETS should contain 'english_female' key."""
        assert "english_female" in VOICE_PRESETS

    def test_has_english_male(self):
        """VOICE_PRESETS should contain 'english_male' key."""
        assert "english_male" in VOICE_PRESETS

    def test_exactly_four_presets(self):
        """VOICE_PRESETS should contain exactly 4 presets."""
        assert len(VOICE_PRESETS) == 4

    def test_all_presets_are_voice_config(self):
        """All presets should be VoiceConfig instances."""
        for name, preset in VOICE_PRESETS.items():
            assert isinstance(preset, VoiceConfig), (
                f"Preset '{name}' should be VoiceConfig, got {type(preset)}"
            )

    def test_korean_female_has_language_field(self):
        """korean_female preset should have language 'Korean'."""
        assert VOICE_PRESETS["korean_female"].language == "Korean"

    def test_korean_male_has_language_field(self):
        """korean_male preset should have language 'Korean'."""
        assert VOICE_PRESETS["korean_male"].language == "Korean"

    def test_english_female_has_language_field(self):
        """english_female preset should have language 'English'."""
        assert VOICE_PRESETS["english_female"].language == "English"

    def test_english_male_has_language_field(self):
        """english_male preset should have language 'English'."""
        assert VOICE_PRESETS["english_male"].language == "English"

    def test_all_presets_have_voice_instruct(self):
        """All presets should have a non-empty voice_instruct."""
        for name, preset in VOICE_PRESETS.items():
            assert preset.voice_instruct, (
                f"Preset '{name}' should have non-empty voice_instruct"
            )

    def test_korean_presets_have_korean_instruct(self):
        """Korean presets should reference Korean in voice_instruct."""
        for name in ("korean_female", "korean_male"):
            instruct = VOICE_PRESETS[name].voice_instruct.lower()
            assert "korean" in instruct, (
                f"Preset '{name}' voice_instruct should mention Korean"
            )

    def test_english_presets_have_english_instruct(self):
        """English presets should reference English in voice_instruct."""
        for name in ("english_female", "english_male"):
            instruct = VOICE_PRESETS[name].voice_instruct.lower()
            assert "english" in instruct, (
                f"Preset '{name}' voice_instruct should mention English"
            )


# ---------------------------------------------------------------------------
# Task 21.2: TTSEngine - creation and defaults
# ---------------------------------------------------------------------------


class TestTTSEngineDefaults:
    """Tests for TTSEngine default state and configuration."""

    def test_default_state_is_idle(self):
        """TTSEngine should start in IDLE state."""
        engine = TTSEngine()
        assert engine.state == TTSEngineState.IDLE

    def test_default_voice_config_is_korean_female(self):
        """TTSEngine default voice config should be korean_female preset."""
        engine = TTSEngine()
        expected = VOICE_PRESETS["korean_female"]
        config = engine.get_voice_config()
        assert config.language == expected.language
        assert config.voice_instruct == expected.voice_instruct

    def test_model_constants(self):
        """TTSEngine should have model constants for VoiceDesign and CustomVoice."""
        assert TTSEngine.MODEL_VOICE_DESIGN == "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16"
        assert TTSEngine.MODEL_CUSTOM_VOICE == "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-bf16"

    def test_default_model_is_voice_design(self):
        """Default model should be VoiceDesign."""
        engine = TTSEngine()
        assert engine.model_id == TTSEngine.MODEL_VOICE_DESIGN
        assert engine.model_type == ModelType.VOICE_DESIGN

    def test_custom_voice_model_type_detection(self):
        """CustomVoice model ID should be detected correctly."""
        engine = TTSEngine(model_id=TTSEngine.MODEL_CUSTOM_VOICE)
        assert engine.model_type == ModelType.CUSTOM_VOICE

    def test_model_is_none_before_init(self):
        """Model should be None before initialize() is called."""
        engine = TTSEngine()
        assert engine._model is None

    def test_status_callback_stored(self):
        """status_callback passed to constructor should be stored."""
        callback = Mock()
        engine = TTSEngine(status_callback=callback)
        assert engine._status_callback is callback

    def test_no_status_callback_by_default(self):
        """status_callback should default to None."""
        engine = TTSEngine()
        assert engine._status_callback is None

    def test_stop_event_exists(self):
        """Engine should have a threading.Event for stop signaling."""
        engine = TTSEngine()
        assert isinstance(engine._stop_event, threading.Event)

    def test_stop_event_initially_not_set(self):
        """Stop event should not be set initially."""
        engine = TTSEngine()
        assert not engine._stop_event.is_set()


# ---------------------------------------------------------------------------
# Task 21.2: TTSEngine - voice configuration
# ---------------------------------------------------------------------------


class TestTTSEngineVoiceConfig:
    """Tests for TTSEngine voice configuration management."""

    def test_set_voice_config_updates(self):
        """set_voice_config() should update the engine's voice config."""
        engine = TTSEngine()
        new_config = VoiceConfig(
            language="English",
            voice_instruct="A deep male English voice"
        )
        engine.set_voice_config(new_config)
        assert engine.get_voice_config() == new_config

    def test_get_voice_config_returns_current(self):
        """get_voice_config() should return the current configuration."""
        engine = TTSEngine()
        config = engine.get_voice_config()
        assert isinstance(config, VoiceConfig)
        assert config.language == "Korean"  # default is korean_female

    def test_set_voice_config_persists_across_calls(self):
        """Voice config should persist after being set until changed again."""
        engine = TTSEngine()

        config_en = VoiceConfig(language="English", voice_instruct="English voice")
        engine.set_voice_config(config_en)
        assert engine.get_voice_config() == config_en

        # Still the same after another get
        assert engine.get_voice_config() == config_en

        config_ko = VoiceConfig(language="Korean", voice_instruct="Korean voice")
        engine.set_voice_config(config_ko)
        assert engine.get_voice_config() == config_ko

    def test_set_voice_config_with_preset(self):
        """Setting voice config with a preset value should work."""
        engine = TTSEngine()
        engine.set_voice_config(VOICE_PRESETS["english_male"])
        config = engine.get_voice_config()
        assert config.language == "English"


# ---------------------------------------------------------------------------
# Task 21.2: TTSEngine - speak() edge cases
# ---------------------------------------------------------------------------


class TestTTSEngineSpeak:
    """Tests for TTSEngine.speak() behavior."""

    @pytest.mark.asyncio
    async def test_speak_empty_string_does_nothing(self):
        """speak() with empty string should return without changing state."""
        engine = TTSEngine()
        await engine.speak("")
        assert engine.state == TTSEngineState.IDLE

    @pytest.mark.asyncio
    async def test_speak_whitespace_only_does_nothing(self):
        """speak() with whitespace-only string should return without changing state."""
        engine = TTSEngine()
        await engine.speak("   ")
        assert engine.state == TTSEngineState.IDLE

    @pytest.mark.asyncio
    async def test_speak_newlines_only_does_nothing(self):
        """speak() with only newlines should return without changing state."""
        engine = TTSEngine()
        await engine.speak("\n\n\t")
        assert engine.state == TTSEngineState.IDLE

    @pytest.mark.asyncio
    @patch("tts.engine.load_model")
    async def test_speak_sets_state_to_generating(self, mock_load_model):
        """speak(text) should transition state to GENERATING when model is ready.

        We mock load_model to avoid actual model download. The mock model's
        generate_voice_design returns an empty iterator so speak() will
        proceed past generation quickly.
        """
        mock_model = MagicMock()
        mock_model.sample_rate = 24000
        mock_model.generate_voice_design.return_value = iter([])
        mock_load_model.return_value = mock_model

        # Track state changes via callback
        states_observed = []
        callback = Mock(side_effect=lambda s: states_observed.append(s))
        engine = TTSEngine(status_callback=callback)

        await engine.speak("Hello world")

        # GENERATING should appear among the observed state transitions
        assert TTSEngineState.GENERATING in states_observed


# ---------------------------------------------------------------------------
# Task 21.2: TTSEngine - stop()
# ---------------------------------------------------------------------------


class TestTTSEngineStop:
    """Tests for TTSEngine.stop() behavior."""

    @pytest.mark.asyncio
    async def test_stop_when_idle_does_nothing(self):
        """stop() when already IDLE should be a no-op."""
        engine = TTSEngine()
        assert engine.state == TTSEngineState.IDLE
        await engine.stop()
        assert engine.state == TTSEngineState.IDLE

    @pytest.mark.asyncio
    async def test_stop_sets_stop_event(self):
        """stop() should set the _stop_event so playback thread can exit."""
        engine = TTSEngine()
        # Force engine into a non-IDLE state to test stop logic
        engine._state = TTSEngineState.PLAYING
        await engine.stop()
        assert engine._stop_event.is_set()

    @pytest.mark.asyncio
    async def test_stop_returns_to_idle(self):
        """stop() should return the engine to IDLE state."""
        engine = TTSEngine()
        engine._state = TTSEngineState.GENERATING
        await engine.stop()
        assert engine.state == TTSEngineState.IDLE

    @pytest.mark.asyncio
    async def test_stop_joins_playback_thread(self):
        """stop() should join the playback thread if one is alive."""
        engine = TTSEngine()
        engine._state = TTSEngineState.PLAYING

        mock_thread = MagicMock(spec=threading.Thread)
        mock_thread.is_alive.return_value = True
        engine._playback_thread = mock_thread

        await engine.stop()

        mock_thread.join.assert_called_once_with(timeout=0.5)


# ---------------------------------------------------------------------------
# Task 21.2: TTSEngine - initialize()
# ---------------------------------------------------------------------------


class TestTTSEngineInitialize:
    """Tests for TTSEngine.initialize() behavior."""

    @pytest.mark.asyncio
    @patch("tts.engine.load_model")
    async def test_initialize_sets_state_to_loading_then_idle(self, mock_load_model):
        """initialize() should transition IDLE -> LOADING_MODEL -> IDLE."""
        mock_model = MagicMock()
        mock_model.sample_rate = 24000
        mock_load_model.return_value = mock_model

        states_observed = []
        callback = Mock(side_effect=lambda s: states_observed.append(s))
        engine = TTSEngine(status_callback=callback)

        await engine.initialize()

        assert TTSEngineState.LOADING_MODEL in states_observed
        assert engine.state == TTSEngineState.IDLE

    @pytest.mark.asyncio
    @patch("tts.engine.load_model")
    async def test_initialize_loads_model(self, mock_load_model):
        """initialize() should call load_model with the model_id."""
        mock_model = MagicMock()
        mock_model.sample_rate = 24000
        mock_load_model.return_value = mock_model

        engine = TTSEngine()
        await engine.initialize()

        mock_load_model.assert_called_once_with(engine.model_id)

    @pytest.mark.asyncio
    @patch("tts.engine.load_model")
    async def test_initialize_idempotent(self, mock_load_model):
        """Calling initialize() twice should only load model once."""
        mock_model = MagicMock()
        mock_model.sample_rate = 24000
        mock_load_model.return_value = mock_model

        engine = TTSEngine()
        await engine.initialize()
        await engine.initialize()

        mock_load_model.assert_called_once()

    @pytest.mark.asyncio
    @patch("tts.engine.load_model")
    async def test_initialize_stores_model(self, mock_load_model):
        """initialize() should store the loaded model on the engine."""
        mock_model = MagicMock()
        mock_model.sample_rate = 24000
        mock_load_model.return_value = mock_model

        engine = TTSEngine()
        await engine.initialize()

        assert engine._model is mock_model


# ---------------------------------------------------------------------------
# Task 21.2: TTSEngine - shutdown()
# ---------------------------------------------------------------------------


class TestTTSEngineShutdown:
    """Tests for TTSEngine.shutdown() behavior."""

    @pytest.mark.asyncio
    async def test_shutdown_clears_model(self):
        """shutdown() should set _model to None."""
        engine = TTSEngine()
        engine._model = MagicMock()
        engine._state = TTSEngineState.IDLE
        await engine.shutdown()
        assert engine._model is None

    @pytest.mark.asyncio
    async def test_shutdown_calls_stop(self):
        """shutdown() should call stop() before clearing model."""
        engine = TTSEngine()
        engine._state = TTSEngineState.PLAYING
        engine._model = MagicMock()

        with patch.object(engine, "stop", new_callable=AsyncMock) as mock_stop:
            await engine.shutdown()
            mock_stop.assert_called_once()

    @pytest.mark.asyncio
    async def test_shutdown_returns_to_idle(self):
        """shutdown() should leave engine in IDLE state."""
        engine = TTSEngine()
        engine._state = TTSEngineState.GENERATING
        await engine.shutdown()
        assert engine.state == TTSEngineState.IDLE


# ---------------------------------------------------------------------------
# Task 21.2: TTSEngine - status_callback
# ---------------------------------------------------------------------------


class TestTTSEngineStatusCallback:
    """Tests for TTSEngine status_callback invocation."""

    def test_set_state_calls_callback(self):
        """_set_state() should invoke status_callback with the new state."""
        callback = Mock()
        engine = TTSEngine(status_callback=callback)

        engine._set_state(TTSEngineState.GENERATING)

        callback.assert_called_once_with(TTSEngineState.GENERATING)

    def test_set_state_without_callback_does_not_raise(self):
        """_set_state() without callback should not raise."""
        engine = TTSEngine()
        engine._set_state(TTSEngineState.LOADING_MODEL)
        assert engine.state == TTSEngineState.LOADING_MODEL

    def test_callback_receives_all_transitions(self):
        """status_callback should be called for every state transition."""
        callback = Mock()
        engine = TTSEngine(status_callback=callback)

        engine._set_state(TTSEngineState.LOADING_MODEL)
        engine._set_state(TTSEngineState.IDLE)
        engine._set_state(TTSEngineState.GENERATING)
        engine._set_state(TTSEngineState.PLAYING)
        engine._set_state(TTSEngineState.STOPPING)
        engine._set_state(TTSEngineState.IDLE)

        assert callback.call_count == 6
        states = [call.args[0] for call in callback.call_args_list]
        assert states == [
            TTSEngineState.LOADING_MODEL,
            TTSEngineState.IDLE,
            TTSEngineState.GENERATING,
            TTSEngineState.PLAYING,
            TTSEngineState.STOPPING,
            TTSEngineState.IDLE,
        ]

    @pytest.mark.asyncio
    async def test_stop_triggers_state_callbacks(self):
        """stop() should trigger STOPPING and then IDLE via status_callback."""
        callback = Mock()
        engine = TTSEngine(status_callback=callback)
        engine._state = TTSEngineState.PLAYING

        await engine.stop()

        # At minimum, STOPPING and IDLE should have been reported
        states = [call.args[0] for call in callback.call_args_list]
        assert TTSEngineState.STOPPING in states
        assert TTSEngineState.IDLE in states


# ---------------------------------------------------------------------------
# Task: TTSEngine - Buffering
# ---------------------------------------------------------------------------


class TestTTSEngineBuffering:
    """Tests for TTSEngine buffering behavior."""

    def test_min_buffer_chunks_constant_exists(self):
        """TTSEngine should have MIN_BUFFER_CHUNKS constant."""
        assert hasattr(TTSEngine, 'MIN_BUFFER_CHUNKS')
        assert isinstance(TTSEngine.MIN_BUFFER_CHUNKS, int)

    def test_min_buffer_chunks_is_positive(self):
        """MIN_BUFFER_CHUNKS should be at least 1."""
        assert TTSEngine.MIN_BUFFER_CHUNKS >= 1

    def test_min_buffer_chunks_default_value(self):
        """MIN_BUFFER_CHUNKS should be 2 by default for smooth playback."""
        assert TTSEngine.MIN_BUFFER_CHUNKS == 2

    @pytest.mark.asyncio
    @patch("tts.engine.sd")
    @patch("tts.engine.load_model")
    async def test_generate_and_play_buffers_before_start(self, mock_load_model, mock_sd):
        """_generate_and_play should NOT call stream.start() until MIN_BUFFER_CHUNKS are ready."""
        import numpy as np

        # Setup mock model that yields multiple chunks
        mock_model = MagicMock()
        chunks = []
        for i in range(4):
            chunk = MagicMock()
            chunk.audio = np.zeros(24000, dtype=np.float32)
            chunk.sample_rate = 24000
            chunks.append(chunk)

        mock_model.generate.return_value = iter(chunks)
        mock_load_model.return_value = mock_model

        # Setup mock sounddevice with call tracking
        mock_stream = MagicMock()
        mock_sd.OutputStream.return_value = mock_stream

        # Track the order of start() and write() calls
        call_log = []

        def on_start():
            call_log.append("start")

        def on_write(data):
            call_log.append("write")

        mock_stream.start.side_effect = on_start
        mock_stream.write.side_effect = on_write

        engine = TTSEngine()
        await engine.initialize()

        from tts.engine import VoiceConfig
        config = VoiceConfig(language="Korean", voice_instruct="test")

        import threading
        thread = threading.Thread(
            target=engine._generate_and_play,
            args=(mock_model, "test text", config),
            daemon=True
        )
        thread.start()
        thread.join(timeout=5.0)

        # Verify call order: start() should be called before any write()
        assert "start" in call_log, "stream.start() should be called"
        start_index = call_log.index("start")

        # After start(), there should be MIN_BUFFER_CHUNKS writes immediately (buffered chunks)
        writes_after_start = call_log[start_index + 1:start_index + 1 + TTSEngine.MIN_BUFFER_CHUNKS]
        assert all(c == "write" for c in writes_after_start), \
            f"Expected {TTSEngine.MIN_BUFFER_CHUNKS} writes after start, got {writes_after_start}"

    @pytest.mark.asyncio
    @patch("tts.engine.sd")
    @patch("tts.engine.load_model")
    async def test_generate_and_play_plays_single_chunk_on_end(self, mock_load_model, mock_sd):
        """If fewer than MIN_BUFFER_CHUNKS are generated, should still play them."""
        import numpy as np

        # Setup mock model that yields only 1 chunk
        mock_model = MagicMock()
        mock_chunk = MagicMock()
        mock_chunk.audio = np.zeros(24000, dtype=np.float32)
        mock_chunk.sample_rate = 24000

        mock_model.generate.return_value = iter([mock_chunk])
        mock_load_model.return_value = mock_model

        # Setup mock sounddevice
        mock_stream = MagicMock()
        mock_sd.OutputStream.return_value = mock_stream

        engine = TTSEngine()
        await engine.initialize()

        from tts.engine import VoiceConfig
        config = VoiceConfig(language="Korean", voice_instruct="test")

        import threading
        thread = threading.Thread(
            target=engine._generate_and_play,
            args=(mock_model, "short", config),
            daemon=True
        )
        thread.start()
        thread.join(timeout=5.0)

        # Even with 1 chunk, playback should happen
        mock_stream.start.assert_called_once()
        mock_stream.write.assert_called_once()
