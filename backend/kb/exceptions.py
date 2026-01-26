"""
Knowledge Base Exceptions

Custom exceptions for KB operations.
"""


class KBError(Exception):
    """Base exception for Knowledge Base errors."""
    pass


class DocumentNotFoundError(KBError):
    """Raised when a document is not found in the knowledge base."""
    
    def __init__(self, name: str):
        self.name = name
        super().__init__(f"Document not found: {name}")


class InvalidMarkdownError(KBError):
    """Raised when a file is not a valid markdown file."""
    
    def __init__(self, path: str, reason: str = "Not a markdown file"):
        self.path = path
        self.reason = reason
        super().__init__(f"Invalid markdown file '{path}': {reason}")


class DocumentExistsError(KBError):
    """Raised when trying to add a document that already exists."""
    
    def __init__(self, name: str):
        self.name = name
        super().__init__(f"Document already exists: {name}")
