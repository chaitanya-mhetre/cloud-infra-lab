# Standard mode: ALB -> ECS Fargate (private subnets) -> RDS + ElastiCache (isolated subnets).
# Composed from the single-purpose modules so staging and prod-like differ only in inputs.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  name       = "${var.project}-${var.env}"
  ssm_prefix = "/slotwise/${var.env}"
  acct       = data.aws_caller_identity.current.account_id
  part       = data.aws_partition.current.partition

  state_bucket_arn = "arn:${local.part}:s3:::${local.acct}-${var.project}-tfstate"
  lock_table_arn   = "arn:${local.part}:dynamodb:${data.aws_region.current.name}:${local.acct}:table/${var.project}-tf-locks"
}

data "aws_ecr_repository" "slotwise" {
  name = "${var.project}/slotwise"
}

module "network" {
  source = "../network"

  name                       = local.name
  cidr_block                 = var.cidr_block
  az_count                   = 2
  enable_nat_gateway         = true # tasks call SES/LLM/webhook targets
  enable_interface_endpoints = var.enable_interface_endpoints
}

module "security" {
  source = "../security"

  name   = local.name
  vpc_id = module.network.vpc_id
  mode   = "standard"
}

module "storage" {
  source = "../storage"

  name          = local.name
  force_destroy = var.disposable
}

module "database" {
  source = "../database"

  name                  = local.name
  subnet_ids            = module.network.data_subnet_ids
  security_group_ids    = [module.security.db_sg_id]
  instance_class        = var.db.instance_class
  multi_az              = var.db.multi_az
  backup_retention_days = var.db.backup_retention_days
  deletion_protection   = var.db.deletion_protection
  skip_final_snapshot   = var.db.skip_final_snapshot
}

module "cache" {
  source = "../cache"

  name               = local.name
  subnet_ids         = module.network.data_subnet_ids
  security_group_ids = [module.security.cache_sg_id]
  node_type          = var.cache_node_type
  replicas           = var.cache_replicas
}

module "secrets" {
  source = "../secrets"

  path_prefix = local.ssm_prefix
  # Connection strings contain app-role passwords created by migrations, so they are set out-of-band.
  secret_names = [
    "DATABASE_URL",
    "MIGRATION_DATABASE_URL",
    "WORKER_DATABASE_URL",
    "JWT_SECRET",
    "FERNET_KEY",
    "MOCKPAY_WEBHOOK_SECRET",
  ]
  plain_parameters = {
    REDIS_URL         = "${module.cache.url_base}/0"
    CELERY_BROKER_URL = "${module.cache.url_base}/1"
    S3_BUCKET         = module.storage.bucket_name
  }
}

module "iam" {
  source = "../iam"

  name                = local.name
  ssm_path_prefix     = local.ssm_prefix
  ecr_repository_arns = [data.aws_ecr_repository.slotwise.arn]
  uploads_bucket_arn  = module.storage.bucket_arn
  log_group_arns      = [module.ecs.log_group_arn]
  create_ecs_roles    = true

  github_owner              = var.github_owner
  create_github_apply_role  = true
  apply_environment         = "infra-${var.env}"
  create_github_deploy_role = true
  app_repos                 = var.app_repos
  ecs_cluster_arn           = module.ecs.cluster_arn
  state_bucket_arn          = local.state_bucket_arn
  lock_table_arn            = local.lock_table_arn
}

module "loadbalancer" {
  source = "../loadbalancer"

  name                = local.name
  vpc_id              = module.network.vpc_id
  public_subnet_ids   = module.network.public_subnet_ids
  security_group_ids  = [module.security.alb_sg_id]
  domain_name         = var.domain_name
  route53_zone_id     = var.route53_zone_id
  deletion_protection = !var.disposable
}

module "ecs" {
  source = "../compute-ecs"

  name                   = local.name
  app_subnet_ids         = module.network.app_subnet_ids
  app_security_group_ids = [module.security.app_sg_id]
  target_group_arn       = module.loadbalancer.target_group_arn
  execution_role_arn     = module.iam.ecs_execution_role_arn
  task_role_arn          = module.iam.ecs_task_role_arn
  image_repo             = data.aws_ecr_repository.slotwise.repository_url
  image_tag              = var.image_tag
  secret_arns            = module.secrets.secret_arns
  environment = {
    SLOTWISE_ENV        = var.env
    SLOTWISE_AWS_REGION = data.aws_region.current.name
  }
  api                = var.api
  worker             = var.worker
  log_retention_days = var.log_retention_days
}

module "observability" {
  source = "../observability"

  name                    = local.name
  alarm_email             = var.alarm_email
  alb_arn_suffix          = module.loadbalancer.alb_arn_suffix
  target_group_arn_suffix = module.loadbalancer.target_group_arn_suffix
  ecs_cluster             = module.ecs.cluster_name
  rds_instance_id         = module.database.instance_id
  redis_group_id          = module.cache.replication_group_id
  app_log_group_name      = module.ecs.log_group_name
}
