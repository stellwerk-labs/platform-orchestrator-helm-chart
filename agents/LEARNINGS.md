# Learnings


## 2026-11-12: qualification boundaries

- A paginated first page cannot prove version absence. Complete catalogue summaries require version-read permission, not just catalogue read access.
- `require` prevents plaintext fallback but does not generally authenticate server identity. CA verification uses existing driver settings; a private-key mount needs its own restrictive permissions.

## 2026-11-13: Infracost configuration closure

- The customer Infracost key belongs to the Admin/DP encrypted installation policy. Helm supplies no feed URL or plaintext API key; runtime dispatch follows the existing deployment-token trust boundary.


## 2026-11-13: Chart release preparation

The generated parent README comes from README.md.gotmpl, including release guidance; edit the template and run make docs. Nested component versions and appVersion do not substitute for final digest qualification.


## 2026-11-14: Qualified pin and contract preparation

Image pin updates can invalidate deliberate test expectations. Search the existing contracts before hosted CI and place the pinned Helm executable in `PATH`; some shell contracts call `helm` directly. Preserve the assertions and select the existing Python interpreter with its required modules.
