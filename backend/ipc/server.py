"""
Unix Domain Socket IPC Server

Handles communication between Swift CLI and Python backend.
"""

import asyncio
import json
import logging
import os
from pathlib import Path
from typing import Callable, Optional, Awaitable

from .protocol import (
    MessageType,
    IPCMessage,
    AudioDataMessage,
    TranscriptionMessage,
    LLMQueryMessage,
    LLMResponseMessage,
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
        
        # Message handlers
        self._audio_handler: Optional[Callable[[AudioDataMessage], Awaitable[None]]] = None
        self._llm_query_handler: Optional[Callable[[LLMQueryMessage], Awaitable[LLMResponseMessage]]] = None
    
    def on_audio_data(self, handler: Callable[[AudioDataMessage], Awaitable[None]]):
        """Register handler for audio data messages."""
        self._audio_handler = handler
    
    def on_llm_query(self, handler: Callable[[LLMQueryMessage], Awaitable[LLMResponseMessage]]):
        """Register handler for LLM query messages."""
        self._llm_query_handler = handler
    
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
        
        elif message.type == MessageType.SHUTDOWN:
            await self.stop()
