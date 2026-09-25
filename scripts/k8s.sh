#!/usr/bin/env bash
# Local Kubernetes track on kind.
#   scripts/k8s.sh up                 cluster + ingress-nginx + metrics-server + deps
#   scripts/k8s.sh deploy [app...]    build images, load into kind, helm upgrade --install (default: rag-engine slotwise)
#   scripts/k8s.sh load-test <host>   drive CPU so the HPA scales (needs `hey` via Docker)
#   scripts/k8s.sh down               delete the cluster
# Uses kind/kubectl/helm from PATH, or from .tools/bin if present.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECTS="$(cd "$ROOT/.." && pwd)"
export PATH="$ROOT/.tools/bin:$PATH"
CLUSTER=cil-lab
INGRESS_NGINX_VERSION=controller-v1.11.3
METRICS_SERVER_VERSION=v0.7.2

need_ram() { # refuse to start on a memory-starved laptop
  local avail; avail="$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)"
  if [ "$avail" -lt "${MIN_FREE_MB:-3000}" ]; then
    echo "only ${avail} MB RAM available (< ${MIN_FREE_MB:-3000}); close something or set MIN_FREE_MB" >&2; exit 1
  fi
}

up() {
  need_ram
  kind get clusters | grep -qx "$CLUSTER" || kind create cluster --config "$ROOT/k8s/kind/cluster.yaml" --wait 120s
  kubectl apply -f "https://raw.githubusercontent.com/kubernetes/ingress-nginx/$INGRESS_NGINX_VERSION/deploy/static/provider/kind/deploy.yaml"
  # metrics-server feeds the HPA; kind's kubelet certs are self-signed, hence --kubelet-insecure-tls (local only)
  kubectl apply -f "https://github.com/kubernetes-sigs/metrics-server/releases/download/$METRICS_SERVER_VERSION/components.yaml"
  kubectl -n kube-system patch deployment metrics-server --type=json \
    -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
  kubectl apply -f "$ROOT/k8s/dev-deps/deps.yaml"
  kubectl -n ingress-nginx wait --for=condition=available deploy/ingress-nginx-controller --timeout=180s
  kubectl -n deps wait --for=condition=available deploy/postgres deploy/redis --timeout=180s
  kubectl -n kube-system wait --for=condition=available deploy/metrics-server --timeout=180s
}

deploy_app() {
  local app="$1" src tag chart values
  case "$app" in
    rag-engine) src="$PROJECTS/rag-engine" ;;
    slotwise)   src="$PROJECTS/production-fastapi" ;;
    *) echo "unknown app $app" >&2; exit 2 ;;
  esac
  tag="$(git -C "$src" rev-parse --short=12 HEAD)"
  chart="$ROOT/k8s/charts/$app"; values="$ROOT/k8s/kind/$app-values.yaml"
  echo "==> $app @ $tag"
  docker image inspect "$app:$tag" >/dev/null 2>&1 || docker build -t "$app:$tag" "$src"
  kind load docker-image "$app:$tag" --name "$CLUSTER"
  kubectl create namespace "$app" --dry-run=client -o yaml | kubectl apply -f -
  helm upgrade --install "$app" "$chart" -n "$app" -f "$values" --set image.tag="$tag" --wait --timeout 5m
}

case "${1:-}" in
  up) up ;;
  deploy) shift; need_ram; for a in "${@:-rag-engine slotwise}"; do for x in $a; do deploy_app "$x"; done; done ;;
  load-test)
    host="${2:?host, e.g. rag.localtest.me}"
    docker run --rm --network host williamyeh/hey -z 120s -c 40 -host "$host" "http://127.0.0.1:58080/v1/health" ;;
  down) kind delete cluster --name "$CLUSTER" ;;
  *) echo "usage: $0 up|deploy [app...]|load-test <host>|down" >&2; exit 2 ;;
esac
