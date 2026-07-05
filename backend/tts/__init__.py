"""
TTS Module

Provides text-to-speech functionality using mlx_audio Qwen3-TTS model.
"""

from .engine import TTSEngine, TTSEngineState, ModelType, VoiceConfig, VOICE_PRESETS
from .service import TTSService, TTSStatus
from .exceptions import TTSError, ModelInitializationError, GenerationError, PlaybackError
from .sentence_splitter import SentenceSplitter

__all__ = [
    "TTSEngine",
    "TTSEngineState",
    "ModelType",
    "VoiceConfig",
    "VOICE_PRESETS",
    "TTSService",
    "TTSStatus",
    "TTSError",
    "ModelInitializationError",
    "GenerationError",
    "PlaybackError",
    "SentenceSplitter",
]
