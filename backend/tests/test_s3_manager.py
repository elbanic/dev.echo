"""
Tests for S3 Document Manager

Tests S3 document operations: list, add, update, remove.
Uses moto to mock AWS S3 service.
"""

import sys
from pathlib import Path

# Add backend to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

import pytest
import tempfile
from unittest.mock import MagicMock, patch
from datetime import datetime, timezone

import boto3
from moto import mock_aws

from aws import (
    S3DocumentManager,
    S3Document,
    S3DocumentError,
    DocumentNotFoundError,
    DocumentExistsError,
    InvalidMarkdownError,
)


TEST_BUCKET = "test-devecho-bucket"
TEST_PREFIX = "kb-documents/"
TEST_REGION = "us-west-2"


@pytest.fixture
def temp_source_dir():
    """Create a temporary directory for source files."""
    with tempfile.TemporaryDirectory() as tmpdir:
        yield Path(tmpdir)


@pytest.fixture
def sample_md_file(temp_source_dir):
    """Create a sample markdown file in source directory."""
    md_path = temp_source_dir / "sample.md"
    md_path.write_text("# Sample Document\n\nThis is a test document.")
    return md_path


@pytest.fixture
def sample_txt_file(temp_source_dir):
    """Create a sample text file (non-markdown)."""
    txt_path = temp_source_dir / "sample.txt"
    txt_path.write_text("This is not markdown.")
    return txt_path


@pytest.fixture
def mock_s3():
    """Create mocked S3 service with test bucket."""
    with mock_aws():
        # Create S3 client and bucket
        s3 = boto3.client("s3", region_name=TEST_REGION)
        s3.create_bucket(
            Bucket=TEST_BUCKET,
            CreateBucketConfiguration={"LocationConstraint": TEST_REGION}
        )
        yield s3


@pytest.fixture
def s3_manager(mock_s3):
    """Create S3DocumentManager with mocked S3."""
    return S3DocumentManager(
        bucket_name=TEST_BUCKET,
        prefix=TEST_PREFIX,
        region=TEST_REGION
    )


class TestS3DocumentManager:
    """Tests for S3DocumentManager class."""
    
    def test_init(self, mock_s3):
        """Test S3DocumentManager initialization."""
        manager = S3DocumentManager(
            bucket_name=TEST_BUCKET,
            prefix=TEST_PREFIX,
            region=TEST_REGION
        )
        
        assert manager.bucket_name == TEST_BUCKET
        assert manager.prefix == TEST_PREFIX
        assert manager.region == TEST_REGION
    
    def test_validate_markdown_valid_extensions(self, s3_manager):
        """Test markdown validation with valid extensions."""
        assert s3_manager.validate_markdown(Path("doc.md")) is True
        assert s3_manager.validate_markdown(Path("doc.markdown")) is True
        assert s3_manager.validate_markdown(Path("DOC.MD")) is True
        assert s3_manager.validate_markdown(Path("DOC.MARKDOWN")) is True
    
    def test_validate_markdown_invalid_extensions(self, s3_manager):
        """Test markdown validation with invalid extensions."""
        assert s3_manager.validate_markdown(Path("doc.txt")) is False
        assert s3_manager.validate_markdown(Path("doc.py")) is False
        assert s3_manager.validate_markdown(Path("doc")) is False
        assert s3_manager.validate_markdown(Path("doc.html")) is False


class TestListDocuments:
    """Tests for list_documents method."""
    
    @pytest.mark.asyncio
    async def test_list_empty_bucket(self, s3_manager):
        """Test listing documents in empty bucket."""
        docs, token = await s3_manager.list_documents()
        
        assert docs == []
        assert token is None
    
    @pytest.mark.asyncio
    async def test_list_documents(self, s3_manager, mock_s3):
        """Test listing documents in bucket."""
        # Add some documents directly to S3
        mock_s3.put_object(
            Bucket=TEST_BUCKET,
            Key=f"{TEST_PREFIX}doc1.md",
            Body=b"# Doc 1"
        )
        mock_s3.put_object(
            Bucket=TEST_BUCKET,
            Key=f"{TEST_PREFIX}doc2.md",
            Body=b"# Doc 2"
        )
        mock_s3.put_object(
            Bucket=TEST_BUCKET,
            Key=f"{TEST_PREFIX}not_md.txt",
            Body=b"Not markdown"
        )
        
        docs, token = await s3_manager.list_documents()
        
        assert len(docs) == 2
        names = [d.name for d in docs]
        assert "doc1.md" in names
        assert "doc2.md" in names
        assert "not_md.txt" not in names
    
    @pytest.mark.asyncio
    async def test_list_documents_sorted(self, s3_manager, mock_s3):
        """Test that documents are sorted alphabetically by name."""
        # Add documents in non-alphabetical order
        mock_s3.put_object(Bucket=TEST_BUCKET, Key=f"{TEST_PREFIX}zebra.md", Body=b"# Zebra")
        mock_s3.put_object(Bucket=TEST_BUCKET, Key=f"{TEST_PREFIX}alpha.md", Body=b"# Alpha")
        mock_s3.put_object(Bucket=TEST_BUCKET, Key=f"{TEST_PREFIX}Beta.md", Body=b"# Beta")
        
        docs, _ = await s3_manager.list_documents()
        
        names = [d.name for d in docs]
        # Case-insensitive sort
        assert names == ["alpha.md", "Beta.md", "zebra.md"]
    
    @pytest.mark.asyncio
    async def test_list_documents_pagination(self, s3_manager, mock_s3):
        """Test pagination with max_items."""
        # Add more documents than max_items
        for i in range(25):
            mock_s3.put_object(
                Bucket=TEST_BUCKET,
                Key=f"{TEST_PREFIX}doc{i:02d}.md",
                Body=f"# Doc {i}".encode()
            )
        
        # First page
        docs1, token1 = await s3_manager.list_documents(max_items=10)
        assert len(docs1) <= 10
        
        # If there's a continuation token, get next page
        if token1:
            docs2, token2 = await s3_manager.list_documents(
                max_items=10,
                continuation_token=token1
            )
            assert len(docs2) <= 10


class TestDocumentExists:
    """Tests for document_exists method."""
    
    @pytest.mark.asyncio
    async def test_document_exists_true(self, s3_manager, mock_s3):
        """Test document_exists returns True for existing document."""
        mock_s3.put_object(
            Bucket=TEST_BUCKET,
            Key=f"{TEST_PREFIX}existing.md",
            Body=b"# Existing"
        )
        
        exists = await s3_manager.document_exists("existing.md")
        assert exists is True
    
    @pytest.mark.asyncio
    async def test_document_exists_false(self, s3_manager):
        """Test document_exists returns False for non-existing document."""
        exists = await s3_manager.document_exists("nonexistent.md")
        assert exists is False
    
    @pytest.mark.asyncio
    async def test_document_exists_adds_extension(self, s3_manager, mock_s3):
        """Test document_exists adds .md extension if missing."""
        mock_s3.put_object(
            Bucket=TEST_BUCKET,
            Key=f"{TEST_PREFIX}test.md",
            Body=b"# Test"
        )
        
        # Query without extension
        exists = await s3_manager.document_exists("test")
        assert exists is True


class TestAddDocument:
    """Tests for add_document method."""
    
    @pytest.mark.asyncio
    async def test_add_document_success(self, s3_manager, sample_md_file):
        """Test adding a document successfully."""
        doc = await s3_manager.add_document(sample_md_file, "test-doc")
        
        assert doc.name == "test-doc.md"
        assert doc.key == f"{TEST_PREFIX}test-doc.md"
        assert doc.size_bytes > 0
        assert doc.etag is not None
    
    @pytest.mark.asyncio
    async def test_add_document_with_extension(self, s3_manager, sample_md_file):
        """Test adding document with .md extension in name."""
        doc = await s3_manager.add_document(sample_md_file, "test-doc.md")
        assert doc.name == "test-doc.md"
    
    @pytest.mark.asyncio
    async def test_add_document_invalid_extension(self, s3_manager, sample_txt_file):
        """Test adding non-markdown file raises error."""
        with pytest.raises(InvalidMarkdownError) as exc_info:
            await s3_manager.add_document(sample_txt_file, "test-doc")
        
        assert ".md" in str(exc_info.value) or ".markdown" in str(exc_info.value)
    
    @pytest.mark.asyncio
    async def test_add_document_already_exists(self, s3_manager, sample_md_file):
        """Test adding document that already exists raises error."""
        await s3_manager.add_document(sample_md_file, "test-doc")
        
        with pytest.raises(DocumentExistsError) as exc_info:
            await s3_manager.add_document(sample_md_file, "test-doc")
        
        assert "test-doc" in str(exc_info.value)
    
    @pytest.mark.asyncio
    async def test_add_document_source_not_found(self, s3_manager):
        """Test adding from non-existent source raises error."""
        with pytest.raises(S3DocumentError, match="Source file not found"):
            await s3_manager.add_document(Path("/nonexistent/file.md"), "test")
    
    @pytest.mark.asyncio
    async def test_add_document_appears_in_list(self, s3_manager, sample_md_file):
        """Test added document appears in list."""
        await s3_manager.add_document(sample_md_file, "test-doc")
        
        docs, _ = await s3_manager.list_documents()
        
        assert len(docs) == 1
        assert docs[0].name == "test-doc.md"


class TestUpdateDocument:
    """Tests for update_document method."""
    
    @pytest.mark.asyncio
    async def test_update_document_success(self, s3_manager, sample_md_file, temp_source_dir):
        """Test updating a document successfully."""
        # First add a document
        await s3_manager.add_document(sample_md_file, "test-doc")
        
        # Create updated content
        updated_file = temp_source_dir / "updated.md"
        updated_file.write_text("# Updated Content\n\nNew content here.")
        
        doc = await s3_manager.update_document(updated_file, "test-doc")
        
        assert doc.name == "test-doc.md"
        assert doc.size_bytes > 0
    
    @pytest.mark.asyncio
    async def test_update_document_not_found(self, s3_manager, sample_md_file):
        """Test updating non-existent document raises error."""
        with pytest.raises(DocumentNotFoundError) as exc_info:
            await s3_manager.update_document(sample_md_file, "nonexistent")
        
        assert "nonexistent" in str(exc_info.value)
    
    @pytest.mark.asyncio
    async def test_update_document_invalid_extension(self, s3_manager, sample_md_file, sample_txt_file):
        """Test updating with non-markdown file raises error."""
        # First add a document
        await s3_manager.add_document(sample_md_file, "test-doc")
        
        with pytest.raises(InvalidMarkdownError):
            await s3_manager.update_document(sample_txt_file, "test-doc")


class TestRemoveDocument:
    """Tests for remove_document method."""
    
    @pytest.mark.asyncio
    async def test_remove_document_success(self, s3_manager, sample_md_file):
        """Test removing a document successfully."""
        await s3_manager.add_document(sample_md_file, "test-doc")
        
        result = await s3_manager.remove_document("test-doc")
        
        assert result is True
        
        # Verify document no longer exists
        exists = await s3_manager.document_exists("test-doc")
        assert exists is False
    
    @pytest.mark.asyncio
    async def test_remove_document_not_found(self, s3_manager):
        """Test removing non-existent document raises error."""
        with pytest.raises(DocumentNotFoundError) as exc_info:
            await s3_manager.remove_document("nonexistent")
        
        assert "nonexistent" in str(exc_info.value)
    
    @pytest.mark.asyncio
    async def test_remove_document_not_in_list(self, s3_manager, sample_md_file):
        """Test removed document no longer appears in list."""
        await s3_manager.add_document(sample_md_file, "test-doc")
        
        docs_before, _ = await s3_manager.list_documents()
        assert len(docs_before) == 1
        
        await s3_manager.remove_document("test-doc")
        
        docs_after, _ = await s3_manager.list_documents()
        assert len(docs_after) == 0


class TestS3Document:
    """Tests for S3Document dataclass."""
    
    def test_to_dict(self):
        """Test S3Document.to_dict() method."""
        doc = S3Document(
            name="test.md",
            key="kb-documents/test.md",
            size_bytes=1024,
            last_modified=1234567890.0,
            etag="abc123"
        )
        
        result = doc.to_dict()
        
        assert result["name"] == "test.md"
        assert result["key"] == "kb-documents/test.md"
        assert result["size_bytes"] == 1024
        assert result["last_modified"] == 1234567890.0
        assert result["etag"] == "abc123"
