data "aws_region" "current" {}

resource "aws_ecs_cluster" "this" {
  #checkov:skip=CKV_AWS_65:Container Insights is a variable (off by default: extra CloudWatch cost); service metrics come from default ECS metrics + app /metrics.
  name = var.name

  setting {
    name  = "containerInsights"
    value = var.container_insights ? "enabled" : "disabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

resource "aws_cloudwatch_log_group" "app" {
  #checkov:skip=CKV_AWS_338:Retention is a variable (14 d staging); 1-year is a compliance need we don't have.
  #checkov:skip=CKV_AWS_158:CloudWatch default encryption; CMK adds cost.
  name              = "/slotwise/${var.name}"
  retention_in_days = var.log_retention_days
}

locals {
  secrets = [for k, arn in var.secret_arns : { name = "SLOTWISE_${k}", valueFrom = arn }]
  env     = [for k, v in var.environment : { name = k, value = v }]

  container = { for role, cmd in var.commands : role => {
    name                   = role
    image                  = "${var.image_repo}:${var.image_tag}"
    command                = cmd
    essential              = true
    readonlyRootFilesystem = true
    user                   = "10001" # the app image runs as non-root; enforce it here too
    secrets                = local.secrets
    environment            = local.env
    portMappings           = role == "api" ? [{ containerPort = var.app_port, protocol = "tcp" }] : []
    mountPoints            = [{ sourceVolume = "tmp", containerPath = "/tmp" }]
    linuxParameters        = { initProcessEnabled = true } # PID 1 reaps zombies, forwards SIGTERM
    stopTimeout            = role == "worker" ? 120 : 30   # let Celery finish the current task
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.app.name
        awslogs-region        = data.aws_region.current.name
        awslogs-stream-prefix = role
      }
    }
  } }

  sizing = {
    api     = { cpu = var.api.cpu, memory = var.api.memory }
    worker  = { cpu = var.worker.cpu, memory = var.worker.memory }
    beat    = { cpu = 256, memory = 512 }
    relay   = { cpu = 256, memory = 512 }
    migrate = { cpu = 256, memory = 512 }
  }
}

resource "aws_ecs_task_definition" "this" {
  for_each = var.commands

  family                   = "${var.name}-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = local.sizing[each.key].cpu
  memory                   = local.sizing[each.key].memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn
  container_definitions    = jsonencode([local.container[each.key]])

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64" # Graviton: cheaper per vCPU; image built for arm64 in CI
  }

  volume {
    name = "tmp" # writable scratch despite the read-only root filesystem
  }
}

# ---------------------------------------------------------------------------
# Services
# ---------------------------------------------------------------------------
resource "aws_ecs_service" "api" {
  name                   = "api"
  cluster                = aws_ecs_cluster.this.id
  task_definition        = aws_ecs_task_definition.this["api"].arn
  desired_count          = var.api.desired
  launch_type            = "FARGATE"
  enable_execute_command = true
  propagate_tags         = "SERVICE"

  # Rolling deploy: start new tasks first (200%), never drop below full capacity (100%).
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 30

  # If new tasks keep failing health checks, ECS stops the deploy and returns to the last good revision.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.app_subnet_ids
    security_groups  = var.app_security_group_ids
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = "api"
    container_port   = var.app_port
  }

  lifecycle {
    # Deploys (scripts/ecs-deploy.sh) register new revisions; autoscaling moves desired_count.
    ignore_changes = [task_definition, desired_count]
  }
}

resource "aws_ecs_service" "worker" {
  name                   = "worker"
  cluster                = aws_ecs_cluster.this.id
  task_definition        = aws_ecs_task_definition.this["worker"].arn
  desired_count          = var.worker.desired
  enable_execute_command = true
  propagate_tags         = "SERVICE"

  capacity_provider_strategy {
    capacity_provider = var.use_spot_for_workers ? "FARGATE_SPOT" : "FARGATE"
    weight            = 1
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.app_subnet_ids
    security_groups  = var.app_security_group_ids
    assign_public_ip = false
  }

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }
}

# Beat must NEVER run twice (duplicate scheduled jobs), so deploys stop the old task
# before starting the new one: min 0% / max 100%.
resource "aws_ecs_service" "beat" {
  name                   = "beat"
  cluster                = aws_ecs_cluster.this.id
  task_definition        = aws_ecs_task_definition.this["beat"].arn
  desired_count          = 1
  enable_execute_command = true
  propagate_tags         = "SERVICE"

  capacity_provider_strategy {
    capacity_provider = var.use_spot_for_workers ? "FARGATE_SPOT" : "FARGATE"
    weight            = 1
  }

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  network_configuration {
    subnets          = var.app_subnet_ids
    security_groups  = var.app_security_group_ids
    assign_public_ip = false
  }

  lifecycle {
    ignore_changes = [task_definition]
  }
}

# Outbox relay: polls committed outbox rows and publishes them. One instance is enough;
# rows are claimed with SELECT ... FOR UPDATE SKIP LOCKED, so a brief overlap during deploys is safe.
resource "aws_ecs_service" "relay" {
  name                   = "relay"
  cluster                = aws_ecs_cluster.this.id
  task_definition        = aws_ecs_task_definition.this["relay"].arn
  desired_count          = 1
  enable_execute_command = true
  propagate_tags         = "SERVICE"

  capacity_provider_strategy {
    capacity_provider = var.use_spot_for_workers ? "FARGATE_SPOT" : "FARGATE"
    weight            = 1
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.app_subnet_ids
    security_groups  = var.app_security_group_ids
    assign_public_ip = false
  }

  lifecycle {
    ignore_changes = [task_definition]
  }
}

# ---------------------------------------------------------------------------
# Autoscaling (target tracking)
# ---------------------------------------------------------------------------
resource "aws_appautoscaling_target" "api" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.api.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.api.min
  max_capacity       = var.api.max
}

resource "aws_appautoscaling_policy" "api_cpu" {
  name               = "${var.name}-api-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.api.service_namespace
  resource_id        = aws_appautoscaling_target.api.resource_id
  scalable_dimension = aws_appautoscaling_target.api.scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value       = var.api.target_cpu
    scale_in_cooldown  = 300 # scale in slowly
    scale_out_cooldown = 60  # scale out fast
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

resource "aws_appautoscaling_target" "worker" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.worker.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.worker.min
  max_capacity       = var.worker.max
}

resource "aws_appautoscaling_policy" "worker_cpu" {
  name               = "${var.name}-worker-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.worker.service_namespace
  resource_id        = aws_appautoscaling_target.worker.resource_id
  scalable_dimension = aws_appautoscaling_target.worker.scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value       = 70
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}
