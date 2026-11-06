#!/usr/bin/env python3
"""Reject self-hosted/controller dependencies in the MEX release workflow."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "mex-release.yml"
FORBIDDEN = (
    "self-hosted",
    "mex-controller",
    "run_legacy_controller",
    "ci/legacy",
)
ALLOWED_RUNNERS = {
    "ubuntu-22.04",
    "ubuntu-24.04",
    "windows-2022",
    "windows-2025",
    "macos-15-intel",
    "macos-15",
}
RUNNER_VALUE_RE = re.compile(r"^\s*(?:runner|runs-on):\s*([^#]+?)\s*$")


def main() -> int:
    text = WORKFLOW.read_text(encoding="utf-8")
    violations = [token for token in FORBIDDEN if token in text]
    if violations:
        raise SystemExit(
            "mex-release.yml must use GitHub-hosted runners only; found: "
            + ", ".join(violations)
        )

    unexpected_runners = set()
    for line in text.splitlines():
        match = RUNNER_VALUE_RE.match(line)
        if not match:
            continue
        value = match.group(1).strip().strip("'\"")
        if value == "${{ matrix.runner }}":
            continue
        if value not in ALLOWED_RUNNERS:
            unexpected_runners.add(value)

    if unexpected_runners:
        raise SystemExit(
            "mex-release.yml contains an unapproved runner label: "
            + ", ".join(sorted(unexpected_runners))
        )

    print("MEX release workflow is GitHub-hosted-only.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
