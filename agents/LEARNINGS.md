# Learnings


## 2026-11-12: qualification boundaries

- A paginated first page cannot prove version absence. Complete catalogue summaries require version-read permission, not just catalogue read access.
- `require` prevents plaintext fallback but does not generally authenticate server identity. CA verification uses existing driver settings; a private-key mount needs its own restrictive permissions.

## 2026-11-13: Infracost configuration closure

- The customer Infracost key belongs to the Admin/DP encrypted installation policy. Helm supplies no feed URL or plaintext API key; runtime dispatch follows the existing deployment-token trust boundary.
