#!/usr/bin/env bash
# Run infra tooling from pinned Docker images so contributors don't need local installs.
# Usage: scripts/tools.sh <terraform|tflint|checkov|helm|kubeconform> [args...]
# Runs in the current directory; the repo root is mounted at /repo.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REL="${PWD#"$ROOT"}"
CACHE="$ROOT/.tools"
mkdir -p "$CACHE/plugin-cache" "$CACHE/tflint" "$CACHE/helm"

TF_IMAGE="${TF_IMAGE:-hashicorp/terraform:1.9}"
TFLINT_IMAGE="${TFLINT_IMAGE:-ghcr.io/terraform-linters/tflint:latest}"
CHECKOV_IMAGE="${CHECKOV_IMAGE:-bridgecrew/checkov:latest}"
HELM_IMAGE="${HELM_IMAGE:-alpine/helm:3.16.2}"
KUBECONFORM_IMAGE="${KUBECONFORM_IMAGE:-ghcr.io/yannh/kubeconform:latest}"

tool="$1"; shift
common=(--rm -u "$(id -u):$(id -g)" -v "$ROOT:/repo" -w "/repo$REL")

case "$tool" in
  terraform)
    exec docker run "${common[@]}" -e HOME=/repo/.tools -e TF_PLUGIN_CACHE_DIR=/repo/.tools/plugin-cache \
      -e TF_IN_AUTOMATION=1 "$TF_IMAGE" "$@" ;;
  tflint)
    exec docker run "${common[@]}" -e HOME=/repo/.tools -e TFLINT_PLUGIN_DIR=/repo/.tools/tflint \
      --entrypoint tflint "$TFLINT_IMAGE" "$@" ;;
  checkov)
    exec docker run "${common[@]}" -e HOME=/tmp "$CHECKOV_IMAGE" "$@" ;;
  helm)
    exec docker run "${common[@]}" -e HOME=/repo/.tools/helm "$HELM_IMAGE" "$@" ;;
  kubeconform)
    exec docker run -i --rm -v "$ROOT:/repo" -w "/repo$REL" "$KUBECONFORM_IMAGE" "$@" ;;
  *)
    echo "unknown tool: $tool" >&2; exit 2 ;;
esac
