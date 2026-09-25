#!/usr/bin/env bash
# Low-cost mode deploy: run host-deploy.sh on the instance via SSM Run Command and wait.
#   scripts/ssm-deploy.sh <region> <instance_id> <tag|--rollback>
set -euo pipefail
REGION="${1:?region}"; INSTANCE="${2:?instance id}"; ARG="${3:?tag or --rollback}"

CMD_ID="$(aws ssm send-command --region "$REGION" --instance-ids "$INSTANCE" \
  --document-name AWS-RunShellScript --comment "deploy $ARG" --timeout-seconds 900 \
  --parameters "commands=[\"/opt/slotwise/host-deploy.sh $ARG\"]" \
  --query Command.CommandId --output text)"
echo "==> SSM command $CMD_ID on $INSTANCE"

# `aws ssm wait command-executed` gives up after ~100 s; deploys can take longer.
for _ in $(seq 1 90); do
  STATUS="$(aws ssm get-command-invocation --region "$REGION" --command-id "$CMD_ID" \
    --instance-id "$INSTANCE" --query Status --output text 2>/dev/null || echo Pending)"
  case "$STATUS" in Pending|InProgress|Delayed) sleep 10 ;; *) break ;; esac
done

aws ssm get-command-invocation --region "$REGION" --command-id "$CMD_ID" --instance-id "$INSTANCE" \
  --query '[StandardOutputContent,StandardErrorContent]' --output text | tail -40
[ "$STATUS" = Success ] || { echo "✘ deploy finished with status $STATUS" >&2; exit 1; }
echo "✔ deploy $ARG succeeded"
