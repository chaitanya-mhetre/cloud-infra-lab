# dev = LOW-COST mode: one public EC2 host running Docker Compose.
# No NAT gateway, no ALB, no interface endpoints (these dominate small-setup cost).

locals {
  env        = "dev"
  name       = "${var.project}-${local.env}"
  ssm_prefix = "/slotwise/${local.env}"
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  state_bucket_arn = "arn:${data.aws_partition.current.partition}:s3:::${data.aws_caller_identity.current.account_id}-${var.project}-tfstate"
  lock_table_arn   = "arn:${data.aws_partition.current.partition}:dynamodb:${var.region}:${data.aws_caller_identity.current.account_id}:table/${var.project}-tf-locks"
}

# Created by envs/shared; looked up by name so dev can be destroyed/recreated independently.
data "aws_ecr_repository" "slotwise" {
  name = "${var.project}/slotwise"
}

module "network" {
  source = "../../modules/network"

  name                       = local.name
  cidr_block                 = "10.20.0.0/16"
  az_count                   = 2
  enable_nat_gateway         = false
  enable_interface_endpoints = false
  enable_flow_logs           = true
  flow_logs_retention_days   = 3
}

module "security" {
  source = "../../modules/security"

  name                 = local.name
  vpc_id               = module.network.vpc_id
  mode                 = "lowcost"
  public_ingress_cidrs = var.public_ingress_cidrs
}

module "secrets" {
  source = "../../modules/secrets"

  path_prefix = local.ssm_prefix
  secret_names = [
    "DATABASE_URL",
    "MIGRATION_DATABASE_URL",
    "WORKER_DATABASE_URL",
    "POSTGRES_PASSWORD",
    "JWT_SECRET",
    "FERNET_KEY",
    "MOCKPAY_WEBHOOK_SECRET",
  ]
  plain_parameters = {
    # Redis runs as a compose service on the host in dev.
    REDIS_URL         = "redis://redis:6379/0"
    CELERY_BROKER_URL = "redis://redis:6379/1"
  }
}

module "iam" {
  source = "../../modules/iam"

  name                = local.name
  ssm_path_prefix     = local.ssm_prefix
  ecr_repository_arns = [data.aws_ecr_repository.slotwise.arn]
  log_group_arns      = [module.host.log_group_arn]
  create_ec2_role     = true

  # CI/CD (M3): gated apply for this env + deploy role for the app repo.
  github_owner              = var.github_owner
  create_github_apply_role  = true
  apply_environment         = "infra-${local.env}"
  create_github_deploy_role = true
  app_repos                 = ["production-fastapi"]
  deploy_instance_tag_env   = local.env
  state_bucket_arn          = local.state_bucket_arn
  lock_table_arn            = local.lock_table_arn
}

module "host" {
  source = "../../modules/compute-ec2"

  name                  = local.name
  subnet_id             = module.network.public_subnet_ids[0]
  security_group_ids    = [module.security.app_sg_id]
  instance_type         = var.instance_type
  instance_profile_name = module.iam.ec2_instance_profile_name
  ssm_path_prefix       = module.secrets.path_prefix
  api_image_repo        = data.aws_ecr_repository.slotwise.repository_url
  initial_image_tag     = var.initial_image_tag
  domain_name           = var.domain_name
  acme_email            = var.acme_email
  log_retention_days    = 3
}

module "observability" {
  source = "../../modules/observability"

  name            = local.name
  alarm_email     = var.alarm_email
  ec2_instance_id = module.host.instance_id
}
