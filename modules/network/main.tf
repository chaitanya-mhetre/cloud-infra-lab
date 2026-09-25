data "aws_availability_zones" "available" {
  #checkov:skip=CKV_AWS_394:We slice to var.az_count, so a newly added AZ can't change which subnets exist.
  state = "available"
}

data "aws_region" "current" {}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # Deterministic subnet plan inside the /16:
  #   public  10.x.0.0/24,  10.x.1.0/24   (ALB, NAT, low-cost EC2)
  #   app     10.x.10.0/24, 10.x.11.0/24  (ECS tasks — no public IPs)
  #   data    10.x.20.0/24, 10.x.21.0/24  (RDS, ElastiCache — no route to the internet at all)
  public_cidrs = [for i in range(var.az_count) : cidrsubnet(var.cidr_block, 8, i)]
  app_cidrs    = [for i in range(var.az_count) : cidrsubnet(var.cidr_block, 8, 10 + i)]
  data_cidrs   = [for i in range(var.az_count) : cidrsubnet(var.cidr_block, 8, 20 + i)]

  interface_endpoints = var.enable_interface_endpoints ? toset([
    "ecr.api", "ecr.dkr", "ssm", "ssmmessages", "ec2messages", "logs",
  ]) : toset([])
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true # required for interface endpoints' private DNS

  tags = { Name = var.name }
}

# The VPC's default SG allows all traffic between members. Strip it so nothing
# accidentally lands in it with open rules (CIS 5.4).
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-default-locked" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = var.name }
}

# ---------------------------------------------------------------------------
# Subnets
# ---------------------------------------------------------------------------
resource "aws_subnet" "public" {
  count = var.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.public_cidrs[count.index]
  availability_zone = local.azs[count.index]
  # Instances get public IPs only when explicitly requested (the low-cost EC2 does).
  map_public_ip_on_launch = false

  tags = { Name = "${var.name}-public-${local.azs[count.index]}", Tier = "public" }
}

resource "aws_subnet" "app" {
  count = var.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.app_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = { Name = "${var.name}-app-${local.azs[count.index]}", Tier = "app" }
}

resource "aws_subnet" "data" {
  count = var.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.data_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = { Name = "${var.name}-data-${local.azs[count.index]}", Tier = "data" }
}

# ---------------------------------------------------------------------------
# Routing
# ---------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-public" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count          = var.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? 1 : 0
  domain = "vpc"
  tags   = { Name = "${var.name}-nat" }
}

# ONE NAT gateway, not one per AZ: a deliberate cost trade-off. If AZ-a fails,
# private subnets in AZ-b lose outbound internet (but not inbound traffic via the ALB).
resource "aws_nat_gateway" "this" {
  count         = var.enable_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id
  tags          = { Name = var.name }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "app" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-app" }
}

resource "aws_route" "app_nat" {
  count                  = var.enable_nat_gateway ? 1 : 0
  route_table_id         = aws_route_table.app.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[0].id
}

resource "aws_route_table_association" "app" {
  count          = var.az_count
  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.app.id
}

# Data subnets get a route table with only the implicit local route:
# databases can talk inside the VPC and nowhere else.
resource "aws_route_table" "data" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-data" }
}

resource "aws_route_table_association" "data" {
  count          = var.az_count
  subnet_id      = aws_subnet.data[count.index].id
  route_table_id = aws_route_table.data.id
}

# ---------------------------------------------------------------------------
# VPC endpoints
# ---------------------------------------------------------------------------
# Gateway endpoint for S3 is free and keeps S3 traffic (image layers, uploads) off the NAT.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.app.id, aws_route_table.public.id]
  tags              = { Name = "${var.name}-s3" }
}

resource "aws_security_group" "endpoints" {
  count = var.enable_interface_endpoints ? 1 : 0

  name        = "${var.name}-vpce"
  description = "HTTPS from inside the VPC to interface endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.cidr_block]
  }

  tags = { Name = "${var.name}-vpce" }
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoints

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.app[*].id
  security_group_ids  = [aws_security_group.endpoints[0].id]
  private_dns_enabled = true
  tags                = { Name = "${var.name}-${each.key}" }
}

# ---------------------------------------------------------------------------
# Flow logs (rejected traffic only — enough to debug SG problems, cheap to store)
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "flow" {
  #checkov:skip=CKV_AWS_338:REJECT-only flow logs for debugging SGs in a lab; 1-year retention is a compliance requirement we don't have. Retention is a variable.
  count = var.enable_flow_logs ? 1 : 0

  name              = "/vpc/${var.name}/flow-logs"
  retention_in_days = var.flow_logs_retention_days
  kms_key_id        = var.flow_logs_kms_key_arn
}

data "aws_iam_policy_document" "flow_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow" {
  count = var.enable_flow_logs ? 1 : 0

  name               = "${var.name}-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_assume.json
}

data "aws_iam_policy_document" "flow_write" {
  count = var.enable_flow_logs ? 1 : 0

  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.flow[0].arn}:*"]
  }
}

resource "aws_iam_role_policy" "flow" {
  count = var.enable_flow_logs ? 1 : 0

  name   = "write-flow-logs"
  role   = aws_iam_role.flow[0].id
  policy = data.aws_iam_policy_document.flow_write[0].json
}

resource "aws_flow_log" "this" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id          = aws_vpc.this.id
  traffic_type    = "REJECT"
  log_destination = aws_cloudwatch_log_group.flow[0].arn
  iam_role_arn    = aws_iam_role.flow[0].arn
}
