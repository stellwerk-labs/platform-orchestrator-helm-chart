# Publishing the stock chart

The manually dispatched **Release Chart** workflow publishes stable tags
`vMAJOR.MINOR.PATCH` and candidates `vMAJOR.MINOR.PATCH-rc.N`. Candidates are
GitHub prereleases, never the latest release. This workflow does not publish
component images or create Git tags.

## Prerequisites

- Obtain approval for the exact public source, chart version and destinations.
  Preparing this workflow locally is not permission to dispatch it.
- Land the reviewed workflow on the default branch before dispatch. Select a
  reviewed workflow revision, not arbitrary untrusted code with publishing rights.
- Prepare reviewed release notes at `docs/releases/<tag>.md`, the matching
  `Chart.yaml` version and compatible, already-published component image pins.
- Create the approved release tag separately according to repository signing
  policy. Supply both the existing tag and its full, lowercase 40-character
  commit SHA. The helper checks identity, not cryptographic tag signatures.
- Preserve protected tags and restrict other registry writers. The workflow
  requires the established public OCI chart repository to be readable; it does
  not bootstrap an absent or private package when absence cannot be proven.

## Identity and duplicate protection

Preflight compares the supplied SHA with the checkout, the local peeled tag and
the current remote peeled tag. The reusable chart tests and packaging job then
check out that exact SHA. The identity is checked again before packaging and
immediately before publication, so tag movement between jobs fails the run.

The publication job uses its `contents: write` token to enumerate all release
pages, including drafts. It also requires an explicit HTTP 404 for the OCI
version. A release, draft, existing chart, malformed response, authorization
failure, rate limit or unavailable registry blocks publication. GitHub's
[release-by-tag endpoint only promises published releases](https://docs.github.com/en/rest/releases/releases#get-a-release-by-tag-name),
so that endpoint alone is not a safe draft-reservation check.

Publication is serialized for this repository. Once checks and packaging pass,
the workflow reserves a draft release and attaches the chart archive **before**
pushing the chart to OCI. Only then does it publish that draft. A repeated run
therefore stops even if an earlier run failed after reserving the version.
There is no chart overwrite, release deletion, tag creation or forced update.

This protects repeated executions of this pipeline, not arbitrary independent
registry publishers: OCI tag publication has no client-side compare-and-swap
here. Repository/tag protection and constrained registry credentials remain
operator prerequisites.

## Interrupted publication

Keep a partial draft and any uploaded chart as failure evidence. Do not delete
the reservation, rerun with different source, move its tag or overwrite its OCI
version. Inspect the failed stage and existing artifacts, then obtain approval
for a new candidate version and tag. Final verification failures also require
investigation; a green source test is not evidence that publication succeeded.

## Local checks

Run `python3 scripts/chart-release-preflight_test.py` and the chart contract
steps in `.github/workflows/lint-test.yaml`. These exercise the real validator
and workflow structure without creating tags, releases or registry artifacts.
Actual GitHub token permissions, draft visibility, OCI upload and downloaded
artifact verification require a separately approved publication rehearsal.
