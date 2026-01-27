"""
Unix Domain Socket IPC Server

Handles communication between Swift CLI and Python backend.
"""

import asyncio
import json
import logging
import os
from pathlib import Path
from typing import Callable, Optional, Awaitable, Union

from .protocol import (
    MessageType,
    IPCMessage,
    AudioDataMessage,
    TranscriptionMessage,
    LLMQueryMessage,
    LLMResponseMessage,
    KBListMessage,
    KBListResponseMessage,
    KBAddMessage,
    KBUpdateMessage,
    KBRemoveMessage,
    KBResponseMessage,
    KBErrorMessage,
    # Phase 2 messages
    CloudLLMQueryMessage,
    CloudLLMResponseMessage,
    CloudLLMErrorMessage,
    KBListRequestMessage,
    KBListResponseWithPaginationMessage,
    KBSyncStatusMessage,
    KBSyncTriggerMessage,
    KBSyncTriggerResponseMessage,
)

logger = logging.getLogger(__name__)


class IPCServer:
    """Unix Domain Socket server for Swift-Python IPC."""
    
    DEFAULT_SOCKET_PATH = "/tmp/devecho.sock"
    
    def __init__(self, socket_path: Optional[str] = None):
        self.socket_path = socket_path or self.DEFAULT_SOCKET_PATH
        self.server: Optional[asyncio.Server] = None
        self.clients: list[asyncio.StreamWriter] = []
        self._running = False
        
        # Phase 1 message handlers
        self._audio_handler: Optional[Callable[[AudioDataMessage], Awaitable[None]]] = None
        self._llm_query_handler: Optional[Callable[[LLMQueryMessage], Awaitable[LLMResponseMessage]]] = None
        self._kb_list_handler: Optional[Callable[[], Awaitable[KBListResponseMessage]]] = None
        self._kb_add_handler: Optional[Callable[[KBAddMessage], Awaitable[KBResponseMessage]]] = None
        self._kb_update_handler: Optional[Callable[[KBUpdateMessage], Awaitable[KBResponseMessage]]] = None
        self._kb_remove_handler: Optional[Callable[[KBRemoveMessage], Awaitable[KBResponseMessage]]] = None
        
        # Phase 2 message handlers
        self._cloud_llm_query_handler: Optional[
            Callable[[CloudLLMQueryMessage], Awaitable[Union[CloudLLMResponseMessage, CloudLLMErrorMessage]]]
        ] = None
        self._kb_list_paginated_handler: Optional[
            Callable[[KBListRequestMessage], Awaitable[Union[KBListResponseWithPaginationMessage, KBErrorMessage]]]
        ] = None
        self._kb_sync_status_handler: Optional[
            Callable[[], Awaitable[Union[KBSyncStatusMessage, KBErrorMessage]]]
        ] = None
        self._kb_sync_trigger_handler: Optional[
            Callable[[], Awaitable[Union[KBSyncTriggerResponseMessage, KBErrorMessage]]]
        ] = None
        
        # Phase 2 S3-based KB handlers (override Phase 1 handlers)
        self._s3_kb_add_handler: Optional[
            Callable[[KBAddMessage], Awaitable[Union[KBResponseMessage, KBErrorMessage]]]
        ] = None
        self._s3_kb_update_handler: Optional[
            Callable[[KBUpdateMessage], Awaitable[Union[KBResponseMessage, KBErrorMessage]]]
        ] = None
        self._s3_kb_remove_handler: Optional[
            Callable[[KBRemoveMessage], Awaitable[Union[KBResponseMessage, KBErrorMessage]]]
        ] = None
    
    def on_audio_data(self, handler: Callable[[AudioDataMessage], Awaitable[None]]):
        """Register handler for audio data messages."""
        self._audio_handler = handler
    
    def on_llm_query(self, handler: Callable[[LLMQueryMessage], Awaitable[LLMResponseMessage]]):
        """Register handler for LLM query messages."""
        self._llm_query_handler = handler
    
    def on_kb_list(self, handler: Callable[[], Awaitable[KBListResponseMessage]]):
        """Register handler for KB list messages."""
        self._kb_list_handler = handler
    
    def on_kb_add(self, handler: Callable[[KBAddMessage], Awaitable[KBResponseMessage]]):
        """Register handler for KB add messages."""
        self._kb_add_handler = handler
    
    def on_kb_update(self, handler: Callable[[KBUpdateMessage], Awaitable[KBResponseMessage]]):
        """Register handler for KB update messages."""
        self._kb_update_handler = handler
    
    def on_kb_remove(self, handler: Callable[[KBRemoveMessage], Awaitable[KBResponseMessage]]):
        """Register handler for KB remove messages."""
        self._kb_remove_handler = handler
    
    # Phase 2 handler registration methods
    
    def on_cloud_llm_query(
        self,
        handler: Callable[[CloudLLMQueryMessage], Awaitable[Union[CloudLLMResponseMessage, CloudLLMErrorMessage]]]
    ):
        """Register handler for Cloud LLM query messages (Phase 2)."""
        self._cloud_llm_query_handler = handler
    
    def on_kb_list_paginated(
        self,
        handler: Callable[[KBListRequestMessage], Awaitable[Union[KBListResponseWithPaginationMessage, KBErrorMessage]]]
    ):
        """Register handler for paginated KB list messages (Phase 2)."""
        self._kb_list_paginated_handler = handler
    
    def on_kb_sync_status(
        self,
        handler: Callable[[], Awaitable[Union[KBSyncStatusMessage, KBErrorMessage]]]
    ):
        """Register handler for KB sync status messages (Phase 2)."""
        self._kb_sync_status_handler = handler
    
    def on_kb_sync_trigger(
        self,
        handler: Callable[[], Awaitable[Union[KBSyncTriggerResponseMessage, KBErrorMessage]]]
    ):
        """Register handler for KB sync trigger messages (Phase 2)."""
        self._kb_sync_trigger_handler = handler
    
    def on_s3_kb_add(
        self,
        handler: Callable[[KBAddMessage], Awaitable[Union[KBResponseMessage, KBErrorMessage]]]
    ):
        """Register S3-based handler for KB add messages (Phase 2)."""
        self._s3_kb_add_handler = handler
    
    def on_s3_kb_update(
        self,
        handler: Callable[[KBUpdateMessage], Awaitable[Union[KBResponseMessage, KBErrorMessage]]]
    ):
        """Register S3-based handler for KB update messages (Phase 2)."""
        self._s3_kb_update_handler = handler
    
    def on_s3_kb_remove(
        self,
        handler: Callable[[KBRemoveMessage], Awaitable[Union[KBResponseMessage, KBErrorMessage]]]
    ):
        """Register S3-based handler for KB remove messages (Phase 2)."""
        self._s3_kb_remove_handler = handler
    
    async def send_transcription(self, transcription: TranscriptionMessage):
        """Send transcription result to all connected clients."""
        logger.debug(f"Broadcasting transcription to {len(self.clients)} clients")
        await self.broadcast(transcription.to_ipc_message())
    
    async def start(self):
        """Start the IPC server."""
        # Remove existing socket file if present
        if os.path.exists(self.socket_path):
            os.unlink(self.socket_path)
        
        self.server = await asyncio.start_unix_server(
            self._handle_client,
            path=self.socket_path
        )
        self._running = True
        
        # Set socket permissions
        os.chmod(self.socket_path, 0o600)
        
        logger.info(f"IPC server started at {self.socket_path}")
    
    async def stop(self):
        """Stop the IPC server."""
        self._running = False
        
        # Close all client connections
        for writer in self.clients:
            writer.close()
            await writer.wait_closed()
        self.clients.clear()
        
        # Close server
        if self.server:
            self.server.close()
            await self.server.wait_closed()
        
        # Remove socket file
        if os.path.exists(self.socket_path):
            os.unlink(self.socket_path)
        
        logger.info("IPC server stopped")
    
    async def broadcast(self, message: IPCMessage):
        """Send message to all connected clients."""
        data = message.to_json().encode() + b"\n"
        for writer in self.clients:
            try:
                writer.write(data)
                await writer.drain()
            except Exception as e:
                logger.error(f"Failed to send message to client: {e}")
    
    async def _handle_client(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter
    ):
        """Handle a connected client."""
        self.clients.append(writer)
        logger.info("Client connected")
        
        try:
            buffer = b""
            while self._running:
                # Read data in chunks
                try:
                    chunk = await asyncio.wait_for(
                        reader.read(65536),  # 64KB chunks
                        timeout=1.0
                    )
                except asyncio.TimeoutError:
                    continue
                
                if not chunk:
                    break
                
                buffer += chunk
                
                # Process complete messages (newline-delimited)
                while b"\n" in buffer:
                    line, buffer = buffer.split(b"\n", 1)
                    if not line:
                        continue
                    
                    try:
                        message = IPCMessage.from_json(line.decode().strip())
                        await self._process_message(message, writer)
                    except json.JSONDecodeError as e:
                        logger.error(f"Invalid JSON message: {e}")
                    except Exception as e:
                        logger.error(f"Error processing message: {e}")
        
        except asyncio.CancelledError:
            pass
        except Exception as e:
            logger.error(f"Client handler error: {e}")
        finally:
            self.clients.remove(writer)
            writer.close()
            await writer.wait_closed()
            logger.info("Client disconnected")
    
    async def _process_message(self, message: IPCMessage, writer: asyncio.StreamWriter):
        """Process incoming message and send response if needed."""
        
        if message.type == MessageType.PING:
            response = IPCMessage(type=MessageType.PONG, payload={})
            writer.write(response.to_json().encode() + b"\n")
            await writer.drain()
        
        elif message.type == MessageType.AUDIO_DATA:
            if self._audio_handler:
                audio_msg = AudioDataMessage.from_payload(message.payload)
                await self._audio_handler(audio_msg)
        
        elif message.type == MessageType.LLM_QUERY:
            if self._llm_query_handler:
                query_msg = LLMQueryMessage.from_payload(message.payload)
                response = await self._llm_query_handler(query_msg)
                writer.write(response.to_ipc_message().to_json().encode() + b"\n")
                await writer.drain()
        
        elif message.type == MessageType.CLOUD_LLM_QUERY:
            # Phase 2: Cloud LLM query
            if self._cloud_llm_query_handler:
                query_msg = CloudLLMQueryMessage.from_payload(message.payload)
                response = await self._cloud_llm_query_handler(query_msg)
                writer.write(response.to_ipc_message().to_json().encode() + b"\n")
                await writer.drain()
        
        elif message.type == MessageType.KB_LIST:
            # Check for Phase 2 paginated handler first
            logger.info(f"KB_LIST received, paginated_handler={self._kb_list_paginated_handler is not None}")
            if self._kb_list_paginated_handler:
                request_msg = KBListRequestMessage.from_payload(message.payload)
                logger.info(f"Calling paginated handler with request: {request_msg}")
                response = await self._kb_list_paginated_handler(request_msg)
                logger.info(f"Paginated handler response: {response}")
                writer.write(response.to_ipc_message().to_json().encode() + b"\n")
                await writer.drain()
            elif self._kb_list_handler:
                # Fallback to Phase 1 handler
                response = await self._kb_list_handler()
                writer.write(response.to_ipc_message().to_json().encode() + b"\n")
                await writer.drain()
        
        elif message.type == MessageType.KB_ADD:
            # Check for Phase 2 S3 handler first
            if self._s3_kb_add_handler:
                add_msg = KBAddMessage.from_payload(message.payload)
                response = await self._s3_kb_add_handler(add_msg)
                writer.write(response.to_ipc_message().to_json().encode() + b"\n")
                await writer.drain()
            elif self._kb_add_handler:
                # Fallback to Phase 1 handler
                add_msg = KBAddMessage.from_payload(message.payload)
                response = await self._kb_add_handler(add_msg)
                writer.write(response.to_ipc_message().to_json().encode() + b"\n")
                await writer.drain()
        
        elif message.type == MessageType.KB_UPDATE:
            # Check for Phase 2 S3 handler first
            if self._s3_kb_update_handler:
                update_msg = KBUpdateMessage.from_payload(message.payload)
                response = await self._s3_kb_update_handler(update_msg)
                writer.write(response.to_ipc_message().to_json().encode() + b"\n")
                await writer.drain()
            elif self._kb_update_handler:
                # Fallback to Phase 1 handler
                update_msg = KBUpdateMessage.from_payload(message.payload)
                response = await self._kb_update_handler(update_msg)
                writer.write(response.to_ipc_message().to_json().encode() + b"\n")
                await writer.drain()
        
        elif message.type == MessageType.KB_REMOVE:
            # Check for Phase 2 S3 handler first
            if self._s3_kb_remove_handler:
                remove_msg = KBRemoveMessage.from_payload(message.payload)
                response = await self._s3_kb_remove_handler(remove_msg)
                writer.write(response.to_ipc_message().to_json().encode() + b"\n")
                await writer.drain()
            elif self._kb_remove_handler:
                # Fallback to Phase 1 handler
                remove_msg = KBRemoveMessage.from_payload(message.payload)
                response = await self._kb_remove_handler(remove_msg)
                writer.write(response.to_ipc_message().to_json().encode() + b"\n")
                await writer.drain()
        
        elif message.type == MessageType.KB_SYNC_STATUS:
            # Phase 2: KB sync status
            if self._kb_sync_status_handler:
                response = await self._kb_sync_status_handler()
                writer.write(response.to_ipc_message().to_json().encode() + b"\n")
                await writer.drain()
        
        elif message.type == MessageType.KB_SYNC_TRIGGER:
            # Phase 2: KB sync trigger
            if self._kb_sync_trigger_handler:
                response = await self._kb_sync_trigger_handler()
                writer.write(response.to_ipc_message().to_json().encode() + b"\n")
                await writer.drain()
        
        elif message.type == MessageType.SHUTDOWN:
            await self.stop()
