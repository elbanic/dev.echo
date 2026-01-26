"""
dev.echo Backend Main Entry Point

Starts the IPC server with transcription service and LLM integration.
"""

import argparse
import asyncio
import logging
import signal
import sys
from pathlib import Path
from typing import Optional

from ipc.server import IPCServer
from ipc.protocol import (
    AudioDataMessage,
    TranscriptionMessage,
    LLMQueryMessage,
    LLMResponseMessage,
    KBAddMessage,
    KBUpdateMessage,
    KBRemoveMessage,
    KBListResponseMessage,
    KBResponseMessage,
)
from transcription import TranscriptionService, TranscriptionResult
from llm import LLMService, OllamaUnavailableError, LLMError
from kb import (
    KnowledgeBaseManager,
    DocumentNotFoundError,
    InvalidMarkdownError,
    DocumentExistsError,
    KBError,
)

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
        self.kb_manager = KnowledgeBaseManager()
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
        
        # Set up KB handlers
        self.ipc_server.on_kb_list(self._on_kb_list)
        self.ipc_server.on_kb_add(self._on_kb_add)
        self.ipc_server.on_kb_update(self._on_kb_update)
        self.ipc_server.on_kb_remove(self._on_kb_remove)
        
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
    
    async def _on_kb_list(self) -> KBListResponseMessage:
        """
        Handle KB list request.
        
        Requirements: 4.1 - Display all documents in knowledge base
        """
        logger.info("Received KB list request")
        
        try:
            documents = await self.kb_manager.list_documents()
            doc_dicts = [doc.to_dict() for doc in documents]
            
            return KBListResponseMessage(documents=doc_dicts)
            
        except Exception as e:
            logger.error(f"KB list error: {e}")
            return KBListResponseMessage(documents=[])
    
    async def _on_kb_add(self, message: KBAddMessage) -> KBResponseMessage:
        """
        Handle KB add request.
        
        Requirements: 4.4, 4.5 - Add markdown file with validation
        """
        logger.info(f"Received KB add request: {message.name} from {message.source_path}")
        
        try:
            doc = await self.kb_manager.add_document(
                source_path=Path(message.source_path),
                name=message.name
            )
            
            return KBResponseMessage(
                success=True,
                message=f"Added document: {doc.name}",
                document=doc.to_dict()
            )
            
        except InvalidMarkdownError as e:
            logger.error(f"Invalid markdown: {e}")
            return KBResponseMessage(
                success=False,
                message=str(e),
                document=None
            )
        except DocumentExistsError as e:
            logger.error(f"Document exists: {e}")
            return KBResponseMessage(
                success=False,
                message=str(e),
                document=None
            )
        except KBError as e:
            logger.error(f"KB error: {e}")
            return KBResponseMessage(
                success=False,
                message=str(e),
                document=None
            )
    
    async def _on_kb_update(self, message: KBUpdateMessage) -> KBResponseMessage:
        """
        Handle KB update request.
        
        Requirements: 4.3 - Update existing document
        """
        logger.info(f"Received KB update request: {message.name} from {message.source_path}")
        
        try:
            doc = await self.kb_manager.update_document(
                source_path=Path(message.source_path),
                name=message.name
            )
            
            return KBResponseMessage(
                success=True,
                message=f"Updated document: {doc.name}",
                document=doc.to_dict()
            )
            
        except DocumentNotFoundError as e:
            logger.error(f"Document not found: {e}")
            return KBResponseMessage(
                success=False,
                message=str(e),
                document=None
            )
        except InvalidMarkdownError as e:
            logger.error(f"Invalid markdown: {e}")
            return KBResponseMessage(
                success=False,
                message=str(e),
                document=None
            )
        except KBError as e:
            logger.error(f"KB error: {e}")
            return KBResponseMessage(
                success=False,
                message=str(e),
                document=None
            )
    
    async def _on_kb_remove(self, message: KBRemoveMessage) -> KBResponseMessage:
        """
        Handle KB remove request.
        
        Requirements: 4.2 - Delete document with specified filename
        """
        logger.info(f"Received KB remove request: {message.name}")
        
        try:
            await self.kb_manager.remove_document(name=message.name)
            
            return KBResponseMessage(
                success=True,
                message=f"Removed document: {message.name}",
                document=None
            )
            
        except DocumentNotFoundError as e:
            logger.error(f"Document not found: {e}")
            return KBResponseMessage(
                success=False,
                message=str(e),
                document=None
            )
        except KBError as e:
            logger.error(f"KB error: {e}")
            return KBResponseMessage(
                success=False,
                message=str(e),
                document=None
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
