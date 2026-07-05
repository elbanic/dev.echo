"""
MLX-Whisper Transcription Engine

Provides real-time transcription using MLX-Whisper for local processing.
Supports source tracking (system audio vs microphone) and error recovery.
"""

import asyncio
import logging
import time
from dataclasses import dataclass
from enum import Enum
from typing import AsyncIterator, Optional, List
import numpy as np

logger = logging.getLogger(__name__)


class TranscriptionError(Exception):
    """Base exception for transcription errors."""
    pass


class ModelInitializationError(TranscriptionError):
    """Raised when model initialization fails."""
    pass


class AudioProcessingError(TranscriptionError):
    """Raised when audio processing fails."""
    pass


class AudioSource(Enum):
    """Audio source identification."""
    SYSTEM = "system"
    MICROPHONE = "microphone"


@dataclass
class TranscriptionResult:
    """Result of a transcription operation."""
    text: str
    source: AudioSource
    timestamp: float
    confidence: float = 1.0
    
    def to_dict(self) -> dict:
        """Convert to dictionary for IPC serialization."""
        return {
            "text": self.text,
            "source": self.source.value,
            "timestamp": self.timestamp,
            "confidence": self.confidence
        }


class TranscriptionEngine:
    """
    MLX-Whisper based transcription engine.
    
    Handles model initialization, audio processing, and transcription
    with source tracking for system audio and microphone input.
    
    Requirements: 6.1, 6.2
    """
    
    DEFAULT_MODEL = "mlx-community/whisper-large-v3-mlx"
    SAMPLE_RATE = 16000  # Expected input sample rate
    
    def __init__(self, model_name: Optional[str] = None):
        """
        Initialize the transcription engine.
        
        Args:
            model_name: MLX-Whisper model to use. Defaults to whisper-base-mlx.
        """
        self.model_name = model_name or self.DEFAULT_MODEL
        self._model = None
        self._initialized = False
        self._lock = asyncio.Lock()
    
    async def initialize(self) -> None:
        """
        Initialize the MLX-Whisper model.
        
        Loads the model on startup for faster subsequent transcriptions.
        Requirement: 6.1 - Initialize model on startup
        
        Raises:
            ModelInitializationError: If model loading fails
        """
        if self._initialized:
            return
        
        async with self._lock:
            if self._initialized:
                return
            
            logger.info(f"Initializing MLX-Whisper model: {self.model_name}")
            
            try:
                # Import mlx_whisper here to avoid import errors if not installed
                import mlx_whisper
                
                # Load model (this downloads if not cached)
                # Run in executor to avoid blocking event loop
                # Timeout set to 300 seconds (5 minutes) for slow machines
                loop = asyncio.get_event_loop()
                await asyncio.wait_for(
                    loop.run_in_executor(None, self._load_model),
                    timeout=300.0
                )
                
                self._initialized = True
                logger.info("MLX-Whisper model initialized successfully")
                
            except asyncio.TimeoutError:
                logger.error("Model initialization timed out after 300 seconds")
                raise ModelInitializationError(
                    "Model initialization timed out. Please check your system resources."
                )
            except ImportError as e:
                logger.error("mlx-whisper not installed. Run: pip install mlx-whisper")
                raise ModelInitializationError(
                    "mlx-whisper not installed. Run: pip install mlx-whisper"
                ) from e
            except Exception as e:
                logger.error(f"Failed to initialize MLX-Whisper: {e}")
                raise ModelInitializationError(f"Failed to initialize model: {e}") from e
    
    def _load_model(self) -> None:
        """Load the MLX-Whisper model (blocking operation)."""
        import mlx_whisper
        # Perform a dummy transcription to ensure model is loaded
        # This triggers model download and caching
        dummy_audio = np.zeros(self.SAMPLE_RATE, dtype=np.float32)
        mlx_whisper.transcribe(
            dummy_audio,
            path_or_hf_repo=self.model_name,
            language="en",  # Force English only
            verbose=False
        )
        self._model = self.model_name
    
    async def transcribe(
        self,
        audio_data: bytes | List[float] | np.ndarray,
        source: AudioSource,
        timestamp: Optional[float] = None
    ) -> TranscriptionResult:
        """
        Transcribe audio data and return result with source identification.
        
        Args:
            audio_data: Audio samples (16kHz, mono, float32)
            source: Audio source (system or microphone)
            timestamp: Optional timestamp for the audio segment
        
        Returns:
            TranscriptionResult with text, source, and timestamp
        
        Raises:
            AudioProcessingError: If transcription fails
        
        Requirements: 6.1, 6.2
        """
        if not self._initialized:
            await self.initialize()
        
        timestamp = timestamp or time.time()
        
        # Convert audio data to numpy array
        try:
            audio_array = self._prepare_audio(audio_data)
        except Exception as e:
            logger.error(f"Failed to prepare audio data: {e}")
            raise AudioProcessingError(f"Invalid audio data: {e}") from e
        
        if len(audio_array) == 0:
            return TranscriptionResult(
                text="",
                source=source,
                timestamp=timestamp,
                confidence=0.0
            )
        
        try:
            import mlx_whisper
            
            # Run transcription in executor to avoid blocking
            loop = asyncio.get_event_loop()
            result = await loop.run_in_executor(
                None,
                lambda: mlx_whisper.transcribe(
                    audio_array,
                    path_or_hf_repo=self.model_name,
                    language="en",  # Force English only
                    verbose=False
                )
            )
            
            text = result.get("text", "").strip()
            
            # Log successful transcription with source
            if text:
                logger.debug(f"Transcribed [{source.value}]: {text[:50]}...")
            
            return TranscriptionResult(
                text=text,
                source=source,
                timestamp=timestamp,
                confidence=1.0
            )
            
        except Exception as e:
            # Requirement 6.4: Log error for recovery
            logger.error(f"Transcription failed for {source.value}: {e}")
            raise AudioProcessingError(f"Transcription failed: {e}") from e
    
    async def stream_transcribe(
        self,
        audio_stream: AsyncIterator[tuple[bytes | List[float], AudioSource]],
    ) -> AsyncIterator[TranscriptionResult]:
        """
        Stream transcription for real-time processing.
        
        Processes audio chunks as they arrive and yields transcription results.
        Maintains source identification throughout the stream.
        
        Args:
            audio_stream: Async iterator yielding (audio_data, source) tuples
        
        Yields:
            TranscriptionResult for each processed audio chunk
        
        Requirements: 6.2, 6.3, 6.4
        """
        if not self._initialized:
            await self.initialize()
        
        async for audio_data, source in audio_stream:
            try:
                result = await self.transcribe(audio_data, source)
                if result.text:  # Only yield non-empty results
                    yield result
            except Exception as e:
                # Requirement 6.4: Log error and continue processing
                logger.error(f"Stream transcription error for {source.value}: {e}")
                # Yield empty result to indicate error but continue
                yield TranscriptionResult(
                    text="",
                    source=source,
                    timestamp=time.time(),
                    confidence=0.0
                )
                continue
    
    def _prepare_audio(self, audio_data: bytes | List[float] | np.ndarray) -> np.ndarray:
        """
        Prepare audio data for transcription.
        
        Converts various input formats to numpy float32 array.
        """
        if isinstance(audio_data, bytes):
            # Assume 16-bit PCM
            audio_array = np.frombuffer(audio_data, dtype=np.int16)
            audio_array = audio_array.astype(np.float32) / 32768.0
        elif isinstance(audio_data, list):
            audio_array = np.array(audio_data, dtype=np.float32)
        elif isinstance(audio_data, np.ndarray):
            audio_array = audio_data.astype(np.float32)
        else:
            raise ValueError(f"Unsupported audio data type: {type(audio_data)}")
        
        return audio_array
    
    async def shutdown(self) -> None:
        """Clean up resources."""
        self._initialized = False
        self._model = None
        logger.info("Transcription engine shut down")
    
    @property
    def is_initialized(self) -> bool:
        """Check if the engine is initialized."""
        return self._initialized
