# ElastiCache Redis (replication group so failover can be switched on by changing `replicas`).
# Holds: Celery broker, rate-limit counters, idempotency keys, cache. It is NOT a system of record —
# losing it must be survivable (see docs/scaling.md).

resource "aws_elasticache_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.subnet_ids
}

# Celery uses Redis as a BROKER: evicting keys would silently drop queued jobs.
# `noeviction` makes Redis refuse writes when full instead — loud failure beats silent data loss.
resource "aws_elasticache_parameter_group" "this" {
  name   = "${var.name}-redis7"
  family = "redis7"

  parameter {
    name  = "maxmemory-policy"
    value = "noeviction"
  }
}

resource "aws_elasticache_replication_group" "this" {
  #checkov:skip=CKV2_AWS_50:Failover follows var.replicas: off in staging (single node), on in prod-like.
  #checkov:skip=CKV_AWS_191:Encryption at rest uses the AWS-managed key; CMK adds cost.
  #checkov:skip=CKV_AWS_31:AUTH token omitted in the lab: access is SG-restricted to the app tier and in-transit TLS is on. Tracked in docs/security.md.
  replication_group_id = var.name
  description          = "${var.name} redis"
  engine               = "redis"
  engine_version       = var.engine_version
  node_type            = var.node_type
  port                 = 6379
  parameter_group_name = aws_elasticache_parameter_group.this.name

  num_cache_clusters         = 1 + var.replicas
  automatic_failover_enabled = var.replicas > 0
  multi_az_enabled           = var.replicas > 0

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = var.security_group_ids

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true

  snapshot_retention_limit = 0 # cache/broker only; no backups needed
  apply_immediately        = true
}
