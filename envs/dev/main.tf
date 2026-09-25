# dev = LOW-COST mode: one public EC2 host running Docker Compose.
# No NAT gateway, no ALB, no interface endpoints (these dominate small-setup cost).

locals {
  env  = "dev"
  name = "${var.project}-${local.env}"
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
