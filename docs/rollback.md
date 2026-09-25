# Deploys and rollback

## The rules that make rollback safe
1. **Immutable image tags.** An ECR tag is a git SHA and can never be overwritten (`IMMUTABLE`), so "roll back to abc123"
   always means the same bytes.
2. **Expand/contract migrations.** Every migration must work with **both** the old and the new code:
   - *expand:* add the nullable column or new table, and deploy code that writes both shapes;
   - *migrate:* backfill;
   - *contract:* drop the old column in a **later** release, once nothing reads it.
   So rolling back the **code** never needs a schema rollback. **Never down-migrate during an incident.**
3. **Migrate before rollout.** A failed migration stops the deploy while the old version is still serving.

## Standard mode (ECS): `scripts/ecs-deploy.sh`
```
register new task-def revisions (image → :<sha>)
  → run migrate task, require exit 0 ──✘──▶ stop: services untouched
  → update-service api/worker/beat/relay (api: min 100% / max 200%: new tasks start before old ones stop)
  → ALB health checks /readyz on new tasks; ECS deployment circuit breaker watches
       └─ repeated failures ─▶ ECS rolls back to the previous revision automatically
  → wait services-stable; if api ended on the OLD revision, report "rolled back" and exit 1
```
Manual rollback: `make rollback ENV=staging TO=<previous sha>`. It's the same path as a deploy, with an old, known-good tag.

Why **beat** uses min 0% / max 100%: two Celery beat schedulers would enqueue every periodic job twice.

## Low-cost mode (EC2): `host-deploy.sh` on the host
```
pull :<sha> → start postgres/redis → run migrate → compose up api worker beat relay nginx
  → poll /readyz for 60 s ──✔──▶ record .current_tag (old one → .previous_tag)
                           ──✘──▶ automatic `compose up` with the previous tag, exit 1
```
Manual rollback: `make rollback ENV=dev`, which swaps back to `.previous_tag`.

## Kubernetes (kind / EKS)
The Helm `pre-upgrade` hook runs the migration Job. If it fails, the Helm upgrade fails and the old ReplicaSet keeps serving.
`maxUnavailable: 0` and readiness gating mean no capacity is lost during a rollout. Roll back with `helm rollback <release> <revision>`.
Measured on kind: a rolling restart of 4 API pods under load returned **11,974/11,974 HTTP 200**
(docs/measurements/2026-09-25-kind-hpa-rollout.md).
