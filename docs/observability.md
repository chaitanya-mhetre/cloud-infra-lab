# Observability

## Signals
| Signal | Where | Notes |
|---|---|---|
| Logs | CloudWatch `/slotwise/<env>` (ECS) or `/slotwise/<env>/containers` (dev, awslogs driver) | JSON logs from the app; retention 3–30 days |
| Metrics (infra) | CloudWatch: ALB, ECS, RDS, ElastiCache, EC2 | free/basic metrics; Container Insights optional (costs extra) |
| Metrics (app) | `/metrics` (Prometheus format) on each app | blocked at nginx/ALB/ingress; scraped in-cluster by kube-prometheus-stack via the chart's ServiceMonitor |
| Traces | the apps emit OpenTelemetry (production-fastapi) | collector/X-Ray wiring on AWS: **not done** (gap) |

## Alarms (`modules/observability`): symptom first
| Alarm | Why it matters |
|---|---|
| 5xx **rate** > 2% (metric math, ignores < 20 req/min) | users are failing; a rate, not a count, so it scales with traffic |
| p95 latency > 1.5 s | users are waiting |
| unhealthy targets > 0 for 3 min | a task keeps failing `/readyz` |
| API CPU > 85%, API/worker memory > 85% | saturation: autoscaling at max, or OOM coming |
| RDS CPU > 80%, free storage < 2 GiB | the database is the usual bottleneck |
| Redis memory > 75% | with `noeviction` a full broker **rejects new jobs** |
| App error log lines > 20 / 5 min | a metric filter on `{ $.level = "error" }` |
| EC2 system status check (dev) | **auto-recovers** the instance onto healthy hardware |

All alarms publish to an SNS topic (with optional email). A CloudWatch dashboard is generated, containing only widgets whose inputs exist
(a bug where mixed-type conditionals broke the dev plan was caught by `modules/observability/tests`).

## Gaps (honest)
- No ALB access logs (needs a log bucket with an ELB bucket policy).
- No distributed tracing backend on AWS (the app side exists; the collector doesn't).
- Thresholds are starting points. Tune them from real traffic.
- "Alarm triggered deliberately and notification received" (M5 acceptance): **TBD**. Needs an AWS session.
