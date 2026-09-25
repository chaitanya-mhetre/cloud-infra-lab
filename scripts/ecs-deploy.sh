#!/usr/bin/env bash
# Standard-mode deploy on ECS Fargate.
#   scripts/ecs-deploy.sh <region> <cluster> <image_tag>
# 1. register new task-definition revisions (same config, new image tag)
# 2. run the migration task and require exit code 0   (expand/contract migrations only)
# 3. roll api/worker/beat; the deployment circuit breaker auto-rolls back if new tasks fail health checks
# 4. wait for services to be stable
set -euo pipefail
REGION="${1:?region}"; CLUSTER="${2:?cluster}"; TAG="${3:?image tag}"
aws_() { aws --region "$REGION" "$@"; }

register() { # family -> new revision ARN with the image tag swapped
  local family="$1" td
  td="$(aws_ ecs describe-task-definition --task-definition "$family" --query taskDefinition --output json)"
  echo "$td" | jq --arg tag "$TAG" '
      .containerDefinitions |= map(.image = (.image | sub(":[^:]+$"; ":" + $tag)))
      | {family, taskRoleArn, executionRoleArn, networkMode, containerDefinitions, volumes,
         requiresCompatibilities, cpu, memory, runtimePlatform}' > "/tmp/td-$family.json"
  aws_ ecs register-task-definition --cli-input-json "file:///tmp/td-$family.json" \
    --query taskDefinition.taskDefinitionArn --output text
}

echo "==> registering revisions for $TAG"
declare -A ARN
for svc in api worker beat migrate; do
  ARN[$svc]="$(register "$CLUSTER-$svc")"
  echo "    $svc -> ${ARN[$svc]##*/}"
done

echo "==> running migrations"
NET="$(aws_ ecs describe-services --cluster "$CLUSTER" --services api \
  --query 'services[0].networkConfiguration' --output json)"
TASK="$(aws_ ecs run-task --cluster "$CLUSTER" --launch-type FARGATE --task-definition "${ARN[migrate]}" \
  --network-configuration "$NET" --started-by "deploy-$TAG" --query 'tasks[0].taskArn' --output text)"
aws_ ecs wait tasks-stopped --cluster "$CLUSTER" --tasks "$TASK"
CODE="$(aws_ ecs describe-tasks --cluster "$CLUSTER" --tasks "$TASK" \
  --query 'tasks[0].containers[0].exitCode' --output text)"
if [ "$CODE" != 0 ]; then
  echo "✘ migration failed (exit $CODE) — services NOT updated. Logs: /slotwise/$CLUSTER stream migrate/*" >&2
  exit 1
fi

echo "==> rolling services"
for svc in api worker beat; do
  aws_ ecs update-service --cluster "$CLUSTER" --service "$svc" --task-definition "${ARN[$svc]}" \
    --query 'service.deployments[0].status' --output text >/dev/null
done

echo "==> waiting for steady state (circuit breaker rolls back automatically on failure)"
aws_ ecs wait services-stable --cluster "$CLUSTER" --services api worker beat

# If the circuit breaker fired, the service is "stable" but on the OLD revision.
RUNNING="$(aws_ ecs describe-services --cluster "$CLUSTER" --services api \
  --query 'services[0].taskDefinition' --output text)"
if [ "$RUNNING" != "${ARN[api]}" ]; then
  echo "✘ api rolled back by the deployment circuit breaker (running ${RUNNING##*/})" >&2
  exit 1
fi
echo "✔ $TAG live on $CLUSTER"
