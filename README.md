# cloud-infra-lab

Terraform-managed AWS infrastructure (VPC, ECS Fargate, RDS, ElastiCache, S3, ALB, IAM, CloudWatch), keyless GitHub Actions CI/CD,
and a Kubernetes/Helm track. It deploys [`production-fastapi`](../production-fastapi) (Slotwise) and [`rag-engine`](../rag-engine),
with a low-cost mode and one-command teardown.

> **Status:** M1–M7 implemented. **Validated offline only**: `terraform validate` + `terraform test` (mocked provider), tflint,
> checkov, rendered-template linting, helm lint/kubeconform. **Nothing has been applied to a real AWS account yet**, so there are
> no AWS cost or latency numbers here. The Kubernetes track was run **live on a local kind cluster** (numbers below).

## Problem
Most of my cloud experience was operational (one VM, Docker Compose, clicking in consoles). Platform roles expect reproducible
infrastructure-as-code, sound networking and IAM, CI/CD without long-lived keys, observability, Kubernetes, and cost discipline.

## Why it exists
To build that properly and cheaply, so I can explain every subnet, security group, IAM condition, and deploy step.

## Architecture
```
                 standard mode (staging / prod-like)                         low-cost mode (dev)
 Internet ─▶ ALB (public, 2 AZ, TLS) ─▶ ECS Fargate arm64 (private)       Internet ─▶ EC2 t4g.small (public, EIP)
                                        api · worker · beat · relay                    nginx + compose:
                                            │            │                             api·worker·beat·relay
                                   RDS Postgres 16   ElastiCache Redis                 postgres·redis
                                   (isolated subnets, no internet route)          SSM Session Manager, no SSH
 NAT (single) · S3 gateway endpoint · interface endpoints (prod-like) · SSM params · ECR (immutable) · CloudWatch alarms
 GitHub Actions ──OIDC──▶ plan (PRs, read-only) · apply (reviewed env) · deploy (app repo main only)
```
Details: [docs/network.md](docs/network.md) · [docs/iam.md](docs/iam.md) · [docs/secrets.md](docs/secrets.md)

## Features
- **Modules:** `network`, `security`, `iam`, `secrets`, `registry`, `storage`, `database`, `cache`, `loadbalancer`, `compute-ec2`,
  `compute-ecs`, `observability`, composed by `stack-standard`
- **Environments:** `shared` (ECR, PR plan role, budget), `dev` (low-cost), `staging`, `prod-like` (Multi-AZ, failover, endpoints)
- **Remote state:** S3 (versioned, KMS, TLS-only) + DynamoDB lock, bootstrapped by `bootstrap/`
- **Keyless CI/CD:** GitHub OIDC roles with exact-subject trust; PR plan comments; reviewer-gated apply of the exact plan;
  nightly dev destroy; weekly drift detection
- **Deploys:** immutable SHA tags, migration gate before rollout, ECS circuit-breaker rollback, host-level auto-rollback in dev
- **Observability:** symptom-first alarms (5xx rate, p95), saturation alarms, log error metric, EC2 auto-recover, dashboard, budget
- **Kubernetes:** Helm charts for both apps (probes, HPA, PDB, NetworkPolicy, migration hooks, ServiceMonitor), kind cluster, load test

## Tech stack
Terraform 1.9 (AWS provider 5.x) · AWS (VPC, ECS Fargate, RDS, ElastiCache, ALB, ACM, Route53, S3, ECR, SSM, IAM, CloudWatch, SNS, Budgets)
· GitHub Actions · Docker · Helm 3 · kind · ingress-nginx · metrics-server · tflint · checkov · gitleaks · shellcheck · kubeconform

## Quick start (offline, no AWS account needed)
```bash
make check        # fmt, validate, terraform test, tflint, checkov, template render tests, helm lint/kubeconform/checkov
make help         # all targets
```
Only Docker and make are required: every tool runs from a pinned image via `scripts/tools.sh`.

Kubernetes track (needs ~3 GB free RAM):
```bash
make k8s-up                              # kind + ingress-nginx + metrics-server + throwaway Postgres/Redis
scripts/k8s.sh deploy rag-engine         # build image, kind load, helm install (migration hook runs first)
curl -H 'Host: rag.localtest.me' http://127.0.0.1:58080/v1/ready
make k8s-down
```

## Usage against AWS
See [docs/runbook.md](docs/runbook.md). In short:
```bash
make bootstrap                               # once per account
make plan ENV=dev && make apply ENV=dev      # low-cost env
make deploy ENV=dev IMAGE_TAG=<sha>          # or let the app pipeline do it
make destroy ENV=dev                         # always, after the session
```

## Testing
| Layer | Tool | Where |
|---|---|---|
| Syntax/types | `terraform fmt`, `validate` (every module and env) | `make validate` |
| Unit tests | `terraform test` + `mock_provider` (network, security, observability) | `modules/*/tests/` |
| Lint | tflint (recommended + AWS ruleset) | `.tflint.hcl` |
| Security | checkov (Terraform, GitHub Actions, rendered K8s), gitleaks | inline skips carry reasons |
| Templates | render cloud-init/compose/nginx/scripts → shellcheck, `docker compose config`, `nginx -t` | `scripts/test-render.sh` |
| Helm | lint --strict, kubeconform, checkov | `make helm-check` |
| Live | kind: install, probes, `/metrics` blocked, HPA scale-up, rolling restart under load | `docs/measurements/` |
| Post-deploy | `scripts/smoke.sh` | run by every deploy |

## Deployment
This repo **is** the deployment layer. App pipeline template: [`ci-templates/app-deploy.yml`](ci-templates/app-deploy.yml).
Rollback strategy: [docs/rollback.md](docs/rollback.md).

## Security
IMDSv2, no SSH, SG-to-SG tiers, isolated data subnets, encryption at rest and in transit, keyless OIDC, least-privilege roles
(including an RLS-enforced DB role), immutable scanned images, non-root read-only containers. Accepted findings and known gaps:
[docs/security.md](docs/security.md).

## Performance (measured values only)
Kind cluster on a laptop (i5-1240P), rag-engine chart, 2026-09-25 ([details](docs/measurements/2026-09-25-kind-hpa-rollout.md)):
- HPA: load start → scale decision **~31 s** → 4 ready pods **~42 s** (1→4 replicas, 50% CPU target)
- Rolling restart of 4 API pods under load: **11,974 / 11,974 requests HTTP 200 (0 errors)**
- AWS numbers (deploy duration, ECS scale-up, failed requests during a deploy): **TBD**. They need an AWS session.

## Cost
Estimates only (no AWS bill yet): [docs/cost.md](docs/cost.md). Dev ≈ one small instance with nightly teardown; staging/prod-like
are applied per demo session and destroyed. `scripts/cost-check.sh` fails if billable leftovers remain.

## Engineering trade-offs
- **ECS Fargate over EKS** for AWS envs (no control-plane cost). Kubernetes skills are practised on kind ([docs/ecs-vs-eks.md](docs/ecs-vs-eks.md)).
- **Single NAT gateway**: cost vs AZ-independent egress.
- **Composition module instead of Terragrunt**: fewer tools, same DRYness for three envs.
- **Placeholder secrets with `ignore_changes`**: secrets stay out of state, at the cost of a manual bootstrap step.
- **Broad apply role** (PowerUser + prefixed IAM), gated by environment reviewers. A permissions boundary is the upgrade.
- **No CPU limits in Kubernetes**, to avoid CFS throttling. Memory limits kept.

## Limitations
- Not yet applied to AWS; the AWS-side acceptance criteria (HTTPS smoke, alarm delivery, zero-downtime ECS deploy under k6) are open.
- slotwise chart validated offline only (the live kind run covered rag-engine, because of laptop RAM).
- rag-engine stores uploads on local disk, so multi-node Kubernetes needs RWX storage or moving uploads to S3.
- No WAF, egress filtering, ALB access logs, tracing backend, or permissions boundary (see docs/security.md).

## Roadmap
1. First real AWS session: dev → smoke → destroy, record actual cost
2. staging apply + k6 rolling-deploy test + deliberate alarm
3. Optional short EKS run (`envs/eks-demo`) with cost recorded before/after
4. Permissions boundary, WAF, ALB access logs, OTel collector → X-Ray/Tempo

## Contributing
See [CONTRIBUTING.md](CONTRIBUTING.md). Learning notes: [docs/LEARNING_GUIDE.md](docs/LEARNING_GUIDE.md).
