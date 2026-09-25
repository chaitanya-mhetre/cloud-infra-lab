output "state_bucket" {
  description = "Name of the S3 bucket holding Terraform state. Put it in envs/*/backend.hcl."
  value       = aws_s3_bucket.state.bucket
}

output "lock_table" {
  description = "DynamoDB table used for state locking."
  value       = aws_dynamodb_table.locks.name
}

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider (null if not created here)."
  value       = one(aws_iam_openid_connect_provider.github[*].arn)
}
