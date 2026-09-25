# Instance profile for the low-cost dev host.
# Grants: SSM Session Manager (instead of SSH), read app config, pull images, write logs, uploads.

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2" {
  count = var.create_ec2_role ? 1 : 0

  name               = "${var.name}-host"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

# AWS-managed policy for the SSM agent (Session Manager, Run Command used by scripts/deploy.sh).
resource "aws_iam_role_policy_attachment" "ec2_ssm_core" {
  count = var.create_ec2_role ? 1 : 0

  role       = aws_iam_role.ec2[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "ec2_app_config" {
  count = var.create_ec2_role ? 1 : 0

  name   = "read-app-config"
  role   = aws_iam_role.ec2[0].id
  policy = data.aws_iam_policy_document.read_app_config.json
}

resource "aws_iam_role_policy" "ec2_pull" {
  count = var.create_ec2_role && length(var.ecr_repository_arns) > 0 ? 1 : 0

  name   = "pull-images"
  role   = aws_iam_role.ec2[0].id
  policy = data.aws_iam_policy_document.pull_images[0].json
}

resource "aws_iam_role_policy" "ec2_logs" {
  count = var.create_ec2_role && length(var.log_group_arns) > 0 ? 1 : 0

  name   = "write-logs"
  role   = aws_iam_role.ec2[0].id
  policy = data.aws_iam_policy_document.write_logs[0].json
}

resource "aws_iam_role_policy" "ec2_uploads" {
  count = var.create_ec2_role && var.uploads_bucket_arn != null ? 1 : 0

  name   = "uploads"
  role   = aws_iam_role.ec2[0].id
  policy = data.aws_iam_policy_document.uploads[0].json
}

resource "aws_iam_instance_profile" "ec2" {
  count = var.create_ec2_role ? 1 : 0

  name = "${var.name}-host"
  role = aws_iam_role.ec2[0].name
}
