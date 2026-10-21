#!/bin/sh
set -eu

chart=${1:-charts/platform-orchestrator}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
rendered=$work/rendered.yaml

fail() {
  echo "$*" >&2
  exit 1
}

helm template platform-orchestrator "$chart" >"$rendered"

# The application token may connect and perform JetStream administration, but
# it deliberately has no system-account access. RTT verifies an authenticated
# protocol connection without requiring $SYS request permissions.
grep -q 'until nats [$]auth rtt 1; do sleep 2; done' "$rendered"

if grep -q 'server ping' "$rendered"; then
  fail "NATS bootstrap must not require system-account server ping access"
fi

# Helm alone manages the bootstrap Job. With a TTL, Kubernetes deletes a Job
# that is still part of the release, and `helm upgrade --wait` or
# `helm rollback --wait` then fails on the missing Job.
if grep -q 'ttlSecondsAfterFinished' "$rendered"; then
  fail "the NATS bootstrap Job must not expire: Helm manages its lifecycle"
fi

# A Job's pod template is immutable, and Helm patches a Job that keeps its
# name. So the name must change whenever the rendered spec changes, and it
# must stay when nothing in the spec changes (no needless reruns).
render_job() { # render_job <variant> <chart> [helm template args...]
  variant=$1 source=$2
  shift 2
  helm template platform-orchestrator "$source" --show-only templates/nats-bootstrap-job.yaml "$@" >"$work/$variant.yaml"
  grep -q '^kind: Job$' "$work/$variant.yaml" || fail "$variant: no bootstrap Job rendered"
  if grep -q 'ttlSecondsAfterFinished' "$work/$variant.yaml"; then
    fail "$variant: the NATS bootstrap Job must not expire"
  fi
  sed -n 's/^  name: //p' "$work/$variant.yaml" >"$work/$variant.name"
  sed -n '/^spec:$/,$p' "$work/$variant.yaml" >"$work/$variant.spec"
}

# Every chart version runs the bootstrap again.
cp -R "$chart" "$work/next-chart"
sed 's/^version: .*/version: 99.0.0-contract/' "$chart/Chart.yaml" >"$work/next-chart/Chart.yaml"

render_job default "$chart"
render_job unrelated "$chart" --set runnerGateway.replicaCount=3 --set iam.replicaCount=2
render_job nats-url "$chart" --set global.config.NATS_URL=nats://nats.example.test:4222
render_job image "$chart" --set messagingBootstrap.image=natsio/nats-box:0.19.6
render_job replicas "$chart" --set messagingBootstrap.replicas=3
render_job max-bytes "$chart" --set messagingBootstrap.maxBytes.events=2147483648
render_job chart-version "$work/next-chart"

cmp -s "$work/default.name" "$work/unrelated.name" ||
  fail "the NATS bootstrap Job must keep its name while its spec is unchanged"
for variant in nats-url image replicas max-bytes chart-version; do
  if cmp -s "$work/default.name" "$work/$variant.name"; then
    fail "$variant: the NATS bootstrap Job must get a new name"
  fi
done

variants="default unrelated nats-url image replicas max-bytes chart-version"
for a in $variants; do
  for b in $variants; do
    if cmp -s "$work/$a.name" "$work/$b.name" && ! cmp -s "$work/$a.spec" "$work/$b.spec"; then
      fail "$a and $b render Job $(cat "$work/$a.name") with different specs; Helm would patch its immutable pod template"
    fi
  done
done

# Verify the command exists in the exact CLI image rendered by the chart. This
# catches incompatible CLI grammar before a Helm install can wait on the Job.
bootstrap_image=$(awk '
  /name: bootstrap/ { bootstrap = 1; next }
  bootstrap && /image:/ { gsub(/[\"[:space:]]/, "", $2); print $2; exit }
' "$rendered")
test -n "$bootstrap_image"
docker run --rm "$bootstrap_image" nats rtt --help 2>&1 | grep -q 'Compute round-trip time to NATS server'
