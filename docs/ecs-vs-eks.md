# ECS vs EKS: why standard mode uses ECS Fargate

| | ECS Fargate | EKS |
|---|---|---|
| Control plane cost | none | hourly per cluster (always on) |
| Nodes | none to manage | managed node groups / Karpenter / Fargate profiles |
| Learning curve | small: task definitions + services | large: the Kubernetes API, controllers, add-ons |
| Portability | AWS-only | same manifests/Helm run anywhere (kind locally, GKE, AKS) |
| Ecosystem | AWS-native integrations | huge: operators, KEDA, service mesh, GitOps (Argo CD) |
| Deploy safety | circuit breaker + rollback built in | rollout strategies, PDBs, readiness gates, Argo Rollouts |
| Good fit | small teams, a few services, AWS-committed | many services/teams, platform team, multi-cloud or on-prem needs |

**Decision for this lab:** ECS Fargate for the AWS environments (no idle control-plane cost, fewer moving parts),
and **Kubernetes on kind** for the portable skills (Helm, HPA, PDB, probes, NetworkPolicy). An EKS run is optional, only if the budget allows:
apply, record the cost, destroy.

What stays the same across both: immutable images, readiness vs liveness, rolling deploys with surge, migrations as a
separate one-off step, secrets injected at runtime, and autoscaling on a target metric.
