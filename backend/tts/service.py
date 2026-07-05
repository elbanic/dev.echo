"""
TTS Service Module

Provides TTSService as the high-level interface for text-to-speech operations.
"""

import logging
import time
from dataclasses import dataclass, field
from typing import Callable, Dict, List, Optional

from .engine import TTSEngine, TTSEngineState, VoiceConfig, VOICE_PRESETS

logger = logging.getLogger(__name__)


@dataclass
class TTSStatus:
    """Status of the TTS service."""
    state: str
    text: Optional[str] = None
    elapsed: Optional[float] = None
    error: Optional[str] = None


class TTSService:
    """High-level TTS service with lazy engine initialization."""

    def __init__(self, status_callback: Optional[Callable] = None):
        self._engine: Optional[TTSEngine] = None
        self._status_callback = status_callback
        self._speak_start_time: Optional[float] = None
        self._current_preset: str = "korean_female"

    async def initialize(self) -> None:
        """Pre-initialize the TTS engine (preload model) without speaking.

        Call this when entering Reading Mode to warm up the model,
        avoiding delay on first text-to-speech request.
        """
        if self._engine is None:
            logger.info("Pre-initializing TTS engine (warmup)")
            self._engine = TTSEngine(status_callback=self._on_engine_status)
        await self._engine.initialize()

    async def speak(self, text: str, language: Optional[str] = None) -> None:
        """Speak the given text, creating engine lazily if needed."""
        if self._engine is None:
            logger.info("Creating TTS engine (lazy init)")
            self._engine = TTSEngine(status_callback=self._on_engine_status)

        logger.debug("Speaking text (%d chars)", len(text))
        self._speak_start_time = time.time()
        await self._engine.speak(text)

    async def stop_speech(self) -> None:
        """Stop current speech playback."""
        logger.debug("Stopping speech")
        if self._engine is not None:
            await self._engine.stop()
        self._speak_start_time = None

    def get_status(self) -> TTSStatus:
        """Get current TTS status."""
        if self._engine is None:
            return TTSStatus(state="idle")

        elapsed = None
        if self._speak_start_time is not None:
            elapsed = time.time() - self._speak_start_time

        return TTSStatus(
            state=self._engine.state.value,
            elapsed=elapsed,
        )

    def get_voice_config(self) -> Dict[str, str]:
        """Get current voice configuration as a dict."""
        if self._engine is not None:
            config = self._engine.get_voice_config()
        else:
            config = VOICE_PRESETS[self._current_preset]

        return {
            "language": config.language,
            "voice_instruct": config.voice_instruct,
        }

    def set_preset(self, name: str) -> bool:
        """Set voice preset by name. Returns True if valid, False otherwise."""
        if name not in VOICE_PRESETS:
            logger.warning("Invalid voice preset: %s", name)
            return False

        logger.info("Voice preset set to: %s", name)
        self._current_preset = name
        if self._engine is not None:
            self._engine.set_voice_config(VOICE_PRESETS[name])

        return True

    def list_presets(self) -> List[str]:
        """Return list of available preset names."""
        return list(VOICE_PRESETS.keys())

    async def shutdown(self) -> None:
        """Shutdown the TTS engine."""
        logger.info("Shutting down TTS service")
        if self._engine is not None:
            await self._engine.shutdown()

    def _on_engine_status(self, state: TTSEngineState) -> None:
        """Internal callback invoked by engine on state changes."""
        if self._status_callback is None:
            return

        elapsed = None
        if self._speak_start_time is not None:
            elapsed = time.time() - self._speak_start_time

        status = TTSStatus(state=state.value, elapsed=elapsed)
        self._status_callback(status)
