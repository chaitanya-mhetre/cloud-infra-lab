# Changelog

All notable changes. Versions follow milestones; dates are commit dates.

## [0.1.0] - 2026-09-25
### M7: docs + hardening
- Network, IAM, secrets, scaling, rollback, cost (estimates), observability, security, runbook, ECS-vs-EKS docs; learning guide.
- Toolbox Dockerfile, `scripts/local-tools.sh`, examples, LICENSE/CONTRIBUTING.

### M6: Kubernetes track
- Helm charts for slotwise (api/worker/beat/relay) and rag-engine (api/worker): probes, HPA, PDB, NetworkPolicy,
  migration hooks, ServiceMonitor, `/metrics` blackhole route.
- kind cluster + throwaway deps + `scripts/k8s.sh`; measured HPA scale-up and a zero-error rolling restart on kind.
- Least-privilege Postgres role bootstrap (`db-roles.sh`), verified against a real Postgres container.

### M5: observability
- Symptom-first CloudWatch alarms (5xx rate via metric math, p95), saturation alarms, log error metric filter,
  EC2 auto-recover, generated dashboard, account budget with forecast alert.

### M4: standard mode
- storage, database (RDS-managed master secret), cache (noeviction), loadbalancer (ACM/Route53, HTTPS redirect),
  compute-ecs (Fargate arm64, circuit breaker, Spot workers, singleton beat, relay, autoscaling), ECS IAM roles.
- `stack-standard` composition; staging and prod-like envs; `ecs-deploy.sh` with migration gate.
- Offline `terraform test` suites with a mocked AWS provider.

### M3: CI/CD
- GitHub OIDC plan/apply/deploy roles (exact-subject trust); infra CI, PR plan comments, gated apply, nightly dev destroy,
  drift detection; app pipeline template.

### M2: low-cost deploy
- registry (immutable ECR), secrets (out-of-band values), EC2 instance profile, compute-ec2 host (cloud-init, compose, nginx/TLS,
  auto-rollback deploy), operator scripts, offline template render tests.

### M1: bootstrap + network
- State bucket + lock table + OIDC provider; network and security modules; dev env; dockerized `make check`.
