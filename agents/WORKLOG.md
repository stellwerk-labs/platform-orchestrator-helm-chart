# Worklog


## 2026-11-12: Helm database TLS defaults and certificate examples

- Implemented the requested local change with targeted tests and documentation. Independent planning, green and final clean-code reviews passed after correcting partial-summary availability and removing an unsupported mTLS mount example.
- TLS configuration was exercised against real PostgreSQL; UI and complete-history/permission boundaries were tested. Hosted release qualification and immutable public schema/image pins remain pending. No public publication or live deployment is established by this local checkpoint.

## 2026-11-13: Infracost Admin policy (uncommitted)

- Removed the unreleased price-catalogue ConfigMap setting and regenerated chart documentation; preserved the exact cost-estimation route, all versions and image pins.
- `make docs`, `helm lint charts/platform-orchestrator` and `helm template cost-policy charts/platform-orchestrator` passed. See `DECISIONS.md` and `LEARNINGS.md`; campaign evidence is `INFRACOST-BACKEND-EVIDENCE.md`.
