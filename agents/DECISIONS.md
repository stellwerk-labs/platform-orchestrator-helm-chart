# Decisions


## 2026-11-12: Helm database TLS defaults and certificate examples

- Preserve existing permissions, confirmation and default behavior. PostgreSQL TLS is opt-in through `DATABASE_SSLMODE`; use existing driver and certificate mechanisms.
- Catalogue filters use complete optional summaries, omit version data for core-only readers, and keep unavailable distinct from false. Verification remains unimplemented; its filter is intentionally present with an explicit limitation.

## 2026-11-13: Infracost Admin policy

- Keep the exact `/platform-settings/cost-estimation` gateway route. Remove the unreleased price-catalogue URL setting entirely; the installation credential is managed through write-only Admin settings and encrypted by DP with Vault Transit.
- Preserve all image digests and chart versions. No release/publication or backend-specific key Secret is introduced.


## 2026-11-13: Chart 0.12 public preparation

Advance chart metadata to 0.12.0 / CP appVersion4.1.0 and consolidate release notes without altering existing image pins. Final qualified public digests are a prerequisite to the final chart commit/publication; no placeholder digest is acceptable.


## 2026-11-14: Qualified pin and contract preparation

Keep the Casbin test’s exact image assertion. Update its IAM version and digest alongside the qualified component pins. Preserve `Recreate`, absence of SpiceDB runtime resources, retained rollback databases and Secrets, and explicit removal when preservation is disabled. All 18 existing contracts pass.
