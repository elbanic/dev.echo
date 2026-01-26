"""
Tests for Knowledge Base Manager

Tests document operations: list, add, update, remove.
"""

import sys
from pathlib import Path

# Add backend to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

import pytest
import tempfile

from kb import (
    KnowledgeBaseManager,
    KBDocument,
    DocumentNotFoundError,
    InvalidMarkdownError,
    DocumentExistsError,
)


@pytest.fixture
def temp_kb_dir():
    """Create a temporary KB directory."""
    with tempfile.TemporaryDirectory() as tmpdir:
        yield Path(tmpdir)


@pytest.fixture
def temp_source_dir():
    """Create a temporary directory for source files."""
    with tempfile.TemporaryDirectory() as tmpdir:
        yield Path(tmpdir)


@pytest.fixture
def kb_manager(temp_kb_dir):
    """Create a KnowledgeBaseManager with temp directory."""
    return KnowledgeBaseManager(kb_path=temp_kb_dir)


@pytest.fixture
def sample_md_file(temp_source_dir):
    """Create a sample markdown file in source directory."""
    md_path = temp_source_dir / "sample.md"
    md_path.write_text("# Sample Document\n\nThis is a test document.")
    return md_path


class TestKnowledgeBaseManager:
    """Tests for KnowledgeBaseManager class."""
    
    def test_init_creates_directory(self, temp_kb_dir):
        """Test that init creates KB directory if it doesn't exist."""
        kb_path = temp_kb_dir / "new_kb"
        assert not kb_path.exists()
        
        manager = KnowledgeBaseManager(kb_path=kb_path)
        
        assert kb_path.exists()
        assert manager.kb_path == kb_path
    
    def test_validate_markdown_valid_extensions(self, kb_manager):
        """Test markdown validation with valid extensions."""
        assert kb_manager.validate_markdown(Path("doc.md")) is True
        assert kb_manager.validate_markdown(Path("doc.markdown")) is True
        assert kb_manager.validate_markdown(Path("DOC.MD")) is True
    
    def test_validate_markdown_invalid_extensions(self, kb_manager):
        """Test markdown validation with invalid extensions."""
        assert kb_manager.validate_markdown(Path("doc.txt")) is False
        assert kb_manager.validate_markdown(Path("doc.py")) is False
        assert kb_manager.validate_markdown(Path("doc")) is False


class TestListDocuments:
    """Tests for list_documents method."""
    
    @pytest.mark.asyncio
    async def test_list_empty_kb(self, kb_manager):
        """Test listing documents in empty KB."""
        docs = await kb_manager.list_documents()
        assert docs == []
    
    @pytest.mark.asyncio
    async def test_list_documents(self, kb_manager, temp_kb_dir):
        """Test listing documents in KB."""
        # Create some documents
        (temp_kb_dir / "doc1.md").write_text("# Doc 1")
        (temp_kb_dir / "doc2.md").write_text("# Doc 2")
        (temp_kb_dir / "not_md.txt").write_text("Not markdown")
        
        docs = await kb_manager.list_documents()
        
        assert len(docs) == 2
        names = [d.name for d in docs]
        assert "doc1.md" in names
        assert "doc2.md" in names
        assert "not_md.txt" not in names
    
    @pytest.mark.asyncio
    async def test_list_documents_sorted(self, kb_manager, temp_kb_dir):
        """Test that documents are sorted by name."""
        (temp_kb_dir / "zebra.md").write_text("# Zebra")
        (temp_kb_dir / "alpha.md").write_text("# Alpha")
        (temp_kb_dir / "beta.md").write_text("# Beta")
        
        docs = await kb_manager.list_documents()
        
        names = [d.name for d in docs]
        assert names == ["alpha.md", "beta.md", "zebra.md"]


class TestAddDocument:
    """Tests for add_document method."""
    
    @pytest.mark.asyncio
    async def test_add_document_success(self, kb_manager, sample_md_file):
        """Test adding a document successfully."""
        doc = await kb_manager.add_document(sample_md_file, "test-doc")
        
        assert doc.name == "test-doc.md"
        assert doc.path.exists()
        assert doc.size_bytes > 0
    
    @pytest.mark.asyncio
    async def test_add_document_preserves_content(self, kb_manager, sample_md_file):
        """Test that added document preserves content."""
        original_content = sample_md_file.read_text()
        
        doc = await kb_manager.add_document(sample_md_file, "test-doc")
        
        added_content = doc.path.read_text()
        assert added_content == original_content
    
    @pytest.mark.asyncio
    async def test_add_document_invalid_extension(self, kb_manager, temp_source_dir):
        """Test adding non-markdown file raises error."""
        txt_file = temp_source_dir / "test.txt"
        txt_file.write_text("Not markdown")
        
        with pytest.raises(InvalidMarkdownError):
            await kb_manager.add_document(txt_file, "test-doc")
    
    @pytest.mark.asyncio
    async def test_add_document_already_exists(self, kb_manager, sample_md_file):
        """Test adding document that already exists raises error."""
        await kb_manager.add_document(sample_md_file, "test-doc")
        
        with pytest.raises(DocumentExistsError):
            await kb_manager.add_document(sample_md_file, "test-doc")
    
    @pytest.mark.asyncio
    async def test_add_document_source_not_found(self, kb_manager):
        """Test adding from non-existent source raises error."""
        from kb.exceptions import KBError
        
        with pytest.raises(KBError, match="Source file not found"):
            await kb_manager.add_document(Path("/nonexistent/file.md"), "test")


class TestDocumentNameHandling:
    """Tests for document name handling."""
    
    @pytest.mark.asyncio
    async def test_add_with_md_extension(self, kb_manager, sample_md_file):
        """Test adding document with .md extension in name."""
        doc = await kb_manager.add_document(sample_md_file, "test-doc.md")
        assert doc.name == "test-doc.md"
    
    @pytest.mark.asyncio
    async def test_add_without_extension(self, kb_manager, sample_md_file):
        """Test adding document without extension adds .md."""
        doc = await kb_manager.add_document(sample_md_file, "test-doc")
        assert doc.name == "test-doc.md"


class TestUpdateDocument:
    """Tests for update_document method."""
    
    @pytest.mark.asyncio
    async def test_update_document_success(self, kb_manager, sample_md_file, temp_source_dir):
        """Test updating a document successfully."""
        # First add a document
        await kb_manager.add_document(sample_md_file, "test-doc")
        
        # Create updated content
        updated_file = temp_source_dir / "updated.md"
        updated_file.write_text("# Updated Content\n\nNew content here.")
        
        doc = await kb_manager.update_document(updated_file, "test-doc")
        
        assert doc.name == "test-doc.md"
        content = doc.path.read_text()
        assert "Updated Content" in content
    
    @pytest.mark.asyncio
    async def test_update_document_not_found(self, kb_manager, sample_md_file):
        """Test updating non-existent document raises error."""
        with pytest.raises(DocumentNotFoundError):
            await kb_manager.update_document(sample_md_file, "nonexistent")
    
    @pytest.mark.asyncio
    async def test_update_document_invalid_extension(self, kb_manager, sample_md_file, temp_source_dir):
        """Test updating with non-markdown file raises error."""
        # First add a document
        await kb_manager.add_document(sample_md_file, "test-doc")
        
        # Try to update with txt file
        txt_file = temp_source_dir / "update.txt"
        txt_file.write_text("Not markdown")
        
        with pytest.raises(InvalidMarkdownError):
            await kb_manager.update_document(txt_file, "test-doc")


class TestRemoveDocument:
    """Tests for remove_document method."""
    
    @pytest.mark.asyncio
    async def test_remove_document_success(self, kb_manager, sample_md_file):
        """Test removing a document successfully."""
        doc = await kb_manager.add_document(sample_md_file, "test-doc")
        assert doc.path.exists()
        
        result = await kb_manager.remove_document("test-doc")
        
        assert result is True
        assert not doc.path.exists()
    
    @pytest.mark.asyncio
    async def test_remove_document_not_found(self, kb_manager):
        """Test removing non-existent document raises error."""
        with pytest.raises(DocumentNotFoundError):
            await kb_manager.remove_document("nonexistent")
    
    @pytest.mark.asyncio
    async def test_remove_document_not_in_list(self, kb_manager, sample_md_file):
        """Test removed document no longer appears in list."""
        await kb_manager.add_document(sample_md_file, "test-doc")
        
        docs_before = await kb_manager.list_documents()
        assert len(docs_before) == 1
        
        await kb_manager.remove_document("test-doc")
        
        docs_after = await kb_manager.list_documents()
        assert len(docs_after) == 0


class TestGetDocument:
    """Tests for get_document method."""
    
    @pytest.mark.asyncio
    async def test_get_document_exists(self, kb_manager, sample_md_file):
        """Test getting an existing document."""
        await kb_manager.add_document(sample_md_file, "test-doc")
        
        doc = await kb_manager.get_document("test-doc")
        
        assert doc is not None
        assert doc.name == "test-doc.md"
    
    @pytest.mark.asyncio
    async def test_get_document_not_exists(self, kb_manager):
        """Test getting a non-existent document returns None."""
        doc = await kb_manager.get_document("nonexistent")
        assert doc is None


class TestGetDocumentContent:
    """Tests for get_document_content method."""
    
    @pytest.mark.asyncio
    async def test_get_content_success(self, kb_manager, sample_md_file):
        """Test getting document content."""
        original_content = sample_md_file.read_text()
        await kb_manager.add_document(sample_md_file, "test-doc")
        
        content = await kb_manager.get_document_content("test-doc")
        
        assert content == original_content
    
    @pytest.mark.asyncio
    async def test_get_content_not_found(self, kb_manager):
        """Test getting content of non-existent document raises error."""
        with pytest.raises(DocumentNotFoundError):
            await kb_manager.get_document_content("nonexistent")
