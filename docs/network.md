# Network architecture

## Standard mode (staging, prod-like): `modules/network` + `modules/security`
```
                         Internet
                            │
                ┌───────────▼────────────┐  public subnets 10.x.0.0/24, 10.x.1.0/24 (2 AZs)
                │  ALB  (SG: alb)        │  route: 0.0.0.0/0 → Internet Gateway
                │  NAT gateway (AZ-a)    │
                └───────────┬────────────┘
                            │ :8000 (SG alb → SG app)
                ┌───────────▼────────────┐  app subnets 10.x.10.0/24, 10.x.11.0/24
                │ ECS Fargate tasks      │  route: 0.0.0.0/0 → NAT (outbound only)
                │ api·worker·beat·relay  │  no public IPs
                └──────┬──────────┬──────┘
          :5432 (app→db)│          │:6379 (app→cache)
                ┌───────▼───┐  ┌───▼────────┐  data subnets 10.x.20.0/24, 10.x.21.0/24
                │ RDS PG 16 │  │ ElastiCache│  route table: local only — NO internet path at all
                └───────────┘  └────────────┘
   S3 gateway endpoint (free) on public + app route tables · interface endpoints (ECR/SSM/Logs) in prod-like
```

| Tier | CIDR (per env /16) | Route to internet | What lives there |
|---|---|---|---|
| public | `.0.0/24`, `.1.0/24` | IGW (in + out) | ALB, NAT gateway, low-cost EC2 host |
| app | `.10.0/24`, `.11.0/24` | NAT (out only), or none | ECS tasks |
| data | `.20.0/24`, `.21.0/24` | **none** | RDS, ElastiCache |

Env CIDRs don't overlap (dev 10.20, staging 10.30, prod-like 10.40), so the VPCs can be peered or joined
through a Transit Gateway later without renumbering.

## Why each piece exists
- **Two AZs.** ALB and RDS subnet groups require them, and one AZ failing shouldn't take the service down.
- **Three tiers.** The blast radius shrinks at each layer: the internet can only reach the ALB, the ALB can only reach app tasks on
  one port, and only app tasks can reach the databases. SGs reference **SGs, not CIDRs**, so rules survive task IPs changing.
- **Data subnets with no route out.** Even a compromised database can't send data out to the internet.
- **A single NAT gateway.** A cost trade-off (see cost.md). If AZ-a fails, tasks in AZ-b lose *outbound* internet,
  but inbound traffic through the ALB keeps working. prod-like adds interface endpoints, so pulling images, reading secrets and shipping logs
  don't depend on the NAT.
- **S3 gateway endpoint.** Free. Keeps ECR layer downloads and uploads traffic off the NAT (which is billed per GB).
- **Locked default SG.** `aws_default_security_group` with no rules, so nothing lands in an allow-all group by accident.
- **Flow logs (REJECT only).** Cheap, and exactly what you need to debug "why can't X reach Y": a rejected packet means an SG or NACL problem.

## Low-cost mode (dev)
```
Internet ──80/443──▶ EC2 t4g.small (public subnet, Elastic IP, SG app: 80/443 only, no 22)
                      docker compose: nginx → api, worker, beat, relay, postgres, redis
```
No NAT, no ALB, no interface endpoints. Admin access goes through **SSM Session Manager** (IAM-authenticated, audited).
Port 22 is closed and no SSH key exists.

## Verified by tests
`modules/network/tests/network.tftest.hcl` (mocked provider) asserts: 2 subnets per tier spread across AZs, the exact
CIDR plan, no auto-assigned public IPs anywhere, NAT/endpoints off by default and exactly 1 NAT when on, and that 1 AZ is rejected.
`modules/security/tests/security.tftest.hcl` asserts that the app tier isn't internet-reachable in standard mode and that port 22 never appears.
