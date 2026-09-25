terraform {
  required_version = ">= 1.9.0"
}

# Renders the low-cost host templates with fixture values so they can be linted offline
# (shellcheck, `docker compose config`, `nginx -t`). No providers, no resources.
# Used by scripts/test-render.sh via `terraform console` (never apply).

variable "domain_name" {
  type    = string
  default = ""
}

locals {
  tpl = {
    app_name        = "slotwise"
    app_dir         = "/opt/slotwise"
    region          = "ap-south-1"
    ssm_path_prefix = "/slotwise/dev"
    image_repo      = "123456789012.dkr.ecr.ap-south-1.amazonaws.com/cil/slotwise"
    image_tag       = "abc1234"
    domain_name     = var.domain_name
    acme_email      = "ops@example.com"
    log_group       = "/slotwise/cil-dev/containers"
    api_command     = "uvicorn slotwise.main:app --host 0.0.0.0 --port 8000 --proxy-headers"
    worker_command  = "celery -A slotwise.worker.celery_app worker --pool threads --concurrency 4 -l info"
    beat_command    = "celery -A slotwise.worker.celery_app beat -l info --schedule /tmp/celerybeat-schedule"
    relay_command   = "python -m slotwise.outbox.relay"
    migrate_command = "alembic upgrade head"
  }
  dir = "../../modules/compute-ec2/files"

  files = {
    "docker-compose.yml" = templatefile("${local.dir}/docker-compose.yml.tftpl", local.tpl)
    "nginx.conf"         = templatefile("${local.dir}/nginx.conf.tftpl", local.tpl)
    "fetch-env.sh"       = templatefile("${local.dir}/fetch-env.sh.tftpl", local.tpl)
    "host-deploy.sh"     = templatefile("${local.dir}/host-deploy.sh.tftpl", local.tpl)
    "db-roles.sh"        = file("${local.dir}/db-roles.sh")
  }

  rendered = merge(local.files, {
    "cloud-init.yaml" = templatefile("${local.dir}/cloud-init.yaml.tftpl", merge(local.tpl, { files = local.files }))
  })
}

output "rendered" {
  description = "Rendered host files keyed by filename."
  value       = local.rendered
}
