#!/usr/bin/env python3
"""Contract tests for the actual chart release validator and workflow."""
import importlib.util
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("preflight", ROOT / "scripts/chart-release-preflight.py")
PREFLIGHT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PREFLIGHT)
SHA = "0123456789abcdef0123456789abcdef01234567"
OTHER = "fedcba9876543210fedcba9876543210fedcba98"
TAG = "v0.7.0-rc.1"


class ReleaseIdentityTests(unittest.TestCase):
    def test_exact_commit(self):
        PREFLIGHT.validate_identity(SHA, SHA, SHA, SHA)

    def test_noncanonical_sha(self):
        for value in ("main", SHA[:12], SHA.upper(), SHA + "\n", "z" * 40):
            with self.subTest(value=value), self.assertRaises(ValueError):
                PREFLIGHT.validate_identity(value, value, value, value)

    def test_checkout_local_or_remote_tag_moved(self):
        for index in range(3):
            values = [SHA, SHA, SHA]
            values[index] = OTHER
            with self.subTest(index=index), self.assertRaises(ValueError):
                PREFLIGHT.validate_identity(SHA, *values)

    def test_remote_lightweight_and_annotated_tags(self):
        ref = f"refs/tags/{TAG}"
        self.assertEqual(PREFLIGHT.remote_commit(TAG, f"{SHA}\t{ref}\n"), SHA)
        self.assertEqual(PREFLIGHT.remote_commit(TAG, f"{OTHER}\t{ref}\n{SHA}\t{ref}^{{}}\n"), SHA)

    def test_remote_missing_ambiguous_or_invalid_tag(self):
        ref = f"refs/tags/{TAG}"
        for response in ("", f"{SHA}\t{ref}^{{}}\n", f"{SHA}\trefs/heads/main\n",
                         f"{SHA}\t{ref}\n{OTHER}\t{ref}\n", f"short\t{ref}\n"):
            with self.subTest(response=response), self.assertRaises(ValueError):
                PREFLIGHT.remote_commit(TAG, response)

    def test_actual_version_validator_rejects_untrusted_refs(self):
        script = str(ROOT / "scripts/chart-release-version.sh")
        for tag in ("main", "v0.7.0-rc.01", "v0.7.0-rc.1\n", "v0.7.0;true"):
            with self.subTest(tag=tag):
                result = subprocess.run(["bash", script, tag, "0.7.0-rc.1"], capture_output=True)
                self.assertNotEqual(result.returncode, 0)


class DuplicatePublicationTests(unittest.TestCase):
    def test_registry_requires_explicit_not_found(self):
        PREFLIGHT.validate_absence_status("OCI chart", 404)
        for status in (200, 301, 401, 403, 429, 500, None):
            with self.subTest(status=status), self.assertRaises(ValueError):
                PREFLIGHT.validate_absence_status("OCI chart", status)

    def test_empty_or_other_release_page(self):
        PREFLIGHT.validate_release_page(TAG, [])
        PREFLIGHT.validate_release_page(TAG, [{"tag_name": "v0.6.1", "draft": False}])

    def test_both_drafts_and_published_releases_consume_tag(self):
        for draft in (True, False):
            with self.subTest(draft=draft), self.assertRaises(ValueError):
                PREFLIGHT.validate_release_page(TAG, [{"tag_name": TAG, "draft": draft}])

    def test_malformed_or_unbounded_release_page_fails_closed(self):
        for page in ({"message": "not found"}, [None], [{}], [{"tag_name": TAG, "draft": "false"}],
                     [{"tag_name": "v0.6.1", "draft": False}] * 101):
            with self.subTest(page=page), self.assertRaises(ValueError):
                PREFLIGHT.validate_release_page(TAG, page)


class WorkflowContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workflow = (ROOT / ".github/workflows/release-chart.yaml").read_text()
        cls.jobs = dict(re.findall(r"^  (preflight|validate|release):\n(.*?)(?=^  \w+:|\Z)",
                                  cls.workflow, re.M | re.S))

    def test_tests_and_package_use_same_immutable_revision(self):
        self.assertEqual(set(self.jobs), {"preflight", "validate", "release"})
        for job in self.jobs.values():
            self.assertIn("ref: ${{ inputs.release_sha }}", job)
            self.assertNotIn("ref: ${{ inputs.release_tag }}", job)
        self.assertIn("needs: preflight", self.jobs["validate"])
        self.assertIn("needs: [preflight, validate]", self.jobs["release"])

    def test_only_publication_job_has_write_permissions(self):
        self.assertIn("permissions:\n  contents: read", self.workflow)
        self.assertNotIn("contents: write", self.jobs["preflight"])
        for job in ("preflight", "release"):
            self.assertIn("github.repository == 'stellwerk-labs/platform-orchestrator-helm-chart'", self.jobs[job])
            self.assertIn("persist-credentials: false", self.jobs[job])
        self.assertIn("contents: write", self.jobs["release"])
        self.assertIn("packages: write", self.jobs["release"])

    def test_reservation_precedes_registry_publication(self):
        release = self.jobs["release"]
        order = [release.index(part) for part in (
            "--check-unpublished", 'gh release create "$RELEASE_TAG" "$chart"',
            'helm push "$chart"', 'gh release edit "$RELEASE_TAG"')]
        self.assertEqual(order, sorted(order))
        reserve = release[order[1]:order[2]]
        self.assertIn("--verify-tag", reserve)
        self.assertIn("--draft", reserve)
        self.assertIn("--draft=false", release[order[3]:])
        self.assertIn("group: release-${{ github.repository }}", release)
        self.assertIn("cancel-in-progress: false", release)
        self.assertEqual(release.count('chart-release-preflight.py "$RELEASE_TAG" "$RELEASE_SHA"'), 2)

    def test_candidates_cannot_become_latest_or_overwrite_artifacts(self):
        release = self.jobs["release"]
        self.assertIn('if [[ "$PRERELEASE" == true ]]', release)
        self.assertIn("release_flags+=(--prerelease --latest=false)", release)
        for forbidden in ("--force", "--clobber", "git tag ", "release delete", "git push "):
            self.assertNotIn(forbidden, release)

    def test_validator_is_part_of_reusable_ci(self):
        lint = (ROOT / ".github/workflows/lint-test.yaml").read_text()
        self.assertIn("run: python3 scripts/chart-release-preflight_test.py", lint)


if __name__ == "__main__":
    unittest.main()
