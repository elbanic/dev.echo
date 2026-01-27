"""
dev.echo Backend Main Entry Point

Starts the IPC server with transcription service and LLM integration.
Supports both Phase 1 (local) and Phase 2 (cloud) services.
"""

import argparse
import asyncio
import logging
import os
import signal
import sys
from pathlib import Path
from typing import Optional, Union


def setup_logging():
    """
    Configure logging for the backend.
    
    Sets up logging format and suppresses verbose logs from external libraries
    (strands, boto3, etc.) to keep the output clean.
    """
    # Get log level from environment variable (default: INFO)
    log_level_str = os.getenv("DEVECHO_LOG_LEVEL", "INFO").upper()
    log_level = getattr(logging, log_level_str, logging.INFO)
    
    # Set up basic logging format
    logging.basicConfig(
        level=log_level,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%H:%M:%S"
    )
    
    # Suppress verbose logs from external libraries
    logging.getLogger("strands").setLevel(logging.WARNING)
    logging.getLogger("strands_tools").setLevel(logging.WARNING)
    logging.getLogger("boto3").setLevel(logging.WARNING)
    logging.getLogger("botocore").setLevel(logging.WARNING)
    logging.getLogger("urllib3").setLevel(logging.WARNING)
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("httpcore").setLevel(logging.WARNING)


# Initialize logging before importing other modules
setup_logging()

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
    KBErrorMessage,
    # Phase 2 messages
    CloudLLMQueryMessage,
    CloudLLMResponseMessage,
    CloudLLMErrorMessage,
    KBListRequestMessage,
    KBListResponseWithPaginationMessage,
    KBSyncStatusMessage,
    KBSyncTriggerResponseMessage,
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

# Phase 2 imports - lazy loaded to avoid boto3 credential lookup blocking
# when AWS is not configured
AWSConfig = None
S3DocumentManager = None
KnowledgeBaseService = None
CloudLLMService = None
CloudLLMHandler = None
S3KBHandler = None
KBSyncHandler = None


def _load_phase2_imports():
    """Lazy load Phase 2 imports to avoid boto3 blocking on startup."""
    global AWSConfig, S3DocumentManager, KnowledgeBaseService
    global CloudLLMService, CloudLLMHandler, S3KBHandler, KBSyncHandler
    
    from aws.config import AWSConfig as _AWSConfig
    from aws.s3_manager import S3DocumentManager as _S3DocumentManager
    from aws.kb_service import KnowledgeBaseService as _KnowledgeBaseService
    from aws.agents import CloudLLMService as _CloudLLMService
    from aws.handlers import (
        CloudLLMHandler as _CloudLLMHandler,
        S3KBHandler as _S3KBHandler,
        KBSyncHandler as _KBSyncHandler,
    )
    
    AWSConfig = _AWSConfig
    S3DocumentManager = _S3DocumentManager
    KnowledgeBaseService = _KnowledgeBaseService
    CloudLLMService = _CloudLLMService
    CloudLLMHandler = _CloudLLMHandler
    S3KBHandler = _S3KBHandler
    KBSyncHandler = _KBSyncHandler

logger = logging.getLogger(__name__)


class DevEchoBackend:
    """
    Main backend application.
    
    Integrates IPC server with transcription service and LLM.
    Supports both Phase 1 (local) and Phase 2 (cloud) services.
    """
    
    def __init__(self, socket_path: Optional[str] = None):
        self.ipc_server = IPCServer(socket_path)
        self.transcription_service = TranscriptionService()
        self.llm_service = LLMService()
        self.kb_manager = KnowledgeBaseManager()
        self._running = False
        
        # Phase 2 services (initialized if configured)
        self._aws_config: Optional[AWSConfig] = None
        self._s3_manager: Optional[S3DocumentManager] = None
        self._kb_service: Optional[KnowledgeBaseService] = None
        self._cloud_llm_service: Optional[CloudLLMService] = None
        
        # Phase 2 handlers
        self._cloud_llm_handler: Optional[CloudLLMHandler] = None
        self._s3_kb_handler: Optional[S3KBHandler] = None
        self._kb_sync_handler: Optional[KBSyncHandler] = None
        
        # Phase 2 enabled flag
        self._phase2_enabled = False
    
    def _init_phase2_services(self) -> bool:
        """
        Initialize Phase 2 AWS services if configured.
        
        Requirements: 9.3, 9.4, 10.5 - Handle AWS credential errors gracefully
        
        Returns:
            True if Phase 2 services are initialized successfully
        """
        import os
        
        # Quick check for required environment variables BEFORE importing AWS modules
        # This avoids boto3 credential lookup blocking when AWS is not configured
        required_vars = ["DEVECHO_S3_BUCKET", "DEVECHO_KB_ID"]
        missing = [v for v in required_vars if not os.getenv(v)]
        
        if missing:
            logger.info(
                f"Phase 2 services not configured. Missing: {', '.join(missing)}. "
                "Using Phase 1 (local) services only."
            )
            return False
        
        # Now safe to load Phase 2 imports (AWS modules)
        _load_phase2_imports()
        
        try:
            # Load AWS configuration
            self._aws_config = AWSConfig.from_env()
            
            # Validate configuration (should pass since we checked env vars above)
            is_valid, _ = self._aws_config.validate()
            if not is_valid:
                # This shouldn't happen, but handle gracefully
                logger.warning("AWS config validation failed unexpectedly")
                return False
            
            logger.info("Initializing Phase 2 AWS services...")
            
            # Initialize S3 Document Manager
            self._s3_manager = S3DocumentManager(
                bucket_name=self._aws_config.s3_bucket,
                prefix=self._aws_config.s3_prefix,
                region=self._aws_config.aws_region,
            )
            
            # Initialize Knowledge Base Service
            # Note: data_source_id is required for sync operations
            import os
            data_source_id = os.getenv("DEVECHO_KB_DS_ID")
            self._kb_service = KnowledgeBaseService(
                knowledge_base_id=self._aws_config.knowledge_base_id,
                data_source_id=data_source_id,
                region=self._aws_config.aws_region,
            )
            
            # Check if debug mode is enabled
            is_debug = os.getenv("DEVECHO_LOG_LEVEL", "INFO").upper() == "DEBUG"
            
            # Initialize Cloud LLM Service
            self._cloud_llm_service = CloudLLMService(
                knowledge_base_id=self._aws_config.knowledge_base_id,
                model_id=self._aws_config.bedrock_model_id,
                region=self._aws_config.aws_region,
                debug=is_debug,
            )
            
            # Initialize handlers
            self._cloud_llm_handler = CloudLLMHandler(self._cloud_llm_service)
            self._s3_kb_handler = S3KBHandler(self._s3_manager, self._kb_service)
            self._kb_sync_handler = KBSyncHandler(self._kb_service)
            
            logger.info(
                f"Phase 2 services initialized: "
                f"bucket={self._aws_config.s3_bucket}, "
                f"kb_id={self._aws_config.knowledge_base_id}, "
                f"model={self._aws_config.bedrock_model_id}"
            )
            return True
            
        except Exception as e:
            logger.warning(
                f"Failed to initialize Phase 2 services: {e}. "
                "Using Phase 1 (local) services only."
            )
            return False
    
    async def start(self) -> None:
        """Start the backend services."""
        logger.info("Starting dev.echo backend...")
        
        # Initialize Phase 2 services if configured
        self._phase2_enabled = self._init_phase2_services()
        
        # Set up transcription callback
        self.transcription_service.set_transcription_callback(
            self._on_transcription
        )
        
        # Set up audio handler
        self.ipc_server.on_audio_data(self._on_audio_data)
        
        # Set up LLM query handler (Phase 1 - local)
        self.ipc_server.on_llm_query(self._on_llm_query)
        
        # Set up KB handlers (Phase 1 - local)
        self.ipc_server.on_kb_list(self._on_kb_list)
        self.ipc_server.on_kb_add(self._on_kb_add)
        self.ipc_server.on_kb_update(self._on_kb_update)
        self.ipc_server.on_kb_remove(self._on_kb_remove)
        
        # Set up Phase 2 handlers if enabled
        if self._phase2_enabled:
            self._register_phase2_handlers()
        
        # Start services
        await self.transcription_service.start()
        await self.llm_service.start()
        await self.ipc_server.start()
        
        self._running = True
        
        if self._phase2_enabled:
            logger.info("dev.echo backend started (Phase 1 + Phase 2)")
        else:
            logger.info("dev.echo backend started (Phase 1 only)")
    
    def _register_phase2_handlers(self) -> None:
        """Register Phase 2 handlers with IPC server."""
        logger.info("Registering Phase 2 handlers...")
        
        # Cloud LLM handler
        self.ipc_server.on_cloud_llm_query(
            self._cloud_llm_handler.handle_cloud_llm_query
        )
        
        # S3-based KB handlers (override Phase 1 handlers)
        self.ipc_server.on_kb_list_paginated(
            self._s3_kb_handler.handle_kb_list
        )
        self.ipc_server.on_s3_kb_add(
            self._s3_kb_handler.handle_kb_add
        )
        self.ipc_server.on_s3_kb_update(
            self._s3_kb_handler.handle_kb_update
        )
        self.ipc_server.on_s3_kb_remove(
            self._s3_kb_handler.handle_kb_remove
        )
        
        # KB sync handlers
        self.ipc_server.on_kb_sync_status(
            self._kb_sync_handler.handle_sync_status
        )
        self.ipc_server.on_kb_sync_trigger(
            self._kb_sync_handler.handle_sync_trigger
        )
        
        logger.info("Phase 2 handlers registered")
    
    async def stop(self) -> None:
        """Stop the backend services."""
        logger.info("Stopping dev.echo backend...")
        self._running = False
        
        await self.ipc_server.stop()
        await self.transcription_service.stop()
        await self.llm_service.stop()
        
        # Shutdown Phase 2 services if enabled
        if self._phase2_enabled and self._cloud_llm_service:
            await self._cloud_llm_service.shutdown()
        
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
