"""
S3 Document Manager

Manages knowledge base documents stored in AWS S3.
Provides CRUD operations for markdown documents with pagination support.

Requirements: 2.1-2.4, 3.1-3.5, 4.1-4.4, 5.1, 5.4, 10.1-10.4
"""

import logging
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import List, Optional, Tuple

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger(__name__)


class S3DocumentError(Exception):
    """Base exception for S3 document operations."""
    pass


class DocumentNotFoundError(S3DocumentError):
    """Raised when a document is not found in S3."""
    
    def __init__(self, name: str):
        self.name = name
        super().__init__(f"Document not found: {name}")


class DocumentExistsError(S3DocumentError):
    """Raised when trying to add a document that already exists."""
    
    def __init__(self, name: str):
        self.name = name
        super().__init__(f"Document already exists: {name}. Use /update instead.")


class InvalidMarkdownError(S3DocumentError):
    """Raised when a file is not a valid markdown file."""
    
    def __init__(self, path: str, reason: str = "Not a markdown file"):
        self.path = path
        self.reason = reason
        super().__init__(f"Invalid markdown file '{path}': {reason}")


@dataclass
class S3Document:
    """
    Document metadata from S3.
    
    Represents a markdown document stored in the S3 bucket
    for Bedrock Knowledge Base.
    """
    name: str
    key: str
    size_bytes: int
    last_modified: float
    etag: str
    
    def to_dict(self) -> dict:
        """Convert to dictionary for serialization."""
        return {
            "name": self.name,
            "key": self.key,
            "size_bytes": self.size_bytes,
            "last_modified": self.last_modified,
            "etag": self.etag,
        }


class S3DocumentManager:
    """
    Manages documents in S3 for Bedrock Knowledge Base.
    
    Provides CRUD operations for markdown documents with
    pagination support for listing.
    
    Requirements: 2.1-2.4, 3.1-3.5, 4.1-4.4, 5.1, 5.4, 10.1-10.4
    """
    
    VALID_EXTENSIONS = {".md", ".markdown"}
    DEFAULT_PREFIX = "kb-documents/"
    DEFAULT_MAX_ITEMS = 20
    
    def __init__(
        self,
        bucket_name: str,
        prefix: str = DEFAULT_PREFIX,
        region: str = "us-west-2"
    ):
        """
        Initialize S3 Document Manager.
        
        Args:
            bucket_name: S3 bucket name for document storage
            prefix: Key prefix for documents (default: kb-documents/)
            region: AWS region (default: us-west-2)
        """
        self.bucket_name = bucket_name
        self.prefix = prefix
        self.region = region
        self.s3_client = boto3.client("s3", region_name=region)
        
        logger.debug(f"S3DocumentManager initialized: bucket={bucket_name}, prefix={prefix}")
    
    def validate_markdown(self, path: Path) -> bool:
        """
        Validate file is markdown format.
        
        Requirements: 3.3, 4.4 - Reject non-markdown files
        
        Args:
            path: Path to the file to validate
            
        Returns:
            True if the file has a valid markdown extension
        """
        path = Path(path)
        return path.suffix.lower() in self.VALID_EXTENSIONS
    
    def _get_document_key(self, name: str) -> str:
        """
        Get the full S3 key for a document name.
        
        Args:
            name: Document name (with or without .md extension)
            
        Returns:
            Full S3 key including prefix
        """
        # Ensure .md extension
        if not name.lower().endswith(tuple(self.VALID_EXTENSIONS)):
            name = f"{name}.md"
        return f"{self.prefix}{name}"
    
    def _extract_name_from_key(self, key: str) -> str:
        """
        Extract document name from S3 key.
        
        Args:
            key: Full S3 key
            
        Returns:
            Document name without prefix
        """
        if key.startswith(self.prefix):
            return key[len(self.prefix):]
        return key
    
    async def document_exists(self, name: str) -> bool:
        """
        Check if document exists in S3.
        
        Requirements: 3.5, 4.3, 5.4 - Document existence validation
        
        Args:
            name: Document name to check
            
        Returns:
            True if document exists
        """
        key = self._get_document_key(name)
        
        try:
            self.s3_client.head_object(Bucket=self.bucket_name, Key=key)
            return True
        except ClientError as e:
            if e.response["Error"]["Code"] == "404":
                return False
            # Re-raise other errors
            logger.error(f"Error checking document existence: {e}")
            raise S3DocumentError(f"Failed to check document: {e}")
    
    async def list_documents(
        self,
        max_items: int = DEFAULT_MAX_ITEMS,
        continuation_token: Optional[str] = None
    ) -> Tuple[List[S3Document], Optional[str]]:
        """
        List documents in S3 with pagination.
        
        Requirements: 2.1, 2.3, 2.4, 10.2 - List with pagination and sorting
        
        Args:
            max_items: Maximum items per page (default: 20)
            continuation_token: Token for next page (from previous call)
            
        Returns:
            Tuple of (documents list, next continuation token or None)
        """
        documents = []
        
        try:
            # Build request parameters
            params = {
                "Bucket": self.bucket_name,
                "Prefix": self.prefix,
                "MaxKeys": max_items,
            }
            
            if continuation_token:
                params["ContinuationToken"] = continuation_token
            
            # List objects
            response = self.s3_client.list_objects_v2(**params)
            
            # Parse results
            for obj in response.get("Contents", []):
                key = obj["Key"]
                name = self._extract_name_from_key(key)
                
                # Skip if not a markdown file
                if not any(name.lower().endswith(ext) for ext in self.VALID_EXTENSIONS):
                    continue
                
                doc = S3Document(
                    name=name,
                    key=key,
                    size_bytes=obj["Size"],
                    last_modified=obj["LastModified"].timestamp(),
                    etag=obj["ETag"].strip('"'),
                )
                documents.append(doc)
            
            # Sort alphabetically by name (case-insensitive)
            # Requirements: 2.3 - Sort documents alphabetically
            documents.sort(key=lambda d: d.name.lower())
            
            # Get continuation token for next page
            next_token = response.get("NextContinuationToken")
            
            logger.info(f"Listed {len(documents)} documents, has_more={next_token is not None}")
            return documents, next_token
            
        except ClientError as e:
            error_code = e.response["Error"]["Code"]
            logger.error(f"S3 list error: {error_code} - {e}")
            raise S3DocumentError(f"Failed to list documents: {e}")
    
    async def add_document(
        self,
        source_path: Path,
        name: str
    ) -> S3Document:
        """
        Upload markdown document to S3.
        
        Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 10.1
        
        Args:
            source_path: Path to the local markdown file
            name: Name for the document in S3
            
        Returns:
            S3Document for the uploaded document
            
        Raises:
            InvalidMarkdownError: If source is not a markdown file
            DocumentExistsError: If document already exists
            S3DocumentError: For S3 operation errors
        """
        source_path = Path(source_path)
        
        # Validate markdown extension
        if not self.validate_markdown(source_path):
            raise InvalidMarkdownError(
                str(source_path),
                f"File must have extension: {', '.join(self.VALID_EXTENSIONS)}"
            )
        
        # Check source file exists
        if not source_path.exists():
            raise S3DocumentError(f"Source file not found: {source_path}")
        
        if not source_path.is_file():
            raise S3DocumentError(f"Source is not a file: {source_path}")
        
        # Check if document already exists
        if await self.document_exists(name):
            raise DocumentExistsError(name)
        
        # Get S3 key
        key = self._get_document_key(name)
        
        try:
            # Read file content
            content = source_path.read_bytes()
            
            # Upload to S3
            self.s3_client.put_object(
                Bucket=self.bucket_name,
                Key=key,
                Body=content,
                ContentType="text/markdown",
            )
            
            # Get object metadata for response
            response = self.s3_client.head_object(
                Bucket=self.bucket_name,
                Key=key
            )
            
            doc = S3Document(
                name=self._extract_name_from_key(key),
                key=key,
                size_bytes=response["ContentLength"],
                last_modified=response["LastModified"].timestamp(),
                etag=response["ETag"].strip('"'),
            )
            
            logger.info(f"Added document: {doc.name} ({doc.size_bytes} bytes)")
            return doc
            
        except ClientError as e:
            error_code = e.response["Error"]["Code"]
            logger.error(f"S3 upload error: {error_code} - {e}")
            raise S3DocumentError(f"Failed to add document: {e}")
    
    async def update_document(
        self,
        source_path: Path,
        name: str
    ) -> S3Document:
        """
        Update existing document in S3.
        
        Requirements: 4.1, 4.2, 4.3, 4.4, 10.3
        
        Args:
            source_path: Path to the local markdown file
            name: Name of the document to update
            
        Returns:
            S3Document for the updated document
            
        Raises:
            InvalidMarkdownError: If source is not a markdown file
            DocumentNotFoundError: If document doesn't exist
            S3DocumentError: For S3 operation errors
        """
        source_path = Path(source_path)
        
        # Validate markdown extension
        if not self.validate_markdown(source_path):
            raise InvalidMarkdownError(
                str(source_path),
                f"File must have extension: {', '.join(self.VALID_EXTENSIONS)}"
            )
        
        # Check source file exists
        if not source_path.exists():
            raise S3DocumentError(f"Source file not found: {source_path}")
        
        if not source_path.is_file():
            raise S3DocumentError(f"Source is not a file: {source_path}")
        
        # Check if document exists (must exist for update)
        if not await self.document_exists(name):
            raise DocumentNotFoundError(name)
        
        # Get S3 key
        key = self._get_document_key(name)
        
        try:
            # Read file content
            content = source_path.read_bytes()
            
            # Upload to S3 (overwrites existing)
            self.s3_client.put_object(
                Bucket=self.bucket_name,
                Key=key,
                Body=content,
                ContentType="text/markdown",
            )
            
            # Get object metadata for response
            response = self.s3_client.head_object(
                Bucket=self.bucket_name,
                Key=key
            )
            
            doc = S3Document(
                name=self._extract_name_from_key(key),
                key=key,
                size_bytes=response["ContentLength"],
                last_modified=response["LastModified"].timestamp(),
                etag=response["ETag"].strip('"'),
            )
            
            logger.info(f"Updated document: {doc.name} ({doc.size_bytes} bytes)")
            return doc
            
        except ClientError as e:
            error_code = e.response["Error"]["Code"]
            logger.error(f"S3 update error: {error_code} - {e}")
            raise S3DocumentError(f"Failed to update document: {e}")
    
    async def remove_document(self, name: str) -> bool:
        """
        Remove document from S3.
        
        Requirements: 5.1, 5.4, 10.4
        
        Args:
            name: Name of the document to remove
            
        Returns:
            True if document was removed
            
        Raises:
            DocumentNotFoundError: If document doesn't exist
            S3DocumentError: For S3 operation errors
        """
        # Check if document exists
        if not await self.document_exists(name):
            raise DocumentNotFoundError(name)
        
        # Get S3 key
        key = self._get_document_key(name)
        
        try:
            # Delete object
            self.s3_client.delete_object(
                Bucket=self.bucket_name,
                Key=key
            )
            
            logger.info(f"Removed document: {name}")
            return True
            
        except ClientError as e:
            error_code = e.response["Error"]["Code"]
            logger.error(f"S3 delete error: {error_code} - {e}")
            raise S3DocumentError(f"Failed to remove document: {e}")
