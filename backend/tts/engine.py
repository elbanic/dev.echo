"""
TTS Engine Module

Provides TTSEngine for text-to-speech using mlx_audio Qwen3-TTS model.
Audio is streamed chunk-by-chunk: playback starts as soon as the first
chunk is generated, without waiting for the full text to be synthesized.

Text is split into sentences using SentenceSplitter for faster first-audio
delivery - the first sentence starts playing while subsequent sentences
are still being generated.
"""

import asyncio
import logging
import threading
import time
from dataclasses import dataclass
from enum import Enum
from typing import Callable, Dict, List, Optional

import numpy as np

logger = logging.getLogger(__name__)

try:
    from mlx_audio.tts.utils import load_model
except ImportError:
    load_model = None  # Will be available when mlx_audio is installed

try:
    import sounddevice as sd
except ImportError:
    sd = None  # Will be available when sounddevice is installed

from .exceptions import ModelInitializationError, GenerationError, PlaybackError


class TTSEngineState(str, Enum):
    """States for the TTS engine lifecycle."""
    IDLE = "idle"
    LOADING_MODEL = "loading_model"
    GENERATING = "generating"
    PLAYING = "playing"
    STOPPING = "stopping"


class ModelType(str, Enum):
    """TTS model type for different generation methods."""
    VOICE_DESIGN = "voice_design"  # Uses generate() with instruct
    CUSTOM_VOICE = "custom_voice"  # Uses generate_custom_voice() with speaker


@dataclass
class VoiceConfig:
    """Configuration for voice synthesis."""
    language: str
    voice_instruct: str
    speaker: Optional[str] = None  # For CustomVoice models


# Predefined voice presets
VOICE_PRESETS: Dict[str, VoiceConfig] = {
    "korean_female": VoiceConfig(
        language="Korean",
        voice_instruct="A warm, friendly Korean female voice with clear pronunciation",
        speaker="Sohee",  # Korean female voice for CustomVoice
    ),
    "korean_male": VoiceConfig(
        language="Korean",
        voice_instruct="A calm, professional Korean male voice with natural tone",
        speaker="Sohee",  # Fallback to Sohee (no Korean male in CustomVoice)
    ),
    "english_female": VoiceConfig(
        language="English",
        voice_instruct="A clear, friendly English female voice with natural intonation",
        speaker="Vivian",  # Use Vivian for English female
    ),
    "english_male": VoiceConfig(
        language="English",
        voice_instruct="A deep, professional English male voice with clear articulation",
        speaker="Ryan",  # English male voice for CustomVoice
    ),
}


class TTSEngine:
    """Text-to-speech engine using mlx_audio Qwen3-TTS model.

    Audio is streamed: generation and playback happen concurrently.
    Each audio chunk is written to the output stream as soon as it is
    generated, so the user hears speech before the full text is synthesized.

    Text is split into sentences for faster first-audio delivery.
    The first sentence starts playing while subsequent sentences are
    still being generated.

    Supports two model types:
    - VoiceDesign: Uses generate() with instruct parameter for voice styling
    - CustomVoice: Uses generate_custom_voice() with speaker parameter
    """

    # Available model IDs
    MODEL_VOICE_DESIGN = "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16"
    MODEL_CUSTOM_VOICE = "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-bf16"

    SAMPLE_RATE = 24000

    def __init__(
        self,
        model_id: Optional[str] = None,
        status_callback: Optional[Callable] = None,
    ):
        self._model_id = model_id or self.MODEL_VOICE_DESIGN
        self._model_type = self._detect_model_type()
        self._model = None
        self._state = TTSEngineState.IDLE
        self._voice_config = VOICE_PRESETS["korean_female"]
        self._stop_event = threading.Event()
        self._playback_thread: Optional[threading.Thread] = None
        self._status_callback = status_callback

    def _detect_model_type(self) -> ModelType:
        """Detect model type from model ID."""
        if "CustomVoice" in self._model_id:
            return ModelType.CUSTOM_VOICE
        return ModelType.VOICE_DESIGN

    @property
    def model_id(self) -> str:
        """Return the current model ID."""
        return self._model_id

    @property
    def model_type(self) -> ModelType:
        """Return the current model type."""
        return self._model_type

    @property
    def state(self) -> TTSEngineState:
        """Return the current engine state."""
        return self._state

    def _set_state(self, state: TTSEngineState) -> None:
        """Update state and notify callback if present."""
        self._state = state
        if self._status_callback is not None:
            self._status_callback(state)

    async def initialize(self) -> None:
        """Load the TTS model if not already loaded."""
        if self._model is not None:
            return

        logger.info("Loading TTS model: %s (type: %s)", self._model_id, self._model_type.value)
        self._set_state(TTSEngineState.LOADING_MODEL)
        loop = asyncio.get_running_loop()
        self._model = await loop.run_in_executor(None, load_model, self._model_id)
        self._set_state(TTSEngineState.IDLE)
        logger.info("TTS model loaded successfully")

    # Minimum chunks to buffer before starting playback for smooth audio
    MIN_BUFFER_CHUNKS = 2

    async def speak(self, text: str) -> None:
        """Generate and stream-play speech for the given text.

        Uses model.generate() with the entire text to ensure consistent voice
        throughout. Audio chunks are buffered initially for smooth playback.
        """
        if not text.strip():
            return

        # Stop any current generation or playback
        if self._state in (TTSEngineState.GENERATING, TTSEngineState.PLAYING):
            await self.stop()

        # Ensure model is loaded
        await self.initialize()

        # Clear stop event for new playback
        self._stop_event.clear()

        logger.info("Starting speech for text (%d chars)", len(text))
        self._set_state(TTSEngineState.GENERATING)

        config = self._voice_config
        model = self._model

        # Run generation + streaming playback in a daemon thread
        self._playback_thread = threading.Thread(
            target=self._generate_and_play,
            args=(model, text, config),
            daemon=True,
        )
        self._playback_thread.start()

    def _generate_and_play(
        self, model, text: str, config: VoiceConfig
    ) -> None:
        """Generate audio chunks and play them using pipeline (runs in thread).

        Uses model.generate() or model.generate_custom_voice() depending on model type.
        Buffers MIN_BUFFER_CHUNKS before starting playback for smooth audio.
        """
        if sd is None:
            logger.error("sounddevice not installed, cannot play audio")
            self._set_state(TTSEngineState.IDLE)
            return

        import queue

        # Queue for audio chunks (None = sentinel for end)
        audio_queue: queue.Queue = queue.Queue(maxsize=20)
        generator_error = [None]
        model_type = self._model_type

        def generator_worker():
            """Generate audio using appropriate method based on model type."""
            try:
                if self._stop_event.is_set():
                    return

                text_preview = text[:50] + "..." if len(text) > 50 else text
                logger.debug("Generating audio for: %s (model_type=%s)", text_preview, model_type.value)

                if model_type == ModelType.CUSTOM_VOICE:
                    # CustomVoice: use generate_custom_voice() with speaker
                    gen_iter = model.generate_custom_voice(
                        text=text,
                        speaker=config.speaker or "Sohee",
                        language=config.language,
                        instruct=config.voice_instruct,
                        split_pattern=r'[.!?。！？]\s*',
                        stream=True,
                        streaming_interval=2.0,
                    )
                else:
                    # VoiceDesign: use generate() with instruct
                    gen_iter = model.generate(
                        text=text,
                        instruct=config.voice_instruct,
                        lang_code=config.language,
                        split_pattern=r'[.!?。！？]\s*',
                        stream=True,
                        streaming_interval=2.0,
                    )

                for chunk in gen_iter:
                    if self._stop_event.is_set():
                        break
                    audio_np = np.array(chunk.audio, dtype=np.float32).flatten()
                    audio_queue.put((audio_np, chunk.sample_rate))

            except Exception as exc:
                generator_error[0] = exc
                logger.error("Generator error: %s", exc)
            finally:
                audio_queue.put(None)  # Sentinel

        # Start generator thread
        generator_thread = threading.Thread(target=generator_worker, daemon=True)
        generator_thread.start()

        # Collect initial buffer then play
        stream = None
        start_time = time.monotonic()
        chunk_count = 0
        total_samples = 0
        initial_buffer = []

        try:
            while True:
                if self._stop_event.is_set():
                    break

                try:
                    item = audio_queue.get(timeout=0.1)
                except queue.Empty:
                    continue

                if item is None:  # Sentinel - generation complete
                    # Play any remaining buffered chunks
                    if initial_buffer and stream is None:
                        sample_rate = initial_buffer[0][1]
                        stream = sd.OutputStream(
                            samplerate=sample_rate, channels=1, dtype="float32"
                        )
                        stream.start()
                        logger.info("Starting playback with %d buffered chunks", len(initial_buffer))
                        self._set_state(TTSEngineState.PLAYING)
                        for buf_audio, _ in initial_buffer:
                            stream.write(buf_audio.reshape(-1, 1))
                            chunk_count += 1
                            total_samples += len(buf_audio)
                    break

                audio_np, sample_rate = item

                # Buffer initial chunks for smooth playback
                if stream is None:
                    initial_buffer.append((audio_np, sample_rate))
                    if len(initial_buffer) >= self.MIN_BUFFER_CHUNKS:
                        # Start playback
                        stream = sd.OutputStream(
                            samplerate=sample_rate, channels=1, dtype="float32"
                        )
                        stream.start()
                        first_chunk_time = time.monotonic() - start_time
                        logger.info(
                            "Buffer ready (%d chunks) in %.1f sec, starting playback",
                            len(initial_buffer), first_chunk_time,
                        )
                        self._set_state(TTSEngineState.PLAYING)
                        # Play buffered chunks
                        for buf_audio, _ in initial_buffer:
                            stream.write(buf_audio.reshape(-1, 1))
                            chunk_count += 1
                            total_samples += len(buf_audio)
                        initial_buffer.clear()
                else:
                    # Normal playback
                    stream.write(audio_np.reshape(-1, 1))
                    chunk_count += 1
                    total_samples += len(audio_np)

        except Exception as exc:
            logger.error("Playback failed: %s", exc)
        finally:
            generator_thread.join(timeout=2.0)

            if generator_error[0] is not None:
                logger.error("Generator thread error: %s", generator_error[0])

            if stream is not None:
                if not self._stop_event.is_set():
                    time.sleep(0.3)  # Let buffer drain
                stream.stop()
                stream.close()

            elapsed = time.monotonic() - start_time
            duration = total_samples / self.SAMPLE_RATE if total_samples > 0 else 0
            logger.info(
                "Playback done: %d chunks, %.1f sec audio, %.1f sec elapsed",
                chunk_count, duration, elapsed,
            )
            self._set_state(TTSEngineState.IDLE)

    async def stop(self) -> None:
        """Stop current speech playback."""
        if self._state == TTSEngineState.IDLE:
            return

        logger.info("Stop requested (current state: %s)", self._state.value)
        self._set_state(TTSEngineState.STOPPING)
        self._stop_event.set()

        # Join playback thread if active (short timeout for responsiveness)
        if self._playback_thread is not None and self._playback_thread.is_alive():
            self._playback_thread.join(timeout=0.5)
            # If still alive after timeout, it will stop on next iteration
            if self._playback_thread.is_alive():
                logger.debug("Playback thread still running, will stop soon")

        self._set_state(TTSEngineState.IDLE)

    def set_voice_config(self, config: VoiceConfig) -> None:
        """Set the voice configuration."""
        self._voice_config = config

    def get_voice_config(self) -> VoiceConfig:
        """Get the current voice configuration."""
        return self._voice_config

    async def shutdown(self) -> None:
        """Stop playback and release model resources."""
        await self.stop()
        self._model = None
