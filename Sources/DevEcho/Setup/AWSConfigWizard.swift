import Foundation

/// AWS configuration wizard
struct AWSConfigWizard {
    private let checker = DependencyChecker()

    /// Configure AWS settings interactively
    /// - Returns: AWSConfig or nil if skipped
    func configure() -> AWSConfig? {
        // Check AWS CLI
        let (awsInstalled, awsVersion) = checker.checkAWSCLI()
        if !awsInstalled {
            SetupProgress.showFailure("AWS CLI not installed")
            SetupProgress.showInfo("Install with: brew install awscli")
            SetupProgress.showInfo("Or download from: https://aws.amazon.com/cli/")
            return nil
        }

        SetupProgress.showSuccess("AWS CLI installed (v\(awsVersion ?? "unknown"))")

        // Check credentials
        let hasCredentials = checker.checkAWSCredentials()
        if !hasCredentials {
            SetupProgress.showFailure("AWS credentials not configured")
            SetupProgress.showInfo("Run 'aws configure' to set up credentials")
            SetupProgress.showInfo("Or set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment variables")

            if !SetupPrompt.askYesNo("Continue without valid credentials?", default: false) {
                return nil
            }
        } else {
            if let accountId = checker.getAWSAccountId() {
                SetupProgress.showSuccess("AWS credentials valid (Account: \(accountId))")
            } else {
                SetupProgress.showSuccess("AWS credentials valid")
            }
        }

        // Get region
        let currentRegion = checker.getAWSRegion()
        let region = SetupPrompt.askText("AWS Region", default: currentRegion)

        // S3 Bucket for KB documents
        print("")
        SetupProgress.showSection("S3 Bucket Configuration")
        SetupProgress.showInfo("S3 bucket is used to store Knowledge Base documents")

        let s3Bucket = SetupPrompt.askText("S3 bucket name (leave empty to skip)")
        var validatedBucket: String? = nil

        if !s3Bucket.isEmpty {
            if verifyS3Bucket(s3Bucket, region: region) {
                SetupProgress.showSuccess("S3 bucket '\(s3Bucket)' accessible")
                validatedBucket = s3Bucket
            } else {
                SetupProgress.showFailure("Cannot access S3 bucket '\(s3Bucket)'")
                SetupProgress.showInfo("Make sure the bucket exists and you have permissions")
            }
        } else {
            SetupProgress.showSkipped("S3 bucket not configured")
        }

        // Knowledge Base ID
        print("")
        SetupProgress.showSection("Bedrock Knowledge Base")
        SetupProgress.showInfo("Knowledge Base ID enables RAG (Retrieval Augmented Generation)")

        let kbId = SetupPrompt.askText("Knowledge Base ID (leave empty to skip)")
        var validatedKBId: String? = nil

        if !kbId.isEmpty {
            if verifyKnowledgeBase(kbId, region: region) {
                SetupProgress.showSuccess("Knowledge Base '\(kbId)' accessible")
                validatedKBId = kbId
            } else {
                SetupProgress.showWarning("Cannot verify Knowledge Base '\(kbId)'")
                SetupProgress.showInfo("Make sure the KB exists and you have bedrock:RetrieveAndGenerate permission")
                if SetupPrompt.askYesNo("Save anyway?", default: true) {
                    validatedKBId = kbId
                }
            }
        } else {
            SetupProgress.showSkipped("Knowledge Base not configured")
        }

        return AWSConfig(
            region: region,
            s3Bucket: validatedBucket,
            knowledgeBaseId: validatedKBId
        )
    }

    /// Verify S3 bucket access
    private func verifyS3Bucket(_ bucket: String, region: String) -> Bool {
        let exitCode = ShellExecutor.execute("aws", arguments: [
            "s3", "ls", "s3://\(bucket)", "--region", region
        ])
        return exitCode == 0
    }

    /// Verify Knowledge Base access
    private func verifyKnowledgeBase(_ kbId: String, region: String) -> Bool {
        // Try to get KB info using bedrock-agent API
        let exitCode = ShellExecutor.execute("aws", arguments: [
            "bedrock-agent", "get-knowledge-base",
            "--knowledge-base-id", kbId,
            "--region", region
        ])
        return exitCode == 0
    }
}
