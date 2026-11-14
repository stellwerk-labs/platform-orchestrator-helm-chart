# Worklog


## 2026-11-12: Helm database TLS defaults and certificate examples

- Implemented the requested local change with targeted tests and documentation. Independent planning, green and final clean-code reviews passed after correcting partial-summary availability and removing an unsupported mTLS mount example.
- TLS configuration was exercised against real PostgreSQL; UI and complete-history/permission boundaries were tested. Hosted release qualification and immutable public schema/image pins remain pending. No public publication or live deployment is established by this local checkpoint.

## 2026-11-13: Infracost Admin policy (uncommitted)

- Removed the unreleased price-catalogue ConfigMap setting and regenerated chart documentation; preserved the exact cost-estimation route, all versions and image pins.
- `make docs`, `helm lint charts/platform-orchestrator` and `helm template cost-policy charts/platform-orchestrator` passed. See `DECISIONS.md` and `LEARNINGS.md`; campaign evidence is `INFRACOST-BACKEND-EVIDENCE.md`.


## Managed logs, 2026-11-13

Clarified CORS release notes: DecryptKey header supports legacy caller-owned clients; new Console uses automatic reads without that header. No chart templates, defaults or package inputs changed.


## 2026-11-13: Chart 0.12 preparation

Prepared metadata and release guidance for TLS, optional customer Infracost credentials, managed log permissions and Vault Transit identity recovery. Preserved existing public image pins pending qualified digests. See DECISIONS.md and LEARNINGS.md; full packaged final-set qualification remains pending.


## 2026-11-14: Qualified pin and contract preparation

Updated 4 qualified public component pins in 5 locations and regenerated the README. All 18 existing CI contract entrypoints passed with Helm `4.3.0`, Python `3.13.1` and GNU `sha256sum`. The Casbin test now expects the qualified IAM `2.8.1` image; all migration and rollback assertions remain. The original failed expectation and independent planning, green and final reviews are retained in the release campaign. The DP pin, final package, commit and publication await qualification of the original DP `4.4.0` artifacts.


## 2026-11-14: Final local source

Prepared the final Data Plane `4.4.0` pin from the published index `cdab42c0f86ec742a8298e4e776c82c170eae4fff1df4cc6011e04165a3b4903`. Its independent original consumer remains a publication hold. Release notes now describe the pinned component set and link the Runner’s existing, version-scoped vendor security disposition. Documentation generation, Helm `4.3.0` lint, release-note Markdown lint and whitespace checks passed. Commit locally for exact source/package comparison; public source, tag, chart and deployment remain held for the required artifact qualifications.
