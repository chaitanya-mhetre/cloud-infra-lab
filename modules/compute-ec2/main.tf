# Low-cost mode: ONE Graviton EC2 host running Docker Compose (nginx + api + worker + redis + postgres).
# Access is via SSM Session Manager — there is no SSH key and port 22 is closed.

data "aws_region" "current" {}

# Latest Amazon Linux 2023 arm64 AMI, resolved through AWS's public SSM parameter.
data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

resource "aws_cloudwatch_log_group" "host" {
  #checkov:skip=CKV_AWS_338:Dev container logs; 1-year retention not required. Retention is a variable.
  #checkov:skip=CKV_AWS_158:CloudWatch default encryption is sufficient for dev logs; CMK adds cost.
  name              = "/${var.app_name}/${var.name}/containers"
  retention_in_days = var.log_retention_days
}

locals {
  app_dir = "/opt/${var.app_name}"

  # Values rendered into the files shipped to the host.
  tpl = {
    app_name        = var.app_name
    app_dir         = local.app_dir
    region          = data.aws_region.current.name
    ssm_path_prefix = var.ssm_path_prefix
    image_repo      = var.api_image_repo
    image_tag       = var.initial_image_tag
    domain_name     = var.domain_name
    acme_email      = var.acme_email
    log_group       = aws_cloudwatch_log_group.host.name
    api_command     = var.api_command
    worker_command  = var.worker_command
    migrate_command = var.migrate_command
  }

  files = {
    "docker-compose.yml" = templatefile("${path.module}/files/docker-compose.yml.tftpl", local.tpl)
    "nginx.conf"         = templatefile("${path.module}/files/nginx.conf.tftpl", local.tpl)
    "fetch-env.sh"       = templatefile("${path.module}/files/fetch-env.sh.tftpl", local.tpl)
    "host-deploy.sh"     = templatefile("${path.module}/files/host-deploy.sh.tftpl", local.tpl)
  }

  user_data = templatefile("${path.module}/files/cloud-init.yaml.tftpl", merge(local.tpl, {
    files = local.files
  }))
}

resource "aws_instance" "host" {
  #checkov:skip=CKV_AWS_88:Low-cost mode deliberately uses a public IP (no NAT/ALB). Only 80/443 are open; SSH is closed.
  #checkov:skip=CKV2_AWS_41:Instance profile is attached via var.instance_profile_name; checkov can't resolve it across modules.
  ami                         = data.aws_ssm_parameter.al2023_arm64.value
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = var.security_group_ids
  iam_instance_profile        = var.instance_profile_name
  associate_public_ip_address = true
  monitoring                  = true # 1-minute CloudWatch metrics
  ebs_optimized               = true
  user_data                   = local.user_data
  user_data_replace_on_change = true # changing compose/nginx templates recreates the host (it's cattle)

  # IMDSv2 only: blocks the classic SSRF-to-credentials attack against the metadata service.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2 # containers are one extra network hop away
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_gb
    encrypted             = true
    delete_on_termination = true
  }

  tags = { Name = "${var.name}-host" }

  lifecycle {
    # A newer AMI shouldn't silently replace a running host; bump it deliberately.
    ignore_changes = [ami]
  }
}

# Stable public IP so DNS / smoke tests survive stop-start.
resource "aws_eip" "host" {
  instance = aws_instance.host.id
  domain   = "vpc"
  tags     = { Name = "${var.name}-host" }
}
