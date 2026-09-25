#!/usr/bin/env bash
set -euo pipefail

script="$(dirname "$0")/chart-release-version.sh"
stable=$(bash "$script" v1.2.3 1.2.3)
[[ "$stable" == $'release_tag=v1.2.3\nchart_version=1.2.3\nprerelease=false' ]]
candidate=$(bash "$script" v1.2.3-rc.1 1.2.3-rc.1)
[[ "$candidate" == $'release_tag=v1.2.3-rc.1\nchart_version=1.2.3-rc.1\nprerelease=true' ]]

for invalid in 'main' '1.2.3' 'v01.2.3' 'v1.2' 'v1.2.3-rc.0' 'v1.2.3-rc.01' \
  'v1.2.3-beta.1' 'v1.2.3+build.1' 'v1.2.3;false' $'v1.2.3\nprerelease=false'; do
  if bash "$script" "$invalid" "${invalid#v}" >/dev/null 2>&1; then
    echo "Unexpectedly accepted release tag: $invalid" >&2
    exit 1
  fi
done
if bash "$script" v1.2.3-rc.1 1.2.3 >/dev/null 2>&1; then
  echo "Candidate tag must not publish a stable chart version" >&2
  exit 1
fi
echo "Chart release version validation: PASS"
