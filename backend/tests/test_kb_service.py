"""
Tests for Knowledge Base Service

Tests Bedrock Knowledge Base operations: connectivity, sync status, sync trigger.
"""

import sys
from pathlib import Path
from unittest.mock import MagicMock, patch
from datetime import datetime

# Add backend to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

import pytest
from botocore.exceptions import ClientError

from aws.kb_service import (
    KnowledgeBaseService,
    SyncStatus,
    RetrievalResult,
    KBServiceError,
    KBNotFoundError,
    KBAccessDeniedError,
    KBSyncError,
)


@pytest.fixture
def mock_bedrock_agent():
    """Create a mock bedrock-agent client."""
    with patch("boto3.client") as mock_client:
        agent_mock = MagicMock()
        runtime_mock = MagicMock()
        
        def client_factory(service_name, **kwargs):
            if service_name == "bedrock-agent":
                return agent_mock
            elif service_name == "bedrock-agent-runtime":
                return runtime_mock
            return MagicMock()
        
        mock_client.side_effect = client_factory
        yield agent_mock, runtime_mock


@pytest.fixture
def kb_service(mock_bedrock_agent):
    """Create a KnowledgeBaseService with mocked clients."""
    return KnowledgeBaseService(
        knowledge_base_id="test-kb-id",
        data_source_id="test-ds-id",
        region="us-west-2"
    )


class TestKnowledgeBaseServiceInit:
    """Tests for KnowledgeBaseService initialization."""
    
    def test_init_with_required_params(self, mock_bedrock_agent):
        """Test initialization with required parameters."""
        service = KnowledgeBaseService(
            knowledge_base_id="test-kb-id",
            region="us-west-2"
        )
        
        assert service.knowledge_base_id == "test-kb-id"
        assert service.region == "us-west-2"
        assert service.data_source_id is None
    
    def test_init_with_data_source_id(self, mock_bedrock_agent):
        """Test initialization with data source ID."""
        service = KnowledgeBaseService(
            knowledge_base_id="test-kb-id",
            data_source_id="test-ds-id",
            region="us-east-1"
        )
        
        assert service.knowledge_base_id == "test-kb-id"
        assert service.data_source_id == "test-ds-id"
        assert service.region == "us-east-1"


class TestCheckConnectivity:
    """Tests for check_connectivity method."""
    
    @pytest.mark.asyncio
    async def test_connectivity_success(self, kb_service, mock_bedrock_agent):
        """Test successful connectivity check."""
        agent_mock, _ = mock_bedrock_agent
        agent_mock.get_knowledge_base.return_value = {
            "knowledgeBase": {
                "knowledgeBaseId": "test-kb-id",
                "status": "ACTIVE"
            }
        }
        
        result = await kb_service.check_connectivity()
        
        assert result is True
        agent_mock.get_knowledge_base.assert_called_once_with(
            knowledgeBaseId="test-kb-id"
        )
    
    @pytest.mark.asyncio
    async def test_connectivity_kb_not_found(self, kb_service, mock_bedrock_agent):
        """Test connectivity check when KB not found."""
        agent_mock, _ = mock_bedrock_agent
        agent_mock.get_knowledge_base.side_effect = ClientError(
            {"Error": {"Code": "ResourceNotFoundException", "Message": "KB not found"}},
            "GetKnowledgeBase"
        )
        
        with pytest.raises(KBNotFoundError) as exc_info:
            await kb_service.check_connectivity()
        
        assert exc_info.value.kb_id == "test-kb-id"
    
    @pytest.mark.asyncio
    async def test_connectivity_access_denied(self, kb_service, mock_bedrock_agent):
        """Test connectivity check when access denied."""
        agent_mock, _ = mock_bedrock_agent
        agent_mock.get_knowledge_base.side_effect = ClientError(
            {"Error": {"Code": "AccessDeniedException", "Message": "Access denied"}},
            "GetKnowledgeBase"
        )
        
        with pytest.raises(KBAccessDeniedError) as exc_info:
            await kb_service.check_connectivity()
        
        assert exc_info.value.kb_id == "test-kb-id"
    
    @pytest.mark.asyncio
    async def test_connectivity_other_error(self, kb_service, mock_bedrock_agent):
        """Test connectivity check with other errors."""
        agent_mock, _ = mock_bedrock_agent
        agent_mock.get_knowledge_base.side_effect = ClientError(
            {"Error": {"Code": "InternalServerError", "Message": "Server error"}},
            "GetKnowledgeBase"
        )
        
        with pytest.raises(KBServiceError):
            await kb_service.check_connectivity()


class TestGetSyncStatus:
    """Tests for get_sync_status method."""
    
    @pytest.mark.asyncio
    async def test_sync_status_active(self, kb_service, mock_bedrock_agent):
        """Test getting sync status for active KB."""
        agent_mock, _ = mock_bedrock_agent
        agent_mock.get_knowledge_base.return_value = {
            "knowledgeBase": {
                "knowledgeBaseId": "test-kb-id",
                "status": "ACTIVE"
            }
        }
        agent_mock.list_ingestion_jobs.return_value = {
            "ingestionJobSummaries": []
        }
        
        status = await kb_service.get_sync_status()
        
        assert status.status == "READY"
        assert isinstance(status, SyncStatus)
    
    @pytest.mark.asyncio
    async def test_sync_status_with_ingestion_job(self, kb_service, mock_bedrock_agent):
        """Test sync status with recent ingestion job."""
        agent_mock, _ = mock_bedrock_agent
        agent_mock.get_knowledge_base.return_value = {
            "knowledgeBase": {
                "knowledgeBaseId": "test-kb-id",
                "status": "ACTIVE"
            }
        }
        
        mock_datetime = datetime(2025, 1, 26, 12, 0, 0)
        agent_mock.list_ingestion_jobs.return_value = {
            "ingestionJobSummaries": [
                {
                    "ingestionJobId": "job-123",
                    "status": "COMPLETE",
                    "updatedAt": mock_datetime,
                    "statistics": {
                        "numberOfDocumentsScanned": 10
                    }
                }
            ]
        }
        
        status = await kb_service.get_sync_status()
        
        assert status.status == "READY"
        assert status.document_count == 10
        assert status.last_sync == mock_datetime.timestamp()
    
    @pytest.mark.asyncio
    async def test_sync_status_in_progress(self, kb_service, mock_bedrock_agent):
        """Test sync status when ingestion is in progress."""
        agent_mock, _ = mock_bedrock_agent
        agent_mock.get_knowledge_base.return_value = {
            "knowledgeBase": {
                "knowledgeBaseId": "test-kb-id",
                "status": "ACTIVE"
            }
        }
        agent_mock.list_ingestion_jobs.return_value = {
            "ingestionJobSummaries": [
                {
                    "ingestionJobId": "job-123",
                    "status": "IN_PROGRESS",
                    "statistics": {}
                }
            ]
        }
        
        status = await kb_service.get_sync_status()
        
        assert status.status == "SYNCING"
    
    @pytest.mark.asyncio
    async def test_sync_status_failed(self, kb_service, mock_bedrock_agent):
        """Test sync status when ingestion failed."""
        agent_mock, _ = mock_bedrock_agent
        agent_mock.get_knowledge_base.return_value = {
            "knowledgeBase": {
                "knowledgeBaseId": "test-kb-id",
                "status": "ACTIVE"
            }
        }
        agent_mock.list_ingestion_jobs.return_value = {
            "ingestionJobSummaries": [
                {
                    "ingestionJobId": "job-123",
                    "status": "FAILED",
                    "failureReasons": ["Document parsing error"],
                    "statistics": {}
                }
            ]
        }
        
        status = await kb_service.get_sync_status()
        
        assert status.status == "FAILED"
        assert status.error_message == "Document parsing error"
    
    @pytest.mark.asyncio
    async def test_sync_status_kb_not_found(self, kb_service, mock_bedrock_agent):
        """Test sync status when KB not found."""
        agent_mock, _ = mock_bedrock_agent
        agent_mock.get_knowledge_base.side_effect = ClientError(
            {"Error": {"Code": "ResourceNotFoundException", "Message": "KB not found"}},
            "GetKnowledgeBase"
        )
        
        with pytest.raises(KBNotFoundError):
            await kb_service.get_sync_status()


class TestStartSync:
    """Tests for start_sync method."""
    
    @pytest.mark.asyncio
    async def test_start_sync_success(self, kb_service, mock_bedrock_agent):
        """Test successful sync trigger."""
        agent_mock, _ = mock_bedrock_agent
        agent_mock.start_ingestion_job.return_value = {
            "ingestionJob": {
                "ingestionJobId": "job-456",
                "status": "STARTING"
            }
        }
        
        job_id = await kb_service.start_sync()
        
        assert job_id == "job-456"
        agent_mock.start_ingestion_job.assert_called_once_with(
            knowledgeBaseId="test-kb-id",
            dataSourceId="test-ds-id",
            description="Triggered by dev.echo after document removal"
        )
    
    @pytest.mark.asyncio
    async def test_start_sync_no_data_source(self, mock_bedrock_agent):
        """Test sync trigger without data source ID."""
        service = KnowledgeBaseService(
            knowledge_base_id="test-kb-id",
            region="us-west-2"
        )
        
        with pytest.raises(KBServiceError, match="Data source ID required"):
            await service.start_sync()
    
    @pytest.mark.asyncio
    async def test_start_sync_conflict(self, kb_service, mock_bedrock_agent):
        """Test sync trigger when job already running."""
        agent_mock, _ = mock_bedrock_agent
        agent_mock.start_ingestion_job.side_effect = ClientError(
            {"Error": {"Code": "ConflictException", "Message": "Job in progress"}},
            "StartIngestionJob"
        )
        
        with pytest.raises(KBSyncError, match="already in progress"):
            await kb_service.start_sync()
    
    @pytest.mark.asyncio
    async def test_start_sync_throttled(self, kb_service, mock_bedrock_agent):
        """Test sync trigger when throttled."""
        agent_mock, _ = mock_bedrock_agent
        agent_mock.start_ingestion_job.side_effect = ClientError(
            {"Error": {"Code": "ThrottlingException", "Message": "Rate exceeded"}},
            "StartIngestionJob"
        )
        
        with pytest.raises(KBSyncError, match="throttled"):
            await kb_service.start_sync()
    
    @pytest.mark.asyncio
    async def test_start_sync_kb_not_found(self, kb_service, mock_bedrock_agent):
        """Test sync trigger when KB not found."""
        agent_mock, _ = mock_bedrock_agent
        agent_mock.start_ingestion_job.side_effect = ClientError(
            {"Error": {"Code": "ResourceNotFoundException", "Message": "KB not found"}},
            "StartIngestionJob"
        )
        
        with pytest.raises(KBNotFoundError):
            await kb_service.start_sync()


class TestGetIngestionJobStatus:
    """Tests for get_ingestion_job_status method."""
    
    @pytest.mark.asyncio
    async def test_get_job_status_success(self, kb_service, mock_bedrock_agent):
        """Test getting ingestion job status."""
        agent_mock, _ = mock_bedrock_agent
        mock_datetime = datetime(2025, 1, 26, 12, 0, 0)
        agent_mock.get_ingestion_job.return_value = {
            "ingestionJob": {
                "ingestionJobId": "job-123",
                "status": "COMPLETE",
                "startedAt": mock_datetime,
                "updatedAt": mock_datetime,
                "statistics": {
                    "numberOfDocumentsScanned": 5,
                    "numberOfDocumentsIndexed": 5
                },
                "failureReasons": []
            }
        }
        
        status = await kb_service.get_ingestion_job_status("job-123")
        
        assert status["job_id"] == "job-123"
        assert status["status"] == "COMPLETE"
        assert status["statistics"]["numberOfDocumentsScanned"] == 5
    
    @pytest.mark.asyncio
    async def test_get_job_status_no_data_source(self, mock_bedrock_agent):
        """Test job status without data source ID."""
        service = KnowledgeBaseService(
            knowledge_base_id="test-kb-id",
            region="us-west-2"
        )
        
        with pytest.raises(KBServiceError, match="Data source ID required"):
            await service.get_ingestion_job_status("job-123")


class TestDataclasses:
    """Tests for dataclass serialization."""
    
    def test_sync_status_to_dict(self):
        """Test SyncStatus serialization."""
        status = SyncStatus(
            status="READY",
            last_sync=1706270400.0,
            document_count=10,
            error_message=None
        )
        
        result = status.to_dict()
        
        assert result["status"] == "READY"
        assert result["last_sync"] == 1706270400.0
        assert result["document_count"] == 10
        assert result["error_message"] is None
    
    def test_retrieval_result_to_dict(self):
        """Test RetrievalResult serialization."""
        result = RetrievalResult(
            content="Test content",
            source="doc.md",
            score=0.95,
            metadata={"key": "value"}
        )
        
        data = result.to_dict()
        
        assert data["content"] == "Test content"
        assert data["source"] == "doc.md"
        assert data["score"] == 0.95
        assert data["metadata"] == {"key": "value"}
