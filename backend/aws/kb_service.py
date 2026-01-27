"""
Knowledge Base Service

Manages Bedrock Knowledge Base operations including sync status,
connectivity checks, and sync triggers for document removal.

Requirements: 5.2, 7.1, 11.1, 11.2, 11.3, 11.5
"""

import logging
from dataclasses import dataclass
from typing import Optional

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger(__name__)


class KBServiceError(Exception):
    """Base exception for Knowledge Base Service errors."""
    pass


class KBNotFoundError(KBServiceError):
    """Raised when the Knowledge Base is not found."""
    
    def __init__(self, kb_id: str):
        self.kb_id = kb_id
        super().__init__(f"Knowledge Base not found: {kb_id}")


class KBAccessDeniedError(KBServiceError):
    """Raised when access to the Knowledge Base is denied."""
    
    def __init__(self, kb_id: str):
        self.kb_id = kb_id
        super().__init__(f"Access denied to Knowledge Base: {kb_id}")


class KBSyncError(KBServiceError):
    """Raised when a sync operation fails."""
    
    def __init__(self, message: str, job_id: Optional[str] = None):
        self.job_id = job_id
        super().__init__(message)


@dataclass
class SyncStatus:
    """
    Knowledge base sync status.
    
    Represents the current state of the Bedrock Knowledge Base
    including sync status and document count.
    """
    status: str  # "SYNCING", "READY", "FAILED", "UNKNOWN"
    last_sync: Optional[float]
    document_count: int
    error_message: Optional[str] = None
    
    def to_dict(self) -> dict:
        """Convert to dictionary for serialization."""
        return {
            "status": self.status,
            "last_sync": self.last_sync,
            "document_count": self.document_count,
            "error_message": self.error_message,
        }


@dataclass
class RetrievalResult:
    """
    Result from knowledge base retrieval.
    
    Represents a single document chunk retrieved from
    semantic search in Bedrock Knowledge Base.
    """
    content: str
    source: str
    score: float
    metadata: dict
    
    def to_dict(self) -> dict:
        """Convert to dictionary for serialization."""
        return {
            "content": self.content,
            "source": self.source,
            "score": self.score,
            "metadata": self.metadata,
        }


class KnowledgeBaseService:
    """
    Service for Bedrock Knowledge Base operations.
    
    Provides connectivity checks, sync status retrieval,
    and sync triggers for document removal.
    
    Requirements: 5.2, 7.1, 11.1, 11.2, 11.3, 11.5
    """
    
    def __init__(
        self,
        knowledge_base_id: str,
        data_source_id: Optional[str] = None,
        region: str = "us-west-2"
    ):
        """
        Initialize Knowledge Base Service.
        
        Args:
            knowledge_base_id: Bedrock Knowledge Base ID
            data_source_id: Optional data source ID for sync operations
            region: AWS region (default: us-west-2)
        """
        self.knowledge_base_id = knowledge_base_id
        self.data_source_id = data_source_id
        self.region = region
        
        # Initialize Bedrock clients
        # bedrock-agent: For KB management operations (sync, status)
        # bedrock-agent-runtime: For retrieval operations
        self.bedrock_agent = boto3.client(
            "bedrock-agent",
            region_name=region
        )
        self.bedrock_agent_runtime = boto3.client(
            "bedrock-agent-runtime",
            region_name=region
        )
        
        logger.debug(
            f"KnowledgeBaseService initialized: kb_id={knowledge_base_id}, "
            f"region={region}"
        )
    
    async def check_connectivity(self) -> bool:
        """
        Verify connection to Bedrock Knowledge Base.
        
        Requirements: 11.3, 11.5 - Startup connectivity verification
        
        Returns:
            True if connection is successful
            
        Raises:
            KBNotFoundError: If KB doesn't exist
            KBAccessDeniedError: If access is denied
            KBServiceError: For other errors
        """
        try:
            # Try to get KB details to verify connectivity
            response = self.bedrock_agent.get_knowledge_base(
                knowledgeBaseId=self.knowledge_base_id
            )
            
            kb_status = response.get("knowledgeBase", {}).get("status", "UNKNOWN")
            logger.info(
                f"KB connectivity check successful: {self.knowledge_base_id}, "
                f"status={kb_status}"
            )
            return True
            
        except ClientError as e:
            error_code = e.response["Error"]["Code"]
            error_message = e.response["Error"]["Message"]
            
            if error_code == "ResourceNotFoundException":
                logger.error(f"KB not found: {self.knowledge_base_id}")
                raise KBNotFoundError(self.knowledge_base_id)
            elif error_code == "AccessDeniedException":
                logger.error(f"KB access denied: {self.knowledge_base_id}")
                raise KBAccessDeniedError(self.knowledge_base_id)
            else:
                logger.error(f"KB connectivity error: {error_code} - {error_message}")
                raise KBServiceError(f"Failed to connect to KB: {error_message}")
    
    async def get_sync_status(self) -> SyncStatus:
        """
        Get current sync status of knowledge base.
        
        Requirements: 11.3, 11.5 - Display sync status and document count
        
        Returns:
            SyncStatus with current KB state
            
        Raises:
            KBServiceError: If status retrieval fails
        """
        try:
            # Get KB details
            kb_response = self.bedrock_agent.get_knowledge_base(
                knowledgeBaseId=self.knowledge_base_id
            )
            
            kb_info = kb_response.get("knowledgeBase", {})
            kb_status = kb_info.get("status", "UNKNOWN")
            
            # Map KB status to our status enum
            status_map = {
                "CREATING": "SYNCING",
                "ACTIVE": "READY",
                "DELETING": "SYNCING",
                "UPDATING": "SYNCING",
                "FAILED": "FAILED",
            }
            mapped_status = status_map.get(kb_status, "UNKNOWN")
            
            # Get document count from data source if available
            document_count = 0
            last_sync = None
            error_message = None
            
            if self.data_source_id:
                try:
                    ds_response = self.bedrock_agent.get_data_source(
                        knowledgeBaseId=self.knowledge_base_id,
                        dataSourceId=self.data_source_id
                    )
                    
                    ds_info = ds_response.get("dataSource", {})
                    
                    # Check for recent ingestion job status
                    ingestion_jobs = self._list_recent_ingestion_jobs()
                    if ingestion_jobs:
                        latest_job = ingestion_jobs[0]
                        job_status = latest_job.get("status", "")
                        
                        if job_status == "IN_PROGRESS":
                            mapped_status = "SYNCING"
                        elif job_status == "FAILED":
                            mapped_status = "FAILED"
                            error_message = latest_job.get("failureReasons", ["Unknown error"])[0]
                        
                        # Get last sync time from completed job
                        if job_status == "COMPLETE":
                            updated_at = latest_job.get("updatedAt")
                            if updated_at:
                                last_sync = updated_at.timestamp()
                        
                        # Get document count from statistics
                        stats = latest_job.get("statistics", {})
                        document_count = stats.get("numberOfDocumentsScanned", 0)
                        
                except ClientError as e:
                    logger.warning(f"Failed to get data source info: {e}")
            
            sync_status = SyncStatus(
                status=mapped_status,
                last_sync=last_sync,
                document_count=document_count,
                error_message=error_message,
            )
            
            logger.info(
                f"KB sync status: {sync_status.status}, "
                f"documents={sync_status.document_count}"
            )
            return sync_status
            
        except ClientError as e:
            error_code = e.response["Error"]["Code"]
            error_message = e.response["Error"]["Message"]
            
            if error_code == "ResourceNotFoundException":
                raise KBNotFoundError(self.knowledge_base_id)
            elif error_code == "AccessDeniedException":
                raise KBAccessDeniedError(self.knowledge_base_id)
            else:
                logger.error(f"Failed to get sync status: {error_code} - {error_message}")
                raise KBServiceError(f"Failed to get sync status: {error_message}")
    
    def _list_recent_ingestion_jobs(self, max_results: int = 5) -> list:
        """
        List recent ingestion jobs for the data source.
        
        Args:
            max_results: Maximum number of jobs to return
            
        Returns:
            List of ingestion job summaries, sorted by most recent first
        """
        if not self.data_source_id:
            return []
        
        try:
            response = self.bedrock_agent.list_ingestion_jobs(
                knowledgeBaseId=self.knowledge_base_id,
                dataSourceId=self.data_source_id,
                maxResults=max_results,
                sortBy={
                    "attribute": "STARTED_AT",
                    "order": "DESCENDING"
                }
            )
            
            return response.get("ingestionJobSummaries", [])
            
        except ClientError as e:
            logger.warning(f"Failed to list ingestion jobs: {e}")
            return []
    
    async def start_sync(self) -> str:
        """
        Trigger knowledge base sync/reindexing.
        
        Requirements: 5.2, 11.2 - Trigger KB reindexing after document removal
        
        This starts an ingestion job to reindex the S3 data source,
        which is necessary after document removal to update the KB index.
        
        Returns:
            Ingestion job ID for tracking
            
        Raises:
            KBServiceError: If sync trigger fails
        """
        if not self.data_source_id:
            raise KBServiceError(
                "Data source ID required for sync operations. "
                "Set data_source_id when initializing KnowledgeBaseService."
            )
        
        try:
            response = self.bedrock_agent.start_ingestion_job(
                knowledgeBaseId=self.knowledge_base_id,
                dataSourceId=self.data_source_id,
                description="Triggered by dev.echo after document removal"
            )
            
            ingestion_job = response.get("ingestionJob", {})
            job_id = ingestion_job.get("ingestionJobId", "")
            job_status = ingestion_job.get("status", "UNKNOWN")
            
            logger.info(
                f"Started KB sync job: {job_id}, status={job_status}"
            )
            return job_id
            
        except ClientError as e:
            error_code = e.response["Error"]["Code"]
            error_message = e.response["Error"]["Message"]
            
            if error_code == "ResourceNotFoundException":
                raise KBNotFoundError(self.knowledge_base_id)
            elif error_code == "AccessDeniedException":
                raise KBAccessDeniedError(self.knowledge_base_id)
            elif error_code == "ConflictException":
                # Another sync job is already running
                logger.warning("Sync job already in progress")
                raise KBSyncError(
                    "A sync job is already in progress. Please wait for it to complete."
                )
            elif error_code == "ThrottlingException":
                logger.warning("Sync request throttled")
                raise KBSyncError(
                    "Request throttled. Please try again later."
                )
            else:
                logger.error(f"Failed to start sync: {error_code} - {error_message}")
                raise KBServiceError(f"Failed to start sync: {error_message}")
    
    async def get_ingestion_job_status(self, job_id: str) -> dict:
        """
        Get status of a specific ingestion job.
        
        Args:
            job_id: Ingestion job ID
            
        Returns:
            Dictionary with job status details
        """
        if not self.data_source_id:
            raise KBServiceError("Data source ID required for job status check.")
        
        try:
            response = self.bedrock_agent.get_ingestion_job(
                knowledgeBaseId=self.knowledge_base_id,
                dataSourceId=self.data_source_id,
                ingestionJobId=job_id
            )
            
            job = response.get("ingestionJob", {})
            return {
                "job_id": job.get("ingestionJobId"),
                "status": job.get("status"),
                "started_at": job.get("startedAt"),
                "updated_at": job.get("updatedAt"),
                "statistics": job.get("statistics", {}),
                "failure_reasons": job.get("failureReasons", []),
            }
            
        except ClientError as e:
            error_code = e.response["Error"]["Code"]
            error_message = e.response["Error"]["Message"]
            logger.error(f"Failed to get job status: {error_code} - {error_message}")
            raise KBServiceError(f"Failed to get job status: {error_message}")
