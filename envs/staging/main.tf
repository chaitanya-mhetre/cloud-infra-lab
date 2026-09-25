# staging = standard mode at minimum sizes. Torn down after each demo session.
module "stack" {
  source = "../../modules/stack-standard"

  project         = var.project
  env             = "staging"
  cidr_block      = "10.30.0.0/16"
  image_tag       = var.image_tag
  domain_name     = var.domain_name
  route53_zone_id = var.route53_zone_id
  github_owner    = var.github_owner
  alarm_email     = var.alarm_email
  disposable      = true

  db = {
    instance_class        = "db.t4g.micro"
    multi_az              = false
    backup_retention_days = 1
    deletion_protection   = false
    skip_final_snapshot   = true
  }
  cache_node_type = "cache.t4g.micro"
  cache_replicas  = 0

  api                = { cpu = 256, memory = 512, desired = 2, min = 2, max = 4, target_cpu = 60 }
  worker             = { cpu = 256, memory = 512, desired = 1, min = 1, max = 2 }
  log_retention_days = 7

  # Off by default to keep staging cheap. Flip to { enabled = true, mode = "count" } to try the rules.
  waf = { enabled = false }
}
