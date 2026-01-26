"""
Knowledge Base Manager

Manages knowledge base documents for dev.echo.
Supports markdown document operations: list, add, update, remove.

Requirements: 4.1, 4.2, 4.3, 4.4, 4.5
"""

from .manager import KnowledgeBaseManager, KBDocument
from .exceptions import (
    KBError,
    DocumentNotFoundError,
    InvalidMarkdownError,
    DocumentExistsError,
)

__all__ = [
    "KnowledgeBaseManager",
    "KBDocument",
    "KBError",
    "DocumentNotFoundError",
    "InvalidMarkdownError",
    "DocumentExistsError",
]
