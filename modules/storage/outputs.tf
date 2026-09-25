output "bucket_name" {
  description = "Uploads bucket name."
  value       = aws_s3_bucket.uploads.bucket
}

output "bucket_arn" {
  description = "Uploads bucket ARN (IAM scopes access to uploads/*)."
  value       = aws_s3_bucket.uploads.arn
}
