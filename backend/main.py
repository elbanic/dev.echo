"""
dev.echo Backend Main Entry Point

Starts the IPC server with transcription service and LLM integration.
"""

import argparse
import asyncio
import logging
import signal
import sys
from typing import Optional

from ipc.server import IPCServer
from ipc.protocol import AudioDataMessage, TranscriptionMessage, LLMQueryMessage, LLMResponseMessage
from transcription import TranscriptionService, TranscriptionResult
from llm import LLMService, OllamaUnavailableError, LLMError

logger = logging.getLogger(__name__)


class DevEchoBackend:
    """
    Main backend application.
    
    Integrates IPC server with transcription service and LLM.
    """
    
    def __init__(self, socket_path: Optional[str] = None):
        self.ipc_server = IPCServer(socket_path)
        self.transcription_service = TranscriptionService()
        self.llm_service = LLMService()
        self._running = False
    
    async def start(self) -> None:
        """Start the backend services."""
        logger.info("Starting dev.echo backend...")
        
        # Set up transcription callback
        self.transcription_service.set_transcription_callback(
            self._on_transcription
        )
        
        # Set up audio handler
        self.ipc_server.on_audio_data(self._on_audio_data)
        
        # Set up LLM query handler
        self.ipc_server.on_llm_query(self._on_llm_query)
        
        # Start services
        await self.transcription_service.start()
        await self.llm_service.start()
        await self.ipc_server.start()
        
        self._running = True
        logger.info("dev.echo backend started")
    
    async def stop(self) -> None:
        """Stop the backend services."""
        logger.info("Stopping dev.echo backend...")
        self._running = False
        
        await self.ipc_server.stop()
        await self.transcription_service.stop()
        await self.llm_service.stop()
        
        logger.info("dev.echo backend stopped")
    
    async def run(self) -> None:
        """Run the backend until shutdown."""
        await self.start()
        
        # Wait for shutdown signal
        try:
            while self._running:
                await asyncio.sleep(1)
        except asyncio.CancelledError:
            pass
        finally:
            await self.stop()
    
    async def _on_audio_data(self, message: AudioDataMessage) -> None:
        """Handle incoming audio data from Swift client."""
        await self.transcription_service.process_audio(
            samples=message.samples,
            source=message.source,
            timestamp=message.timestamp
        )
    
    async def _on_transcription(self, result: TranscriptionResult) -> None:
        """Handle transcription result and send to Swift client."""
        logger.debug(f"Sending to Swift: [{result.source.value}] '{result.text}'")
        transcription_msg = TranscriptionMessage(
            text=result.text,
            source=result.source.value,
            timestamp=result.timestamp,
            confidence=result.confidence
        )
        await self.ipc_server.send_transcription(transcription_msg)
    
    async def _on_llm_query(self, message: LLMQueryMessage) -> LLMResponseMessage:
        """
        Handle LLM query from Swift client.
        
        Requirements: 7.1, 7.2, 7.3, 7.4
        """
        logger.info(f"Received LLM query: {message.query_type} - {message.content[:50]}...")
        
        try:
            response = await self.llm_service.process_query(
                query_type=message.query_type,
                content=message.content,
                context=message.context
            )
            
            return LLMResponseMessage(
                content=response.content,
                model=response.model,
                tokens_used=response.tokens_used
            )
            
        except OllamaUnavailableError:
            logger.error("Ollama service unavailable")
            return LLMResponseMessage(
                content="Error: Ollama service is unavailable. Please ensure Ollama is running.",
                model="error",
                tokens_used=0
            )
        except LLMError as e:
            logger.error(f"LLM error: {e}")
            return LLMResponseMessage(
                content=f"Error: {str(e)}",
                model="error",
                tokens_used=0
            )


async def main():
    """Main entry point."""
    backend = DevEchoBackend()
    
    # Set up signal handlers
    loop = asyncio.get_event_loop()
    
    def signal_handler():
        logger.info("Received shutdown signal")
        asyncio.create_task(backend.stop())
    
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, signal_handler)
    
    await backend.run()


if __name__ == "__main__":
    asyncio.run(main())
