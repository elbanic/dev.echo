# Requirements Document

## Introduction

dev.echo Phase 2 extends the developer-focused AI partner with cloud services and knowledge base capabilities. Building on Phase 1's local audio capture and transcription foundation, Phase 2 introduces AWS Bedrock integration for cloud LLM queries with RAG capabilities using Bedrock Knowledge Base. Documents are stored in S3 and automatically indexed by Bedrock Knowledge Base for semantic retrieval. The system enables context-aware assistance by combining real-time conversation context with the developer's personal knowledge repository.

## Glossary

- **CLI_Interface**: The command-line interface that provides the main user interaction point for dev.echo
- **KB_Management_Mode**: The operational mode for managing knowledge base documents
- **S3_Bucket**: The AWS S3 bucket storing raw markdown documents for the knowledge base
- **Bedrock_Knowledge_Base**: AWS Bedrock Knowledge Base service that indexes S3 documents and provides RAG capabilities
- **Cloud_LLM**: AWS Bedrock-based LLM service for context-aware responses with RAG capabilities
- **Local_LLM**: The Ollama-based local LLM for quick responses (from Phase 1)
- **RAG_Pipeline**: Retrieval-Augmented Generation pipeline using Bedrock Knowledge Base for semantic retrieval
- **Strands_Agent**: The Python agent framework used for LLM orchestration (https://strandsagents.com)
- **Transcript_Display**: The area showing real-time transcription and LLM responses
- **Reindexing**: The process of updating Bedrock Knowledge Base index after S3 document changes

## Requirements

### Requirement 1: Knowledge Base Management Mode Entry and Exit

**User Story:** As a developer, I want to enter and exit knowledge base management mode, so that I can manage my personal knowledge repository.

#### Acceptance Criteria

1. WHEN a user enters `/managekb` in Command_Mode THEN THE CLI_Interface SHALL transition to KB_Management_Mode and display available KB commands
2. WHEN a user enters `/quit` in KB_Management_Mode THEN THE CLI_Interface SHALL return to Command_Mode
3. WHILE in KB_Management_Mode THEN THE CLI_Interface SHALL display a mode indicator showing "KB Management Mode"
4. WHILE in KB_Management_Mode THEN THE CLI_Interface SHALL only accept KB-specific commands (/list, /add, /update, /remove, /quit)

### Requirement 2: Knowledge Base Document Listing

**User Story:** As a developer, I want to list all documents in my knowledge base, so that I can see what knowledge is available.

#### Acceptance Criteria

1. WHEN a user enters `/list` in KB_Management_Mode THEN THE CLI_Interface SHALL retrieve and display all documents from the S3_Bucket with name, size, and last modified date
2. WHEN the S3_Bucket is empty THEN THE CLI_Interface SHALL display a message indicating no documents are available
3. WHEN listing documents THEN THE CLI_Interface SHALL sort documents alphabetically by name
4. WHEN a document list exceeds 20 items THEN THE CLI_Interface SHALL implement S3 pagination to display documents in pages

### Requirement 3: Knowledge Base Document Addition

**User Story:** As a developer, I want to add markdown documents to my knowledge base, so that I can build my personal knowledge repository.

#### Acceptance Criteria

1. WHEN a user enters `/add {from_path} {name}` THEN THE CLI_Interface SHALL upload the markdown file from the specified local path to the S3_Bucket with the given name
2. WHEN a document is successfully uploaded to S3 THEN THE CLI_Interface SHALL display a confirmation message with the document name and size
3. IF a user attempts to add a non-markdown file THEN THE CLI_Interface SHALL reject the operation and display an error message specifying valid file types (.md, .markdown)
4. IF a user attempts to add a file that does not exist locally THEN THE CLI_Interface SHALL display an error message with the invalid path
5. IF a document with the same name already exists in S3 THEN THE CLI_Interface SHALL display an error message and suggest using /update instead
6. WHEN a document is uploaded to S3 THEN THE Bedrock_Knowledge_Base SHALL automatically index the new document

### Requirement 4: Knowledge Base Document Update

**User Story:** As a developer, I want to update existing documents in my knowledge base, so that I can keep my knowledge current.

#### Acceptance Criteria

1. WHEN a user enters `/update {from_path} {name}` THEN THE CLI_Interface SHALL replace the existing document in S3_Bucket with the file from the specified local path
2. WHEN a document is successfully updated in S3 THEN THE CLI_Interface SHALL display a confirmation message with the document name and new size
3. IF the target document does not exist in S3 THEN THE CLI_Interface SHALL display an error message and suggest using /add instead
4. IF the source file does not exist locally THEN THE CLI_Interface SHALL display an error message with the invalid path
5. WHEN a document is updated in S3 THEN THE Bedrock_Knowledge_Base SHALL automatically reindex the updated document

### Requirement 5: Knowledge Base Document Removal

**User Story:** As a developer, I want to remove documents from my knowledge base, so that I can maintain relevant knowledge only.

#### Acceptance Criteria

1. WHEN a user enters `/remove {name}` THEN THE CLI_Interface SHALL delete the document with the specified filename from the S3_Bucket
2. WHEN a document is successfully removed from S3 THEN THE CLI_Interface SHALL trigger Bedrock_Knowledge_Base reindexing
3. WHEN reindexing completes THEN THE CLI_Interface SHALL display a confirmation message with the removed document name
4. IF the specified document does not exist in S3 THEN THE CLI_Interface SHALL display an error message listing available documents

### Requirement 6: Cloud LLM Integration with Strands Agent

**User Story:** As a developer, I want to query a cloud-based LLM with my conversation context, so that I can get more powerful AI assistance.

#### Acceptance Criteria

1. WHEN a user enters `/chat {contents}` in Transcribing_Mode THEN THE Strands_Agent SHALL send the query with current conversation context to the Cloud_LLM via AWS Bedrock
2. WHEN the Cloud_LLM generates a response THEN THE Transcript_Display SHALL display it in the center with a distinct color from transcript entries
3. WHILE waiting for a Cloud_LLM response THEN THE CLI_Interface SHALL display a loading animation with elapsed time
4. WHEN processing a query THEN THE Strands_Agent SHALL use Bedrock_Knowledge_Base to retrieve relevant documents as context
5. IF the Cloud_LLM service is unavailable THEN THE CLI_Interface SHALL display an error message and suggest using /quick for local LLM
6. WHEN a Cloud_LLM response is received THEN THE CLI_Interface SHALL display the sources used from the Bedrock_Knowledge_Base

### Requirement 7: Semantic Search via Bedrock Knowledge Base

**User Story:** As a developer, I want the system to find contextually relevant documents from my knowledge base, so that I get personalized assistance based on my past work.

#### Acceptance Criteria

1. WHEN the Strands_Agent receives a query THEN THE Strands_Agent SHALL call Bedrock_Knowledge_Base to retrieve relevant documents
2. WHEN performing semantic search THEN THE Bedrock_Knowledge_Base SHALL use vector similarity for contextual matching
3. WHEN multiple relevant documents are found THEN THE Strands_Agent SHALL include the top-k results ranked by relevance score as context
4. WHEN no relevant documents are found THEN THE Strands_Agent SHALL proceed with the query using only conversation context
5. WHEN semantic search completes THEN THE Strands_Agent SHALL log the retrieved document names and relevance scores

### Requirement 8: RAG Pipeline Context Assembly

**User Story:** As a developer, I want the system to intelligently combine conversation context with retrieved documents, so that I get comprehensive and relevant responses.

#### Acceptance Criteria

1. WHEN assembling context for the Cloud_LLM THEN THE Strands_Agent SHALL include the current conversation transcript
2. WHEN assembling context THEN THE Strands_Agent SHALL include relevant documents retrieved via Bedrock_Knowledge_Base
3. WHEN the combined context exceeds token limits THEN THE Strands_Agent SHALL prioritize recent conversation and highest-relevance documents
4. WHEN context is assembled THEN THE Strands_Agent SHALL format it clearly for the Cloud_LLM with source attribution
5. WHEN a response is generated THEN THE Strands_Agent SHALL track which documents contributed to the response

### Requirement 9: AWS Bedrock Integration

**User Story:** As a developer, I want the system to use AWS Bedrock for cloud LLM capabilities, so that I can leverage powerful foundation models.

#### Acceptance Criteria

1. WHEN initializing the Cloud_LLM THEN THE Strands_Agent SHALL connect to AWS Bedrock using configured credentials
2. WHEN sending a query to AWS Bedrock THEN THE Strands_Agent SHALL use the configured foundation model (Claude)
3. IF AWS credentials are not configured THEN THE CLI_Interface SHALL display an error message with setup instructions
4. IF AWS Bedrock service returns an error THEN THE CLI_Interface SHALL display the error type and suggest troubleshooting steps
5. WHEN the Cloud_LLM is initialized THEN THE CLI_Interface SHALL display the connected model name in the status area

### Requirement 10: S3 Document Storage

**User Story:** As a developer, I want my knowledge base documents stored reliably in S3, so that they persist and can be indexed by Bedrock Knowledge Base.

#### Acceptance Criteria

1. WHEN a document is added THEN THE CLI_Interface SHALL upload it to the configured S3_Bucket with appropriate metadata
2. WHEN listing documents THEN THE CLI_Interface SHALL retrieve the list from S3_Bucket using pagination
3. WHEN a document is updated THEN THE CLI_Interface SHALL overwrite the existing S3 object
4. WHEN a document is removed THEN THE CLI_Interface SHALL delete the S3 object
5. IF S3 operations fail THEN THE CLI_Interface SHALL display the AWS error message and suggest checking permissions

### Requirement 11: Bedrock Knowledge Base Synchronization

**User Story:** As a developer, I want my S3 documents to be automatically indexed by Bedrock Knowledge Base, so that they are searchable via semantic search.

#### Acceptance Criteria

1. WHEN documents are added or updated in S3 THEN THE Bedrock_Knowledge_Base SHALL automatically detect and index changes
2. WHEN a document is removed from S3 THEN THE CLI_Interface SHALL trigger a sync job to update the Bedrock_Knowledge_Base index
3. WHEN the application starts THEN THE CLI_Interface SHALL verify Bedrock_Knowledge_Base connectivity and display sync status
4. IF Bedrock_Knowledge_Base sync fails THEN THE CLI_Interface SHALL display an error message with the failure reason
5. WHEN sync completes THEN THE CLI_Interface SHALL display the number of indexed documents

