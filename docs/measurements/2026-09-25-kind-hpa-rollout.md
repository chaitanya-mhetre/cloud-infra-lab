# Measurement: HPA scale-up and rolling restart on kind (rag-engine chart)

**Date:** 2026-09-25 · **Environment:** laptop, Intel i5-1240P (16 threads), ~4–6 GB free RAM,
kind v0.24.0 single-node cluster (Kubernetes from kind's default node image), ingress-nginx controller-v1.11.3,
metrics-server v0.7.2. Load generator `hey` on the same machine. **Not a production benchmark**; it shows
the mechanisms working, and the numbers only hold for this setup.

Commands: `scripts/k8s.sh up && scripts/k8s.sh deploy rag-engine`, then `hey` against the ingress.
Values: `k8s/kind/rag-engine-values.yaml` (api request 100m CPU, HPA 1→4 at 50% CPU). Image: rag-engine @ c8e1a5c5ac36.

## 1. HPA scale-up under load
`hey -z 150s -c 40` against `GET /v1/health` through ingress-nginx.

| t (s) | HPA current/desired | avg CPU vs request | ready pods |
|---|---|---|---|
| 0–26 | 1/1 | 3–6% | 1 |
| 31 | 1/4 | 305% | 1 |
| 42 | 1/4 | 305% | **4** |
| 47+ | 4/4 | 660–990% | 4 |

- **From load start to HPA deciding to scale: ~31 s.** Most of that is metrics-server's scrape + averaging window.
- **From load start to 4 ready pods: ~42 s.** Pods were ready in about 11 s after the decision (image already on the node).
- CPU stayed far above target at max replicas (4 on one node): the ceiling was `maxReplicas` + one node, not the HPA.
- hey totals: 261,489 requests, all HTTP 200; ~1,743 req/s; p50 16 ms, p95 71 ms, p99 140 ms (includes the single-pod warm-up).

## 2. Rolling restart under load (zero-downtime check)
`hey -z 60s -c 10 -q 20` against `GET /v1/ready` while running `kubectl rollout restart` of the 4-pod API.

- **11,974 requests, 11,974 × HTTP 200, 0 errors** during a full rollout (maxSurge 1 / maxUnavailable 0,
  readiness gating, `preStop: sleep 5`).
- p50 7.3 ms, p99 17.6 ms.

## 3. Other checks in the same session
- The migration Job ran as a pre-install hook, succeeded, and was deleted (`hook-succeeded`).
- `GET /metrics` through the ingress → **503** (blackhole route); `/v1/health` → 200, `/v1/ready` → 200.
- The PVC bound on kind's `standard` StorageClass (RWO, single node).

Raw `hey` output was kept locally (not committed). Cluster deleted right after the run.
