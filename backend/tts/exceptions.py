"""
TTS Exception Classes

Custom exceptions for TTS-related errors.
"""


class TTSError(Exception):
    """Base exception for TTS errors."""
    pass


class ModelInitializationError(TTSError):
    """Raised when TTS model fails to load."""
    pass


class GenerationError(TTSError):
    """Raised when audio generation fails."""
    pass


class PlaybackError(TTSError):
    """Raised when audio playback fails."""
    pass
