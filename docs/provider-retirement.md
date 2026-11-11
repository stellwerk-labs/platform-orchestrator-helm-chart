# Activating Provider retirement

The setting `control-plane.config.PROVIDER_RETIREMENT_ENABLED` defaults to
`"false"`. Keep it disabled during the rolling upgrade. Every serving Control
Plane and every Data Plane execution writer must support Provider retirement
before activation. Checking a version on one pod is insufficient.

1. Upgrade the qualified CP/DP image set with retirement disabled and wait for
   rollout completion. Confirm the running image digests and that no predecessor
   replicas or transactions remain.
2. Verify the authenticated DP Provider-usage endpoint reports protocol version 1
   and complete canonical Environment coverage. Missing legacy state must be
   restored or reconciled, never treated as empty.
3. Enable `control-plane.config.PROVIDER_RETIREMENT_ENABLED: "true"` in the
   instance values, then apply the same qualified chart. This enables requests
   and bounded background reconciliation.
4. Verify the lifecycle with an isolated test Provider before marking customer
   Providers. A request returns `202`; the row stays visible until authoritative
   managed-state and admission checks permit deletion.

Disabling reconciliation leaves pending requests and configuration intact. It
does not make a downgraded writer safe or erase the deletion timestamp. The
schema refuses a metadata downgrade while deletion requests are pending.

Retirement does not destroy workloads. Remove the Provider's desired bindings
and deploy cleanup, or use the existing non-force environment destroy flow.
Terraform/OpenTofu waits for confirmed removal, rather than interpreting an
accepted request as a completed delete.
