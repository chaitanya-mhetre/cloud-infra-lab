data "aws_caller_identity" "current" {}

locals {
  state_bucket_name = "${data.aws_caller_identity.current.account_id}-${var.project}-tfstate"
}

# ---------------------------------------------------------------------------
# Remote state bucket
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "state" {
  #checkov:skip=CKV_AWS_18:Access logging needs a second log bucket; cost/complexity not justified for a single-user lab state bucket (CloudTrail data events are the upgrade path).
  #checkov:skip=CKV_AWS_144:Cross-region replication doubles storage + adds a second region; versioning covers accidental overwrite for this lab.
  #checkov:skip=CKV2_AWS_62:No consumer for bucket event notifications.
  bucket = local.state_bucket_name

  # Losing this bucket means losing track of every resource Terraform manages.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled" # lets us recover a corrupted/overwritten state file
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"
    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Deny any non-TLS access to the state (state files contain resource attributes).
data "aws_iam_policy_document" "state_tls_only" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state_tls_only.json
}

# ---------------------------------------------------------------------------
# State lock table: Terraform writes a LockID item while a plan/apply runs,
# so two people (or two CI jobs) can't modify the same state concurrently.
# ---------------------------------------------------------------------------
resource "aws_dynamodb_table" "locks" {
  #checkov:skip=CKV_AWS_119:Lock items hold only LockID + digest; AWS-owned key encryption is sufficient and avoids a CMK monthly fee.
  name         = "${var.project}-tf-locks"
  billing_mode = "PAY_PER_REQUEST" # pennies for a lab; no capacity planning
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }
}

# ---------------------------------------------------------------------------
# GitHub Actions OIDC identity provider (account-wide, created once).
# Roles that trust it live in modules/iam and are scoped per repo + branch.
# ---------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # AWS no longer validates this thumbprint for GitHub's OIDC endpoint, but the argument is still accepted.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}
