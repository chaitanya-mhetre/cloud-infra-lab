#!/usr/bin/env bash
# Operator deploy from a laptop (reads targets from Terraform outputs).
#   scripts/deploy.sh dev <sha>        low-cost host via SSM Run Command
#   scripts/deploy.sh staging <sha>    ECS: migration task, then rolling service update
# CI uses ssm-deploy.sh / ecs-deploy.sh directly (it can't read state).
set -euo pipefail
ENV="${1:?usage: deploy.sh <env> <image_tag>}"
TAG="${2:?usage: deploy.sh <env> <image_tag>}"
REGION="${AWS_REGION:-ap-south-1}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tf_out() { (cd "$ROOT/envs/$ENV" && terraform output -raw "$1"); }

if [ "$ENV" = dev ]; then
  "$ROOT/scripts/ssm-deploy.sh" "$REGION" "$(tf_out instance_id)" "$TAG"
else
  "$ROOT/scripts/ecs-deploy.sh" "$REGION" "$(tf_out ecs_cluster_name)" "$TAG"
fi

"$ROOT/scripts/smoke.sh" "$(tf_out base_url)"
