#!/usr/bin/env bash
set -euo pipefail

release_tag=${1:?usage: chart-release-version.sh TAG CHART_VERSION}
chart_version=${2:?usage: chart-release-version.sh TAG CHART_VERSION}
numeric='(0|[1-9][0-9]*)'
version_pattern="^v${numeric}\\.${numeric}\\.${numeric}(-rc\\.[1-9][0-9]*)?$"

if ! [[ "$release_tag" =~ $version_pattern ]]; then
  echo "Expected a canonical vMAJOR.MINOR.PATCH or vMAJOR.MINOR.PATCH-rc.N tag (N >= 1)" >&2
  exit 1
fi
if [[ "$release_tag" != "v$chart_version" ]]; then
  echo "Release tag does not match Chart.yaml version" >&2
  exit 1
fi

prerelease=false
if [[ "$chart_version" == *-rc.* ]]; then
  prerelease=true
fi
printf 'release_tag=%s\nchart_version=%s\nprerelease=%s\n' "$release_tag" "$chart_version" "$prerelease"
