locals {
  tls = var.domain_name != ""
}

resource "aws_lb" "this" {
  #checkov:skip=CKV_AWS_91:ALB access logs need a log bucket with a regional ELB principal policy; deferred (docs/observability.md).
  #checkov:skip=CKV_AWS_150:Deletion protection is a variable: off for disposable envs.
  #checkov:skip=CKV2_AWS_28:No WAF in the lab (cost); rate limiting is done in the app. Listed in docs/security.md.
  #checkov:skip=CKV2_AWS_20:HTTP listener only redirects to HTTPS when a domain is configured; HTTP-only mode is demo-only.
  name                       = substr(var.name, 0, 32)
  load_balancer_type         = "application"
  internal                   = false
  subnets                    = var.public_subnet_ids
  security_groups            = var.security_group_ids
  idle_timeout               = var.idle_timeout
  drop_invalid_header_fields = true # blocks request-smuggling style malformed headers
  enable_deletion_protection = var.deletion_protection
}

resource "aws_lb_target_group" "api" {
  #checkov:skip=CKV_AWS_378:TLS terminates at the ALB; ALB->task traffic stays inside private subnets on the app SG.
  name        = substr("${var.name}-api", 0, 32)
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # Fargate tasks register by IP

  # Give in-flight requests 30 s to finish before a task is removed (rolling deploys).
  deregistration_delay = 30

  health_check {
    path                = var.health_check_path
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# ---------------------------------------------------------------------------
# TLS (optional): ACM cert with DNS validation + alias record
# ---------------------------------------------------------------------------
resource "aws_acm_certificate" "this" {
  count             = local.tls ? 1 : 0
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "validation" {
  for_each = local.tls ? {
    for o in aws_acm_certificate.this[0].domain_validation_options : o.domain_name => o
  } : {}

  zone_id = var.route53_zone_id
  name    = each.value.resource_record_name
  type    = each.value.resource_record_type
  records = [each.value.resource_record_value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "this" {
  count                   = local.tls ? 1 : 0
  certificate_arn         = aws_acm_certificate.this[0].arn
  validation_record_fqdns = [for r in aws_route53_record.validation : r.fqdn]
}

resource "aws_route53_record" "alias" {
  count   = local.tls ? 1 : 0
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}

# ---------------------------------------------------------------------------
# Listeners
# ---------------------------------------------------------------------------
resource "aws_lb_listener" "https" {
  count             = local.tls ? 1 : 0
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.this[0].certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}

resource "aws_lb_listener" "http" {
  #checkov:skip=CKV_AWS_2:Port 80 redirects to HTTPS when TLS is configured; plain HTTP only in domain-less demo mode.
  #checkov:skip=CKV_AWS_103:TLS policy applies to the HTTPS listener; this one only redirects.
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = local.tls ? "redirect" : "forward"
    target_group_arn = local.tls ? null : aws_lb_target_group.api.arn

    dynamic "redirect" {
      for_each = local.tls ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }
}

# Never expose Prometheus metrics publicly.
resource "aws_lb_listener_rule" "block_metrics" {
  listener_arn = local.tls ? aws_lb_listener.https[0].arn : aws_lb_listener.http.arn
  priority     = 10

  condition {
    path_pattern {
      values = ["/metrics", "/metrics/*"]
    }
  }

  action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "not found"
      status_code  = "404"
    }
  }
}
