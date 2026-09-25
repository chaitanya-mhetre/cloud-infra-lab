# Security groups reference OTHER security groups, not CIDRs, wherever possible:
#   internet -> alb -> app -> {db, cache}
# If an app task's IP changes (it always does on Fargate), rules still hold.

locals {
  standard   = var.mode == "standard"
  restricted = var.egress_mode == "restricted"
}

# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  #checkov:skip=CKV2_AWS_5:Attached by compute/database/cache/loadbalancer modules in the calling env; checkov can't see cross-module attachment.
  count = local.standard ? 1 : 0

  name        = "${var.name}-alb"
  description = "Public HTTPS entry point"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-alb" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  for_each = local.standard ? toset(var.public_ingress_cidrs) : toset([])

  security_group_id = aws_security_group.alb[0].id
  description       = "HTTPS from internet"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value
}

# Port 80 exists only to 301-redirect to 443 (listener rule in modules/loadbalancer).
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  for_each = local.standard ? toset(var.public_ingress_cidrs) : toset([])

  security_group_id = aws_security_group.alb[0].id
  description       = "HTTP from internet (redirected to HTTPS)"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  count = local.standard ? 1 : 0

  security_group_id            = aws_security_group.alb[0].id
  description                  = "Forward to app tasks"
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  referenced_security_group_id = aws_security_group.app.id
}

# ---------------------------------------------------------------------------
# App tier (ECS tasks in standard mode, the EC2 host in low-cost mode)
# ---------------------------------------------------------------------------
resource "aws_security_group" "app" {
  #checkov:skip=CKV2_AWS_5:Attached by compute/database/cache/loadbalancer modules in the calling env; checkov can't see cross-module attachment.
  name        = "${var.name}-app"
  description = local.standard ? "API/worker tasks; inbound only from the ALB" : "Low-cost host; 80/443 from internet, no SSH (use SSM)"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-app" }
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  count = local.standard ? 1 : 0

  security_group_id            = aws_security_group.app.id
  description                  = "API port from ALB only"
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  referenced_security_group_id = aws_security_group.alb[0].id
}

resource "aws_vpc_security_group_ingress_rule" "host_http" {
  for_each = local.standard ? toset([]) : toset(var.public_ingress_cidrs)

  security_group_id = aws_security_group.app.id
  description       = "HTTP to nginx (ACME challenge + redirect)"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_ingress_rule" "host_https" {
  for_each = local.standard ? toset([]) : toset(var.public_ingress_cidrs)

  security_group_id = aws_security_group.app.id
  description       = "HTTPS to nginx"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value
}

# Outbound HTTPS. Two modes:
#   open        443 to anywhere (tasks call AWS APIs, SES, LLM providers, webhook targets).
#   restricted  443 only to (a) the VPC CIDR, where the interface endpoints live (ECR, SSM, Logs),
#               (b) the S3 gateway endpoint's prefix list, and (c) an explicit CIDR allow-list.
# Security groups filter by IP, not hostname. Providers behind CDNs change IPs, so hostname
# allow-listing needs AWS Network Firewall (SNI filtering): see docs/security.md.
resource "aws_vpc_security_group_egress_rule" "app_https_out" {
  count = local.restricted ? 0 : 1

  security_group_id = aws_security_group.app.id
  description       = "HTTPS to AWS APIs and third parties"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "app_https_vpc" {
  count = local.restricted ? 1 : 0

  security_group_id = aws_security_group.app.id
  description       = "HTTPS to interface VPC endpoints"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = var.vpc_cidr
}

resource "aws_vpc_security_group_egress_rule" "app_https_s3" {
  count = local.restricted ? 1 : 0

  security_group_id = aws_security_group.app.id
  description       = "HTTPS to S3 via the gateway endpoint (ECR layers, uploads)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = var.s3_prefix_list_id
}

resource "aws_vpc_security_group_egress_rule" "app_https_allowed" {
  for_each = local.restricted ? toset(var.egress_allowed_cidrs) : toset([])

  security_group_id = aws_security_group.app.id
  description       = "HTTPS to allow-listed third party"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "app_http_out" {
  count = local.standard ? 0 : 1

  security_group_id = aws_security_group.app.id
  description       = "HTTP for OS package mirrors on the low-cost host"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "app_to_db" {
  security_group_id            = aws_security_group.app.id
  description                  = "Postgres"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.db.id
}

resource "aws_vpc_security_group_egress_rule" "app_to_cache" {
  count = local.standard ? 1 : 0

  security_group_id            = aws_security_group.app.id
  description                  = "Redis"
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  referenced_security_group_id = aws_security_group.cache[0].id
}

# ---------------------------------------------------------------------------
# Data tier
# ---------------------------------------------------------------------------
resource "aws_security_group" "db" {
  #checkov:skip=CKV2_AWS_5:Attached by compute/database/cache/loadbalancer modules in the calling env; checkov can't see cross-module attachment.
  name        = "${var.name}-db"
  description = "Postgres; inbound only from the app tier"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-db" }
}

resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  description                  = "Postgres from app tier"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.app.id
}

# In low-cost mode Redis runs as a container on the host, so no cache SG.
resource "aws_security_group" "cache" {
  #checkov:skip=CKV2_AWS_5:Attached by compute/database/cache/loadbalancer modules in the calling env; checkov can't see cross-module attachment.
  count = local.standard ? 1 : 0

  name        = "${var.name}-cache"
  description = "Redis; inbound only from the app tier"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-cache" }
}

resource "aws_vpc_security_group_ingress_rule" "cache_from_app" {
  count = local.standard ? 1 : 0

  security_group_id            = aws_security_group.cache[0].id
  description                  = "Redis from app tier"
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  referenced_security_group_id = aws_security_group.app.id
}
