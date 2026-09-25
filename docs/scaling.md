# Scaling

| Component | How it scales | Limit / next step |
|---|---|---|
| API (ECS) | target-tracking on CPU (staging 60%, prod-like 55%), 2→4 / 3→10 tasks; scale out after 60 s, in after 300 s | add ALB `RequestCountPerTarget` tracking for spiky I/O-bound load |
| Worker (ECS) | CPU target 70%, on FARGATE_SPOT | queue-depth scaling (custom metric from Redis `LLEN`) is the better signal: CPU lies for I/O-bound tasks |
| Beat | exactly 1, by design | — |
| Relay | 1; rows are claimed with `FOR UPDATE SKIP LOCKED`, so a second instance is safe if lag grows | alarm on outbox lag |
| RDS | vertical (instance class), storage autoscaling up to `max_allocated_storage` | read replica for reporting; PgBouncer/RDS Proxy once connections (tasks × pool size) near the max |
| Redis | vertical node type; `replicas ≥ 1` for failover | Redis is broker + cache, not a system of record: losing it loses queued jobs not yet started. The outbox pattern means events can be re-published from Postgres |
| API (k8s) | HPA on CPU, fast up / slow down (`behavior`), PDB `minAvailable: 1` | KEDA for queue-based worker scaling |

## Connection math (a real scaling limit)
Each API task opens a SQLAlchemy pool (say 10). 10 tasks × 10 = 100 connections, plus workers. `db.t4g.micro` allows
roughly 80–100 (`max_connections` depends on memory; check `SHOW max_connections`). So **scaling the API can take the DB down.**
Fix: a smaller pool per task, RDS Proxy, or PgBouncer. This comes up in interviews.

## What was actually measured
Only the kind HPA test (docs/measurements/2026-09-25-kind-hpa-rollout.md): load start → 4 ready pods in ~42 s on a laptop.
ECS autoscaling timings on AWS: **TBD** (needs an AWS session and a k6 run).
