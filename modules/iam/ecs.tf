# Two roles per ECS task, and they are NOT the same thing:
#   execution role : used by the ECS AGENT before the container starts
#                    (pull image, fetch secrets for injection, create log stream)
#   task role      : used by the APPLICATION code at runtime (S3 uploads, ...)
# Keeping them apart means app code can't read every secret the agent can.

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id] # confused-deputy protection
    }
  }
}

resource "aws_iam_role" "ecs_execution" {
  count              = var.create_ecs_roles ? 1 : 0
  name               = "${var.name}-ecs-exec"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy" "ecs_execution_config" {
  count  = var.create_ecs_roles ? 1 : 0
  name   = "read-app-config"
  role   = aws_iam_role.ecs_execution[0].id
  policy = data.aws_iam_policy_document.read_app_config.json
}

resource "aws_iam_role_policy" "ecs_execution_pull" {
  count  = var.create_ecs_roles && length(var.ecr_repository_arns) > 0 ? 1 : 0
  name   = "pull-images"
  role   = aws_iam_role.ecs_execution[0].id
  policy = data.aws_iam_policy_document.pull_images[0].json
}

resource "aws_iam_role_policy" "ecs_execution_logs" {
  count  = var.create_ecs_roles && length(var.log_group_arns) > 0 ? 1 : 0
  name   = "write-logs"
  role   = aws_iam_role.ecs_execution[0].id
  policy = data.aws_iam_policy_document.write_logs[0].json
}

resource "aws_iam_role" "ecs_task" {
  count              = var.create_ecs_roles ? 1 : 0
  name               = "${var.name}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy" "ecs_task_uploads" {
  count  = var.create_ecs_roles && var.uploads_bucket_arn != null ? 1 : 0
  name   = "uploads"
  role   = aws_iam_role.ecs_task[0].id
  policy = data.aws_iam_policy_document.uploads[0].json
}

data "aws_iam_policy_document" "ecs_exec" {
  statement {
    sid = "EcsExecChannels"
    # ssmmessages actions don't support resource-level permissions.
    actions = [
      "ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ecs_task_exec" {
  count  = var.create_ecs_roles && var.enable_ecs_exec ? 1 : 0
  name   = "ecs-exec"
  role   = aws_iam_role.ecs_task[0].id
  policy = data.aws_iam_policy_document.ecs_exec.json
}
