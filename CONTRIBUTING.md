# Contributing

1. `make check` must pass. It runs fmt, validate, `terraform test` (mocked provider), tflint, checkov,
   template render tests, and helm lint/kubeconform/checkov. Everything runs in Docker, so you only need Docker and make.
2. Scanner findings are fixed, or skipped **inline** with a one-line reason (`#checkov:skip=ID:reason`). No blanket skips.
3. A PR that destroys or replaces resources needs the `allow-destroy` label, added after reading the plan comment.
4. Never commit `backend.hcl`, `*.tfstate`, or real secret values. `gitleaks` runs in CI.
5. Conventional commits (`feat(module): ...`, `fix: ...`, `docs: ...`, `ci: ...`).
6. Any number in docs must come from a run you can point to (`docs/measurements/`), or be marked as an estimate/TBD.
