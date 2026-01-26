"""
Knowledge Base Manager

Manages knowledge base documents for dev.echo.

Requirements: 4.1, 4.2, 4.3, 4.4, 4.5
"""

import logging
import os
import shutil
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional

from .exceptions import (
    KBError,
    DocumentNotFoundError,
    InvalidMarkdownError,
    DocumentExistsError,
)

logger = logging.getLogger(__name__)


@dataclass
class KBDocument:
    """
    Knowledge base document metadata.
    
    Represents a markdown document stored in the knowledge base.
    """
    name: str
    path: Path
    size_bytes: int
    created_at: float
    updated_at: float
    
    def to_dict(self) -> dict:
        """Convert to dictionary for serialization."""
        return {
            "name": self.name,
            "path": str(self.path),
            "size_bytes": self.size_bytes,
            "created_at": self.created_at,
            "updated_at": self.updated_at,
        }


class KnowledgeBaseManager:
    """
    Manages knowledge base documents.
    
    Provides operations to list, add, update, and remove markdown
    documents from the knowledge base.
    
    Requirements: 4.1, 4.2, 4.3, 4.4, 4.5
    """
    
    VALID_EXTENSIONS = {".md", ".markdown"}
    
    def __init__(self, kb_path: Optional[Path] = None):
        """
        Initialize the Knowledge Base Manager.
        
        Args:
            kb_path: Path to the knowledge base directory.
                     Defaults to ~/.devecho/kb/
        """
        if kb_path is None:
            kb_path = Path.home() / ".devecho" / "kb"
        
        self.kb_path = Path(kb_path)
        self._ensure_kb_directory()
    
    def _ensure_kb_directory(self) -> None:
        """Ensure the KB directory exists."""
        self.kb_path.mkdir(parents=True, exist_ok=True)
        logger.debug(f"KB directory: {self.kb_path}")
    
    def validate_markdown(self, path: Path) -> bool:
        """
        Validate that a file is a markdown file.
        
        Requirements: 4.5 - Reject non-markdown files
        
        Args:
            path: Path to the file to validate
            
        Returns:
            True if the file is a valid markdown file
        """
        path = Path(path)
        return path.suffix.lower() in self.VALID_EXTENSIONS

    async def list_documents(self) -> List[KBDocument]:
        """
        List all documents in the knowledge base.
        
        Requirements: 4.1 - Display all documents in current knowledge base
        
        Returns:
            List of KBDocument objects for all documents in the KB
        """
        documents = []
        
        if not self.kb_path.exists():
            return documents
        
        for file_path in self.kb_path.iterdir():
            if file_path.is_file() and self.validate_markdown(file_path):
                try:
                    stat = file_path.stat()
                    doc = KBDocument(
                        name=file_path.name,
                        path=file_path,
                        size_bytes=stat.st_size,
                        created_at=stat.st_ctime,
                        updated_at=stat.st_mtime,
                    )
                    documents.append(doc)
                except OSError as e:
                    logger.warning(f"Failed to stat file {file_path}: {e}")
                    continue
        
        # Sort by name for consistent ordering
        documents.sort(key=lambda d: d.name.lower())
        
        logger.info(f"Listed {len(documents)} documents in KB")
        return documents
    
    def _get_document_path(self, name: str) -> Path:
        """Get the full path for a document by name."""
        # Ensure .md extension
        if not name.lower().endswith(tuple(self.VALID_EXTENSIONS)):
            name = f"{name}.md"
        return self.kb_path / name
    
    def _document_exists(self, name: str) -> bool:
        """Check if a document exists in the KB."""
        doc_path = self._get_document_path(name)
        return doc_path.exists()
    
    async def add_document(
        self,
        source_path: Path,
        name: str
    ) -> KBDocument:
        """
        Add a markdown document to the knowledge base.
        
        Requirements: 4.4 - Upload markdown file with given name
        Requirements: 4.5 - Reject non-markdown files
        
        Args:
            source_path: Path to the source markdown file
            name: Name for the document in the KB
            
        Returns:
            KBDocument for the added document
            
        Raises:
            InvalidMarkdownError: If source is not a markdown file
            DocumentExistsError: If document with name already exists
            KBError: For other errors
        """
        source_path = Path(source_path)
        
        # Validate source is markdown
        if not self.validate_markdown(source_path):
            raise InvalidMarkdownError(
                str(source_path),
                f"File must have extension: {', '.join(self.VALID_EXTENSIONS)}"
            )
        
        # Check source exists
        if not source_path.exists():
            raise KBError(f"Source file not found: {source_path}")
        
        if not source_path.is_file():
            raise KBError(f"Source is not a file: {source_path}")
        
        # Get destination path
        dest_path = self._get_document_path(name)
        
        # Check if document already exists
        if dest_path.exists():
            raise DocumentExistsError(name)
        
        try:
            # Copy file to KB
            shutil.copy2(source_path, dest_path)
            
            stat = dest_path.stat()
            doc = KBDocument(
                name=dest_path.name,
                path=dest_path,
                size_bytes=stat.st_size,
                created_at=stat.st_ctime,
                updated_at=stat.st_mtime,
            )
            
            logger.info(f"Added document: {doc.name}")
            return doc
            
        except OSError as e:
            raise KBError(f"Failed to add document: {e}")

    async def update_document(
        self,
        source_path: Path,
        name: str
    ) -> KBDocument:
        """
        Update an existing document in the knowledge base.
        
        Requirements: 4.3 - Update existing document with content from path
        Requirements: 4.5 - Reject non-markdown files
        
        Args:
            source_path: Path to the source markdown file
            name: Name of the document to update
            
        Returns:
            KBDocument for the updated document
            
        Raises:
            InvalidMarkdownError: If source is not a markdown file
            DocumentNotFoundError: If document doesn't exist
            KBError: For other errors
        """
        source_path = Path(source_path)
        
        # Validate source is markdown
        if not self.validate_markdown(source_path):
            raise InvalidMarkdownError(
                str(source_path),
                f"File must have extension: {', '.join(self.VALID_EXTENSIONS)}"
            )
        
        # Check source exists
        if not source_path.exists():
            raise KBError(f"Source file not found: {source_path}")
        
        if not source_path.is_file():
            raise KBError(f"Source is not a file: {source_path}")
        
        # Get destination path
        dest_path = self._get_document_path(name)
        
        # Check if document exists
        if not dest_path.exists():
            raise DocumentNotFoundError(name)
        
        try:
            # Copy file to KB (overwrites existing)
            shutil.copy2(source_path, dest_path)
            
            stat = dest_path.stat()
            doc = KBDocument(
                name=dest_path.name,
                path=dest_path,
                size_bytes=stat.st_size,
                created_at=stat.st_ctime,
                updated_at=stat.st_mtime,
            )
            
            logger.info(f"Updated document: {doc.name}")
            return doc
            
        except OSError as e:
            raise KBError(f"Failed to update document: {e}")
    
    async def remove_document(self, name: str) -> bool:
        """
        Remove a document from the knowledge base.
        
        Requirements: 4.2 - Delete document with specified filename
        
        Args:
            name: Name of the document to remove
            
        Returns:
            True if document was removed
            
        Raises:
            DocumentNotFoundError: If document doesn't exist
            KBError: For other errors
        """
        dest_path = self._get_document_path(name)
        
        # Check if document exists
        if not dest_path.exists():
            raise DocumentNotFoundError(name)
        
        try:
            dest_path.unlink()
            logger.info(f"Removed document: {name}")
            return True
            
        except OSError as e:
            raise KBError(f"Failed to remove document: {e}")
    
    async def get_document(self, name: str) -> Optional[KBDocument]:
        """
        Get a specific document by name.
        
        Args:
            name: Name of the document
            
        Returns:
            KBDocument if found, None otherwise
        """
        dest_path = self._get_document_path(name)
        
        if not dest_path.exists():
            return None
        
        try:
            stat = dest_path.stat()
            return KBDocument(
                name=dest_path.name,
                path=dest_path,
                size_bytes=stat.st_size,
                created_at=stat.st_ctime,
                updated_at=stat.st_mtime,
            )
        except OSError:
            return None
    
    async def get_document_content(self, name: str) -> str:
        """
        Get the content of a document.
        
        Args:
            name: Name of the document
            
        Returns:
            Document content as string
            
        Raises:
            DocumentNotFoundError: If document doesn't exist
        """
        dest_path = self._get_document_path(name)
        
        if not dest_path.exists():
            raise DocumentNotFoundError(name)
        
        try:
            return dest_path.read_text(encoding="utf-8")
        except OSError as e:
            raise KBError(f"Failed to read document: {e}")
