"""
AWS Configuration Module

Provides configuration management for AWS services used in Phase 2.
Configuration is loaded from environment variables.

Environment Variables:
- AWS_REGION: AWS region (default: us-west-2)
- DEVECHO_S3_BUCKET: S3 bucket name for KB documents
- DEVECHO_S3_PREFIX: S3 key prefix for documents (default: kb-documents/)
- DEVECHO_KB_ID: Bedrock Knowledge Base ID
- DEVECHO_BEDROCK_MODEL: Bedrock model ID (default: Claude Sonnet)
"""

from dataclasses import dataclass
import os


@dataclass
class AWSConfig:
    """AWS configuration for Phase 2 services."""
    
    # AWS Configuration
    aws_region: str = "us-west-2"
    s3_bucket: str = ""
    s3_prefix: str = "kb-documents/"
    knowledge_base_id: str = ""
    
    # Model Configuration
    bedrock_model_id: str = "us.anthropic.claude-sonnet-4-20250514-v1:0"
    
    # RAG Configuration
    retrieval_top_k: int = 5
    context_max_tokens: int = 4000
    
    @classmethod
    def from_env(cls) -> "AWSConfig":
        """
        Load configuration from environment variables.
        
        Returns:
            AWSConfig instance with values from environment
        """
        return cls(
            aws_region=os.getenv("AWS_REGION", "us-west-2"),
            s3_bucket=os.getenv("DEVECHO_S3_BUCKET", ""),
            s3_prefix=os.getenv("DEVECHO_S3_PREFIX", "kb-documents/"),
            knowledge_base_id=os.getenv("DEVECHO_KB_ID", ""),
            bedrock_model_id=os.getenv(
                "DEVECHO_BEDROCK_MODEL",
                "us.anthropic.claude-sonnet-4-20250514-v1:0"
            ),
        )
    
    def validate(self) -> tuple[bool, list[str]]:
        """
        Validate configuration has required values.
        
        Returns:
            Tuple of (is_valid, list of missing fields)
        """
        missing = []
        
        if not self.s3_bucket:
            missing.append("DEVECHO_S3_BUCKET")
        if not self.knowledge_base_id:
            missing.append("DEVECHO_KB_ID")
        
        return len(missing) == 0, missing
    
    def is_configured(self) -> bool:
        """Check if AWS services are configured."""
        is_valid, _ = self.validate()
        return is_valid
