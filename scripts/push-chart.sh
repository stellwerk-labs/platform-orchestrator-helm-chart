#!/usr/bin/env bash
# Push one packaged chart to an OCI repository.
#
#   push-chart.sh CHART_TGZ OCI_REPOSITORY [helm push flags...]
#
# helm push uploads the manifest by digest and then tags it, and GHCR can answer the lookup of a manifest
# it has just accepted with 404 for a moment (chart 0.12.3 lost its publisher run to it). The push is
# content-addressed, so it is repeated for exactly that error; anything else, a timeout included, fails at
# once. A failed attempt may already have written the tag, so the caller checks the destination's absence
# once, before this script, never between attempts.
set -euo pipefail
usage="usage: push-chart.sh CHART_TGZ OCI_REPOSITORY [helm push flags...]"
chart="${1:?$usage}"
repository="${2:?$usage}"
shift 2
attempts=6
pause="${PUBLISH_RETRY_PAUSE_SECONDS:-10}"
lag='^Error: failed to perform "Tag" on destination: sha256:[0-9a-f]{64}: not found$'
errors="$(mktemp)"
trap 'rm -f -- "$errors"' EXIT

for attempt in $(seq "$attempts"); do
  status=0
  # 6 attempts of 120 s plus pauses fit the 20 min release job.
  timeout -k 5s 120s helm push "$@" "$chart" "$repository" 2>"$errors" || status=$?
  cat "$errors" >&2
  if ((status == 0)); then exit 0; fi
  if ((status != 1 || attempt == attempts)) || ! tail -n 1 "$errors" | grep -Eq "$lag"; then
    exit "$status"
  fi
  printf 'Registry did not yet serve a manifest it had just accepted; push attempt %d of %d, retrying.\n' \
    "$attempt" "$attempts" >&2
  sleep "$pause"
done
