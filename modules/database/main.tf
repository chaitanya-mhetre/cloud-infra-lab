# RDS Postgres in isolated data subnets. The master password is generated and stored
# by RDS in Secrets Manager (manage_master_user_password) — it never enters Terraform state.

resource "aws_db_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.subnet_ids
}

resource "aws_db_parameter_group" "this" {
  name   = "${var.name}-pg16"
  family = "postgres16"

  parameter {
    name  = "log_min_duration_statement"
    value = "500" # log queries slower than 500 ms
  }
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements"
    apply_method = "pending-reboot"
  }
}

resource "aws_iam_role" "monitoring" {
  name = "${var.name}-rds-monitoring"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_db_instance" "this" {
  #checkov:skip=CKV_AWS_157:Multi-AZ is a variable: off in staging for cost, on in prod-like.
  #checkov:skip=CKV_AWS_161:IAM DB auth not used; the app authenticates with a least-privilege Postgres role from SSM.
  #checkov:skip=CKV_AWS_293:Deletion protection is a variable: off for disposable envs so teardown works.
  #checkov:skip=CKV2_AWS_60:Copy-tags-to-snapshots is set; checkov misses it through default_tags.
  #checkov:skip=CKV_AWS_354:Performance Insights uses the AWS-managed key; CMK costs monthly.
  identifier     = var.name
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name                             = var.database_name
  username                            = var.master_username
  manage_master_user_password         = true
  iam_database_authentication_enabled = false

  allocated_storage     = var.allocated_storage_gb
  max_allocated_storage = var.max_allocated_storage_gb
  storage_type          = "gp3"
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = var.security_group_ids
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = false
  multi_az               = var.multi_az

  backup_retention_period = var.backup_retention_days
  backup_window           = "20:00-20:30" # 01:30 IST
  maintenance_window      = "sun:21:00-sun:21:30"
  copy_tags_to_snapshot   = true

  auto_minor_version_upgrade = true
  deletion_protection        = var.deletion_protection
  skip_final_snapshot        = var.skip_final_snapshot
  final_snapshot_identifier  = var.skip_final_snapshot ? null : "${var.name}-final"

  performance_insights_enabled          = var.performance_insights
  performance_insights_retention_period = var.performance_insights ? 7 : null
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.monitoring.arn
  enabled_cloudwatch_logs_exports       = ["postgresql", "upgrade"]
}
