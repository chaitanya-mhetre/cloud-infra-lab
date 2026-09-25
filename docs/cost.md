# Cost

> **Every number on this page is an ESTIMATE, not a bill.** Sources are AWS public on-demand list prices for
> ap-south-1 as I understood them when writing. Source: AWS Pricing Calculator / pricing pages, **checked on: TBD — verify before relying on it**.
> Actual spend per session goes in the log at the bottom, taken from Cost Explorer.

## What drives cost in a small AWS setup (ranked)
1. **NAT gateway.** Hourly charge plus per-GB processing, and it runs 24/7 whether or not there's traffic. Usually the biggest fixed line.
2. **ALB.** Hourly charge plus LCUs.
3. **RDS.** Instance-hours (Multi-AZ doubles it) plus storage.
4. **Interface VPC endpoints.** Per endpoint, per AZ, per hour. Six endpoints × 2 AZs adds up fast.
5. **Fargate.** vCPU-hours + GB-hours; Spot is much cheaper for workers.
6. **ElastiCache.** Node-hours.
7. CloudWatch logs and metrics, ECR storage, S3, Elastic IPs (public IPv4 addresses are billed hourly).

## Estimated monthly cost *if left running 24/7* (don't do this)
| Env | Main components | Rough estimate (USD/month) |
|---|---|---|
| dev (low-cost) | 1× t4g.small, 20 GB gp3, Elastic IP, logs | **~15–25** (estimate) |
| staging | NAT, ALB, 2× 0.25 vCPU API + worker + beat + relay on Fargate/Spot, db.t4g.micro, cache.t4g.micro | **~110–160** (estimate) |
| prod-like | + Multi-AZ db.t4g.medium, Redis replica, 6 interface endpoints × 2 AZ, bigger tasks | **~350–500** (estimate) |

For precise numbers, run `make cost ENV=staging` (infracost; needs an infracost API key) and paste the output here with the date.

## How this repo keeps the bill near zero
- dev = one small instance, **no NAT, no ALB**; `nightly-destroy-dev.yml` tears it down every night.
- staging/prod-like are **applied for a demo session and destroyed** the same day (`make destroy`).
- `scripts/cost-check.sh` fails if anything tagged for the env remains, plus unattached EIPs, NAT gateways and detached volumes.
- An AWS Budget (`envs/shared`) emails at 50% and 80% of actual spend and when the month is **forecast** to exceed the budget.
- ECR lifecycle keeps the last 15 images. Log retention is 3–30 days. S3 expires old versions.
- Graviton (arm64) everywhere and FARGATE_SPOT for workers.

## Session log (ACTUAL spend, from Cost Explorer)
| Date | Env | Duration | What was done | Actual cost |
|---|---|---|---|---|
| — | — | — | nothing applied yet | $0 |
