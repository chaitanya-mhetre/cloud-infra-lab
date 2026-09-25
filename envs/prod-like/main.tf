# prod-like = what production would look like: Multi-AZ RDS, Redis failover, interface endpoints,
# deletion protection, longer backups. Expensive: apply for a few hours, record cost, destroy.
module "stack" {
  source = "../../modules/stack-standard"

  project                    = var.project
  env                        = "prod-like"
  cidr_block                 = "10.40.0.0/16"
  image_tag                  = var.image_tag
  domain_name                = var.domain_name
  route53_zone_id            = var.route53_zone_id
  github_owner               = var.github_owner
  enable_interface_endpoints = true
  disposable                 = false

  db = {
    instance_class        = "db.t4g.medium"
    multi_az              = true
    backup_retention_days = 7
    deletion_protection   = true
    skip_final_snapshot   = false
  }
  cache_node_type = "cache.t4g.small"
  cache_replicas  = 1

  api                = { cpu = 512, memory = 1024, desired = 3, min = 3, max = 10, target_cpu = 55 }
  worker             = { cpu = 512, memory = 1024, desired = 2, min = 2, max = 6 }
  log_retention_days = 30
}
