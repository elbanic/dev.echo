"""
LLM Integration Exceptions

Custom exceptions for LLM-related errors.
"""


class LLMError(Exception):
    """Base exception for LLM errors."""
    pass


class OllamaUnavailableError(LLMError):
    """Raised when Ollama service is not running or unreachable."""
    
    def __init__(self, message: str = "Ollama service is unavailable"):
        super().__init__(message)


class ModelNotFoundError(LLMError):
    """Raised when the requested model is not found in Ollama."""
    
    def __init__(self, model_name: str):
        self.model_name = model_name
        super().__init__(f"Model '{model_name}' not found. Try: ollama pull {model_name}")


class ContextTooLargeError(LLMError):
    """Raised when the context exceeds model limits."""
    
    def __init__(self, message: str = "Context too large for model"):
        super().__init__(message)


class QueryTimeoutError(LLMError):
    """Raised when LLM query times out."""
    
    def __init__(self, timeout_seconds: float):
        self.timeout_seconds = timeout_seconds
        super().__init__(f"LLM query timed out after {timeout_seconds} seconds")
