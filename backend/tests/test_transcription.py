"""
Tests for Transcription Engine

Basic unit tests for transcription components.
Note: Full transcription tests require mlx-whisper which may not be available in CI.
"""

import pytest
import numpy as np
from transcription.engine import (
    AudioSource,
    TranscriptionResult,
    TranscriptionEngine,
)


class TestAudioSource:
    """Tests for AudioSource enum."""
    
    def test_system_value(self):
        """Test system audio source value."""
        assert AudioSource.SYSTEM.value == "system"
    
    def test_microphone_value(self):
        """Test microphone source value."""
        assert AudioSource.MICROPHONE.value == "microphone"


class TestTranscriptionResult:
    """Tests for TranscriptionResult dataclass."""
    
    def test_to_dict(self):
        """Test conversion to dictionary."""
        result = TranscriptionResult(
            text="Hello world",
            source=AudioSource.SYSTEM,
            timestamp=1234567890.0,
            confidence=0.95
        )
        
        d = result.to_dict()
        
        assert d["text"] == "Hello world"
        assert d["source"] == "system"
        assert d["timestamp"] == 1234567890.0
        assert d["confidence"] == 0.95
    
    def test_default_confidence(self):
        """Test default confidence value."""
        result = TranscriptionResult(
            text="Test",
            source=AudioSource.MICROPHONE,
            timestamp=1234567890.0
        )
        
        assert result.confidence == 1.0


class TestTranscriptionEngine:
    """Tests for TranscriptionEngine class."""
    
    def test_initialization_state(self):
        """Test engine starts uninitialized."""
        engine = TranscriptionEngine()
        
        assert not engine.is_initialized
        assert engine.model_name == TranscriptionEngine.DEFAULT_MODEL
    
    def test_custom_model_name(self):
        """Test custom model name."""
        engine = TranscriptionEngine(model_name="custom-model")
        
        assert engine.model_name == "custom-model"
    
    def test_prepare_audio_from_list(self):
        """Test audio preparation from list."""
        engine = TranscriptionEngine()
        
        audio_list = [0.1, 0.2, 0.3, -0.1]
        result = engine._prepare_audio(audio_list)
        
        assert isinstance(result, np.ndarray)
        assert result.dtype == np.float32
        assert len(result) == 4
    
    def test_prepare_audio_from_numpy(self):
        """Test audio preparation from numpy array."""
        engine = TranscriptionEngine()
        
        audio_array = np.array([0.5, -0.5, 0.0], dtype=np.float64)
        result = engine._prepare_audio(audio_array)
        
        assert result.dtype == np.float32
        np.testing.assert_array_almost_equal(result, [0.5, -0.5, 0.0])
    
    def test_prepare_audio_from_bytes(self):
        """Test audio preparation from bytes (16-bit PCM)."""
        engine = TranscriptionEngine()
        
        # Create 16-bit PCM samples: [0, 16384, -16384]
        import struct
        audio_bytes = struct.pack('<3h', 0, 16384, -16384)
        
        result = engine._prepare_audio(audio_bytes)
        
        assert result.dtype == np.float32
        assert len(result) == 3
        assert abs(result[0]) < 0.001  # ~0
        assert abs(result[1] - 0.5) < 0.001  # ~0.5
        assert abs(result[2] + 0.5) < 0.001  # ~-0.5
