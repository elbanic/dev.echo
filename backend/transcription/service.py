"""
Transcription Service

Integrates TranscriptionEngine with IPC server for real-time transcription.
Handles audio buffering and source tracking.
"""

import asyncio
import logging
import time
from collections import defaultdict
from typing import Callable, Optional, Awaitable

from .engine import TranscriptionEngine, TranscriptionResult, AudioSource

logger = logging.getLogger(__name__)


class TranscriptionService:
    """
    Service layer for transcription with audio buffering.
    
    Buffers incoming audio data and triggers transcription when
    sufficient audio has accumulated. Maintains separate buffers
    for system audio and microphone input.
    
    Requirements: 6.1, 6.2, 6.3, 6.4
    """
    
    # Buffer settings
    SAMPLE_RATE = 16000
    BUFFER_DURATION_SECONDS = 2.0  # Transcribe every 2 seconds of audio
    MIN_BUFFER_SAMPLES = int(SAMPLE_RATE * 0.5)  # Minimum 0.5 seconds
    
    def __init__(
        self,
        engine: Optional[TranscriptionEngine] = None,
        on_transcription: Optional[Callable[[TranscriptionResult], Awaitable[None]]] = None
    ):
        """
        Initialize the transcription service.
        
        Args:
            engine: TranscriptionEngine instance. Creates new one if not provided.
            on_transcription: Callback for transcription results.
        """
        self.engine = engine or TranscriptionEngine()
        self._on_transcription = on_transcription
        
        # Separate buffers for each audio source
        self._buffers: dict[AudioSource, list[float]] = defaultdict(list)
        self._buffer_timestamps: dict[AudioSource, float] = {}
        self._lock = asyncio.Lock()
        
        self._running = False
        self._process_task: Optional[asyncio.Task] = None
    
    async def start(self) -> None:
        """Start the transcription service."""
        if self._running:
            return
        
        await self.engine.initialize()
        self._running = True
        
        # Start background processing task
        self._process_task = asyncio.create_task(self._process_loop())
        
        logger.info("Transcription service started")
    
    async def stop(self) -> None:
        """Stop the transcription service."""
        self._running = False
        
        if self._process_task:
            self._process_task.cancel()
            try:
                await self._process_task
            except asyncio.CancelledError:
                pass
        
        # Process any remaining audio
        await self._flush_buffers()
        
        await self.engine.shutdown()
        logger.info("Transcription service stopped")
    
    async def process_audio(
        self,
        samples: list[float],
        source: str,
        timestamp: float
    ) -> None:
        """
        Process incoming audio data.
        
        Buffers audio samples and triggers transcription when buffer is full.
        
        Args:
            samples: Audio samples (16kHz, mono, float32)
            source: Audio source ("system" or "microphone")
            timestamp: Timestamp of the audio data
        
        Requirements: 6.2 - Maintain source identification
        """
        audio_source = AudioSource(source)
        
        async with self._lock:
            # Add samples to buffer
            self._buffers[audio_source].extend(samples)
            
            # Track first timestamp in buffer
            if audio_source not in self._buffer_timestamps:
                self._buffer_timestamps[audio_source] = timestamp
            
            # Log buffer status (debug level)
            buffer_len = len(self._buffers[audio_source])
            buffer_seconds = buffer_len / self.SAMPLE_RATE
            logger.debug(f"[{source}] Received {len(samples)} samples, buffer: {buffer_seconds:.1f}s")
    
    async def _process_loop(self) -> None:
        """Background loop to process buffered audio."""
        while self._running:
            try:
                await asyncio.sleep(0.5)  # Check buffers every 500ms
                await self._check_and_process_buffers()
            except asyncio.CancelledError:
                break
            except Exception as e:
                # Requirement 6.4: Log error and continue
                logger.error(f"Error in process loop: {e}")
                continue
    
    async def _check_and_process_buffers(self) -> None:
        """Check buffers and process if ready."""
        buffer_threshold = int(self.SAMPLE_RATE * self.BUFFER_DURATION_SECONDS)
        
        for source in list(AudioSource):
            async with self._lock:
                buffer = self._buffers[source]
                
                if len(buffer) >= buffer_threshold:
                    # Extract buffer for processing
                    samples = buffer[:buffer_threshold]
                    self._buffers[source] = buffer[buffer_threshold:]
                    timestamp = self._buffer_timestamps.pop(source, time.time())
                    
                    # Update timestamp for remaining buffer
                    if self._buffers[source]:
                        self._buffer_timestamps[source] = time.time()
            
            # Process outside lock
            if len(buffer) >= buffer_threshold:
                await self._transcribe_buffer(samples, source, timestamp)
    
    async def _transcribe_buffer(
        self,
        samples: list[float],
        source: AudioSource,
        timestamp: float
    ) -> None:
        """
        Transcribe a buffer of audio samples.
        
        Requirements: 6.1, 6.2, 6.4
        """
        try:
            logger.debug(f"[{source.value}] Starting transcription of {len(samples)} samples...")
            result = await self.engine.transcribe(samples, source, timestamp)
            
            if result.text:
                logger.info(f"[{source.value}] {result.text}")
                if self._on_transcription:
                    await self._on_transcription(result)
            else:
                logger.debug(f"[{source.value}] No speech detected")
                
        except Exception as e:
            # Requirement 6.4: Log error and continue
            logger.error(f"Transcription error for {source.value}: {e}")
    
    async def _flush_buffers(self) -> None:
        """Process any remaining audio in buffers."""
        for source in list(AudioSource):
            async with self._lock:
                buffer = self._buffers[source]
                timestamp = self._buffer_timestamps.pop(source, time.time())
                self._buffers[source] = []
            
            if len(buffer) >= self.MIN_BUFFER_SAMPLES:
                await self._transcribe_buffer(buffer, source, timestamp)
    
    def set_transcription_callback(
        self,
        callback: Callable[[TranscriptionResult], Awaitable[None]]
    ) -> None:
        """Set the callback for transcription results."""
        self._on_transcription = callback
