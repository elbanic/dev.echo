"""
Phase 2 IPC Handlers

Handlers for Cloud LLM and S3-based KB operations.
Integrates Phase 2 services with the IPC server.

Requirements: 2.1-2.4, 3.1-3.5, 4.1-4.4, 5.1-5.3, 6.1, 6.2, 11.3, 11.5
"""

import logging
from pathlib import Path
from typing import Optional

from ipc.protocol import (
    CloudLLMQueryMessage,
    CloudLLMResponseMessage,
    CloudLLMErrorMessage,
    KBListRequestMessage,
    KBListResponseWithPaginationMessage,
    KBAddMessage,
    KBUpdateMessage,
    KBRemoveMessage,
    KBResponseMessage,
    KBErrorMessage,
    KBSyncStatusMessage,
    KBSyncTriggerResponseMessage,
)
from .agents import (
    CloudLLMService,
    ConversationContext,
    TranscriptContext,
    CloudLLMError,
    BedrockUnavailableError,
    BedrockAccessDeniedError,
    CloudQueryTimeoutError,
)
from .s3_manager import (
    S3DocumentManager,
    S3DocumentError,
    DocumentNotFoundError,
    DocumentExistsError,
    InvalidMarkdownError,
)
from .kb_service import (
    KnowledgeBaseService,
    KBServiceError,
    KBNotFoundError,
    KBAccessDeniedError,
    KBSyncError,
)
from .config import AWSConfig

logger = logging.getLogger(__name__)


class CloudLLMHandler:
    """
    Handler for Cloud LLM IPC messages.
    
    Processes CLOUD_LLM_QUERY messages and routes them to CloudLLMService.
    
    Requirements: 6.1, 6.2
    """
    
    def __init__(self, cloud_llm_service: CloudLLMService):
        """
        Initialize CloudLLMHandler.
        
        Args:
            cloud_llm_service: Initialized CloudLLMService instance
        """
        self.cloud_llm_service = cloud_llm_service
    
    def _build_conversation_context(
        self,
        query_msg: CloudLLMQueryMessage
    ) -> ConversationContext:
        """
        Build ConversationContext from IPC message.
        
        Args:
            query_msg: CloudLLMQueryMessage from IPC
            
        Returns:
            ConversationContext for CloudLLMService
        """
        # Convert context dicts to TranscriptContext objects
        transcript = []
        for entry in query_msg.context:
            transcript.append(TranscriptContext(
                text=entry.get("text", ""),
                source=entry.get("source", "microphone"),
                timestamp=entry.get("timestamp", 0.0),
            ))
        
        return ConversationContext(
            transcript=transcript,
            user_query=query_msg.content,
        )
    
    async def handle_cloud_llm_query(
        self,
        query_msg: CloudLLMQueryMessage
    ) -> CloudLLMResponseMessage | CloudLLMErrorMessage:
        """
        Handle CLOUD_LLM_QUERY message.
        
        Requirements: 6.1 - Send query with context to Cloud LLM
        Requirements: 6.2 - Display response in transcript
        
        Args:
            query_msg: CloudLLMQueryMessage from IPC
            
        Returns:
            CloudLLMResponseMessage on success, CloudLLMErrorMessage on failure
        """
        logger.info(f"Processing Cloud LLM query: {query_msg.content[:50]}...")
        
        try:
            # Build conversation context from IPC message
            context = self._build_conversation_context(query_msg)
            
            # Route to CloudLLMService
            response = await self.cloud_llm_service.query(
                context=context,
                force_rag=query_msg.force_rag,
            )
            
            logger.info(
                f"Cloud LLM query successful: {len(response.content)} chars, "
                f"{len(response.sources)} sources"
            )
            
            return CloudLLMResponseMessage(
                content=response.content,
                model=response.model,
                sources=response.sources,
                tokens_used=response.tokens_used,
                used_rag=response.used_rag,
            )
            
        except BedrockAccessDeniedError as e:
            logger.error(f"Bedrock access denied: {e}")
            return CloudLLMErrorMessage(
                error=str(e),
                error_type="credentials",
                suggestion="Check AWS credentials and IAM permissions. Run 'aws configure' to set up.",
            )
            
        except BedrockUnavailableError as e:
            logger.error(f"Bedrock unavailable: {e}")
            return CloudLLMErrorMessage(
                error=str(e),
                error_type="service_unavailable",
                suggestion="Try /quick for local LLM instead.",
            )
            
        except CloudQueryTimeoutError as e:
            logger.error(f"Cloud LLM query timeout: {e}")
            return CloudLLMErrorMessage(
                error=str(e),
                error_type="timeout",
                suggestion="Try a shorter query or use /quick for faster local LLM.",
            )
            
        except CloudLLMError as e:
            logger.error(f"Cloud LLM error: {e}")
            return CloudLLMErrorMessage(
                error=str(e),
                error_type="other",
                suggestion="Try /quick for local LLM instead.",
            )
            
        except Exception as e:
            logger.exception(f"Unexpected error in Cloud LLM handler: {e}")
            return CloudLLMErrorMessage(
                error=f"Unexpected error: {e}",
                error_type="other",
                suggestion="Try /quick for local LLM instead.",
            )


class S3KBHandler:
    """
    Handler for S3-based KB IPC messages.
    
    Processes KB_LIST, KB_ADD, KB_UPDATE, KB_REMOVE messages
    using S3DocumentManager.
    
    Requirements: 2.1-2.4, 3.1-3.5, 4.1-4.4, 5.1-5.3
    """
    
    def __init__(
        self,
        s3_manager: S3DocumentManager,
        kb_service: Optional[KnowledgeBaseService] = None
    ):
        """
        Initialize S3KBHandler.
        
        Args:
            s3_manager: Initialized S3DocumentManager instance
            kb_service: Optional KnowledgeBaseService for sync triggers
        """
        self.s3_manager = s3_manager
        self.kb_service = kb_service
    
    async def handle_kb_list(
        self,
        request_msg: Optional[KBListRequestMessage] = None
    ) -> KBListResponseWithPaginationMessage | KBErrorMessage:
        """
        Handle KB_LIST message with pagination support.
        
        Requirements: 2.1-2.4 - List documents with pagination and sorting
        
        Args:
            request_msg: Optional KBListRequestMessage with pagination params
            
        Returns:
            KBListResponseWithPaginationMessage on success, KBErrorMessage on failure
        """
        logger.info("Processing KB list request")
        
        try:
            # Get pagination params from request
            max_items = 20
            continuation_token = None
            
            if request_msg:
                max_items = request_msg.max_items
                continuation_token = request_msg.continuation_token
            
            # List documents from S3
            documents, next_token = await self.s3_manager.list_documents(
                max_items=max_items,
                continuation_token=continuation_token,
            )
            
            # Convert to dict format for IPC
            doc_dicts = [doc.to_dict() for doc in documents]
            
            logger.info(f"Listed {len(documents)} documents, has_more={next_token is not None}")
            
            return KBListResponseWithPaginationMessage(
                documents=doc_dicts,
                has_more=next_token is not None,
                continuation_token=next_token,
            )
            
        except S3DocumentError as e:
            logger.error(f"S3 list error: {e}")
            return KBErrorMessage(
                error=str(e),
                error_type="other",
            )
            
        except Exception as e:
            logger.exception(f"Unexpected error in KB list handler: {e}")
            return KBErrorMessage(
                error=f"Unexpected error: {e}",
                error_type="other",
            )
    
    async def handle_kb_add(
        self,
        add_msg: KBAddMessage
    ) -> KBResponseMessage | KBErrorMessage:
        """
        Handle KB_ADD message.
        
        Requirements: 3.1-3.5 - Add document to S3
        
        Args:
            add_msg: KBAddMessage with source_path and name
            
        Returns:
            KBResponseMessage on success, KBErrorMessage on failure
        """
        logger.info(f"Processing KB add: {add_msg.name} from {add_msg.source_path}")
        
        try:
            source_path = Path(add_msg.source_path).expanduser()
            
            # Check if source file exists
            if not source_path.exists():
                return KBErrorMessage(
                    error=f"Source file not found: {add_msg.source_path}",
                    error_type="not_found",
                )
            
            # Add document to S3
            doc = await self.s3_manager.add_document(
                source_path=source_path,
                name=add_msg.name,
            )
            
            logger.info(f"Added document: {doc.name} ({doc.size_bytes} bytes)")
            
            return KBResponseMessage(
                success=True,
                message=f"Added: {doc.name} ({doc.size_bytes} bytes)",
                document=doc.to_dict(),
            )
            
        except InvalidMarkdownError as e:
            logger.error(f"Invalid markdown: {e}")
            return KBErrorMessage(
                error=str(e),
                error_type="invalid_markdown",
            )
            
        except DocumentExistsError as e:
            logger.error(f"Document exists: {e}")
            return KBErrorMessage(
                error=str(e),
                error_type="exists",
            )
            
        except S3DocumentError as e:
            logger.error(f"S3 add error: {e}")
            return KBErrorMessage(
                error=str(e),
                error_type="other",
            )
            
        except Exception as e:
            logger.exception(f"Unexpected error in KB add handler: {e}")
            return KBErrorMessage(
                error=f"Unexpected error: {e}",
                error_type="other",
            )
    
    async def handle_kb_update(
        self,
        update_msg: KBUpdateMessage
    ) -> KBResponseMessage | KBErrorMessage:
        """
        Handle KB_UPDATE message.
        
        Requirements: 4.1-4.4 - Update document in S3
        
        Args:
            update_msg: KBUpdateMessage with source_path and name
            
        Returns:
            KBResponseMessage on success, KBErrorMessage on failure
        """
        logger.info(f"Processing KB update: {update_msg.name} from {update_msg.source_path}")
        
        try:
            source_path = Path(update_msg.source_path).expanduser()
            
            # Check if source file exists
            if not source_path.exists():
                return KBErrorMessage(
                    error=f"Source file not found: {update_msg.source_path}",
                    error_type="not_found",
                )
            
            # Update document in S3
            doc = await self.s3_manager.update_document(
                source_path=source_path,
                name=update_msg.name,
            )
            
            logger.info(f"Updated document: {doc.name} ({doc.size_bytes} bytes)")
            
            return KBResponseMessage(
                success=True,
                message=f"Updated: {doc.name} ({doc.size_bytes} bytes)",
                document=doc.to_dict(),
            )
            
        except InvalidMarkdownError as e:
            logger.error(f"Invalid markdown: {e}")
            return KBErrorMessage(
                error=str(e),
                error_type="invalid_markdown",
            )
            
        except DocumentNotFoundError as e:
            logger.error(f"Document not found: {e}")
            return KBErrorMessage(
                error=f"{e}. Use /add instead.",
                error_type="not_found",
            )
            
        except S3DocumentError as e:
            logger.error(f"S3 update error: {e}")
            return KBErrorMessage(
                error=str(e),
                error_type="other",
            )
            
        except Exception as e:
            logger.exception(f"Unexpected error in KB update handler: {e}")
            return KBErrorMessage(
                error=f"Unexpected error: {e}",
                error_type="other",
            )
    
    async def handle_kb_remove(
        self,
        remove_msg: KBRemoveMessage
    ) -> KBResponseMessage | KBErrorMessage:
        """
        Handle KB_REMOVE message.
        
        Requirements: 5.1-5.3 - Remove document from S3 and trigger KB sync
        
        Args:
            remove_msg: KBRemoveMessage with document name
            
        Returns:
            KBResponseMessage on success, KBErrorMessage on failure
        """
        logger.info(f"Processing KB remove: {remove_msg.name}")
        
        try:
            # Remove document from S3
            await self.s3_manager.remove_document(name=remove_msg.name)
            
            # Trigger KB sync if service is available
            sync_message = ""
            if self.kb_service:
                try:
                    job_id = await self.kb_service.start_sync()
                    sync_message = f" KB sync started (job: {job_id})"
                    logger.info(f"KB sync triggered: {job_id}")
                except KBSyncError as e:
                    sync_message = f" KB sync skipped: {e}"
                    logger.warning(f"KB sync failed: {e}")
                except Exception as e:
                    sync_message = f" KB sync failed: {e}"
                    logger.warning(f"KB sync error: {e}")
            
            logger.info(f"Removed document: {remove_msg.name}")
            
            return KBResponseMessage(
                success=True,
                message=f"Removed: {remove_msg.name}.{sync_message}",
                document=None,
            )
            
        except DocumentNotFoundError as e:
            logger.error(f"Document not found: {e}")
            return KBErrorMessage(
                error=str(e),
                error_type="not_found",
            )
            
        except S3DocumentError as e:
            logger.error(f"S3 remove error: {e}")
            return KBErrorMessage(
                error=str(e),
                error_type="other",
            )
            
        except Exception as e:
            logger.exception(f"Unexpected error in KB remove handler: {e}")
            return KBErrorMessage(
                error=f"Unexpected error: {e}",
                error_type="other",
            )


class KBSyncHandler:
    """
    Handler for KB sync status IPC messages.
    
    Processes KB_SYNC_STATUS messages using KnowledgeBaseService.
    
    Requirements: 11.3, 11.5
    """
    
    def __init__(self, kb_service: KnowledgeBaseService):
        """
        Initialize KBSyncHandler.
        
        Args:
            kb_service: Initialized KnowledgeBaseService instance
        """
        self.kb_service = kb_service
    
    async def handle_sync_status(self) -> KBSyncStatusMessage | KBErrorMessage:
        """
        Handle KB_SYNC_STATUS message.
        
        Requirements: 11.3, 11.5 - Return sync status and verify connectivity
        
        Returns:
            KBSyncStatusMessage on success, KBErrorMessage on failure
        """
        logger.info("Processing KB sync status request")
        
        try:
            # Get sync status from KB service
            status = await self.kb_service.get_sync_status()
            
            logger.info(
                f"KB sync status: {status.status}, "
                f"documents={status.document_count}"
            )
            
            return KBSyncStatusMessage(
                status=status.status,
                document_count=status.document_count,
                last_sync=status.last_sync,
                error_message=status.error_message,
            )
            
        except KBNotFoundError as e:
            logger.error(f"KB not found: {e}")
            return KBErrorMessage(
                error=str(e),
                error_type="not_found",
            )
            
        except KBAccessDeniedError as e:
            logger.error(f"KB access denied: {e}")
            return KBErrorMessage(
                error=str(e),
                error_type="access_denied",
            )
            
        except KBServiceError as e:
            logger.error(f"KB service error: {e}")
            return KBErrorMessage(
                error=str(e),
                error_type="other",
            )
            
        except Exception as e:
            logger.exception(f"Unexpected error in KB sync status handler: {e}")
            return KBErrorMessage(
                error=f"Unexpected error: {e}",
                error_type="other",
            )
    
    async def handle_sync_trigger(self) -> KBSyncTriggerResponseMessage | KBErrorMessage:
        """
        Handle KB_SYNC_TRIGGER message.
        
        Requirements: 5.2, 11.2 - Trigger KB reindexing
        
        Returns:
            KBSyncTriggerResponseMessage on success, KBErrorMessage on failure
        """
        logger.info("Processing KB sync trigger request")
        
        try:
            # Trigger sync
            job_id = await self.kb_service.start_sync()
            
            logger.info(f"KB sync triggered: {job_id}")
            
            return KBSyncTriggerResponseMessage(
                success=True,
                ingestion_job_id=job_id,
                message=f"Sync started (job: {job_id})",
            )
            
        except KBSyncError as e:
            logger.error(f"KB sync error: {e}")
            return KBSyncTriggerResponseMessage(
                success=False,
                ingestion_job_id=e.job_id,
                message=str(e),
            )
            
        except KBNotFoundError as e:
            logger.error(f"KB not found: {e}")
            return KBErrorMessage(
                error=str(e),
                error_type="not_found",
            )
            
        except KBAccessDeniedError as e:
            logger.error(f"KB access denied: {e}")
            return KBErrorMessage(
                error=str(e),
                error_type="access_denied",
            )
            
        except Exception as e:
            logger.exception(f"Unexpected error in KB sync trigger handler: {e}")
            return KBErrorMessage(
                error=f"Unexpected error: {e}",
                error_type="other",
            )
