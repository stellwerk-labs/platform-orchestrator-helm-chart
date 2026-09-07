#!/usr/bin/env python3
"""Read-only identity and duplicate-publication checks for the stock chart."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

REPOSITORY = "stellwerk-labs/platform-orchestrator-helm-chart"
OCI_REPOSITORY = "stellwerk-labs/charts/platform-orchestrator"
SHA = re.compile(r"[0-9a-f]{40}")


def validate_identity(expected, head, local_tag, remote_tag):
    if not SHA.fullmatch(expected):
        raise ValueError("release SHA must be exactly 40 lowercase hexadecimal characters")
    if any(value != expected for value in (head, local_tag, remote_tag)):
        raise ValueError("approved SHA, checkout, local tag and remote tag must identify the same commit")


def remote_commit(tag, refs):
    base = "refs/tags/" + tag
    values = {}
    for line in refs.splitlines():
        parts = line.split()
        if len(parts) != 2 or parts[1] not in (base, base + "^{}") or not SHA.fullmatch(parts[0]):
            raise ValueError("unexpected remote tag response")
        if parts[1] in values:
            raise ValueError("ambiguous remote tag response")
        values[parts[1]] = parts[0]
    if base not in values:
        raise ValueError("the release tag must already exist on the remote")
    return values.get(base + "^{}", values[base])


def validate_absence_status(destination, status):
    if status != 404:
        raise ValueError(f"{destination} absence is not proven (HTTP {status}); refuse publication")


def response_status(request):
    try:
        with urlopen(request, timeout=20) as response:
            return response.status
    except HTTPError as error:
        return error.code


def validate_release_page(tag, releases):
    if not isinstance(releases, list) or len(releases) > 100:
        raise ValueError("unexpected GitHub release list")
    for release in releases:
        if (not isinstance(release, dict)
                or not isinstance(release.get("tag_name"), str)
                or not isinstance(release.get("draft"), bool)):
            raise ValueError("unexpected GitHub release record")
        if release["tag_name"] == tag:
            raise ValueError("a draft or published GitHub release already reserves this tag")


def assert_unpublished(tag, version):
    token = os.environ.get("GH_TOKEN")
    if not token:
        raise ValueError("GH_TOKEN is required to detect existing draft releases as well as public releases")
    # The tag lookup only promises published releases. The publication job uses
    # its contents:write token to enumerate drafts too, including older pages.
    for page in range(1, 101):
        request = Request(
            f"https://api.github.com/repos/{REPOSITORY}/releases?per_page=100&page={page}",
            headers={"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json"},
        )
        with urlopen(request, timeout=20) as response:
            releases = json.load(response)
        validate_release_page(tag, releases)
        if len(releases) < 100:
            break
    else:
        raise ValueError("release-list safety limit reached; absence is not proven")
    query = urlencode({"service": "ghcr.io", "scope": f"repository:{OCI_REPOSITORY}:pull"})
    with urlopen(f"https://ghcr.io/token?{query}", timeout=20) as response:
        pull_token = json.load(response)["token"]
    request = Request(
        f"https://ghcr.io/v2/{OCI_REPOSITORY}/manifests/{version}",
        headers={"Authorization": f"Bearer {pull_token}",
                 "Accept": "application/vnd.oci.image.manifest.v1+json"},
        method="HEAD",
    )
    validate_absence_status("OCI chart", response_status(request))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tag")
    parser.add_argument("sha")
    parser.add_argument("--check-unpublished", action="store_true")
    args = parser.parse_args()
    validate_identity(args.sha, args.sha, args.sha, args.sha)
    chart = Path("charts/platform-orchestrator/Chart.yaml").read_text()
    versions = re.findall(r"^version: ([^\s]+)$", chart, re.M)
    if len(versions) != 1:
        raise ValueError("Chart.yaml must contain exactly one unquoted chart version")
    # Reuse the canonical version/tag validator before interpreting a Git ref.
    subprocess.run(["bash", "scripts/chart-release-version.sh", args.tag, versions[0]],
                   check=True, stdout=subprocess.DEVNULL)
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    local_tag = subprocess.check_output(["git", "rev-parse", "--verify", f"refs/tags/{args.tag}^{{commit}}"], text=True).strip()
    remote = subprocess.check_output(["git", "ls-remote", "--exit-code", "origin",
                                      f"refs/tags/{args.tag}", f"refs/tags/{args.tag}^{{}}"], text=True)
    validate_identity(args.sha, head, local_tag, remote_commit(args.tag, remote))
    if not Path("docs/releases", args.tag + ".md").is_file():
        raise ValueError("reviewed release notes must exist at docs/releases/<tag>.md")
    if args.check_unpublished:
        if os.environ.get("GITHUB_REPOSITORY") != REPOSITORY:
            raise ValueError("publication preflight is restricted to the original chart repository")
        assert_unpublished(args.tag, versions[0])
    print(f"Verified chart {versions[0]} at {args.sha}; no publication performed.")


if __name__ == "__main__":
    main()
