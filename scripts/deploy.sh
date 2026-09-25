#!/usr/bin/env bash
# Deploy an image tag (git SHA) to an environment.
#   scripts/deploy.sh dev <sha>        low-cost host via SSM Run Command
#   scripts/deploy.sh staging <sha>    ECS: migrate task, then rolling service update
set -euo pipefail
ENV="${1:?usage: deploy.sh <env> <image_tag>}"
TAG="${2:?usage: deploy.sh <env> <image_tag>}"
REGION="${AWS_REGION:-ap-south-1}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tf_out() { (cd "$ROOT/envs/$ENV" && terraform output -raw "$1"); }

if [ "$ENV" = dev ]; then
  INSTANCE="$(tf_out instance_id)"
  echo "==> deploying $TAG to $INSTANCE via SSM"
  CMD_ID="$(aws ssm send-command --region "$REGION" --instance-ids "$INSTANCE" \
    --document-name AWS-RunShellScript --comment "deploy $TAG" \
    --parameters "commands=[\"/opt/slotwise/host-deploy.sh $TAG\"]" \
    --query Command.CommandId --output text)"
  aws ssm wait command-executed --region "$REGION" --command-id "$CMD_ID" --instance-id "$INSTANCE" || true
  STATUS="$(aws ssm get-command-invocation --region "$REGION" --command-id "$CMD_ID" --instance-id "$INSTANCE" \
    --query Status --output text)"
  aws ssm get-command-invocation --region "$REGION" --command-id "$CMD_ID" --instance-id "$INSTANCE" \
    --query StandardOutputContent --output text | tail -20
  [ "$STATUS" = Success ] || { echo "deploy failed: $STATUS" >&2; exit 1; }
else
  CLUSTER="$(tf_out ecs_cluster_name)"
  "$ROOT/scripts/ecs-deploy.sh" "$REGION" "$CLUSTER" "$TAG"
fi

"$ROOT/scripts/smoke.sh" "$(tf_out base_url)"
