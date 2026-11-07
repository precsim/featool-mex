#!/usr/bin/env python3
"""Decide whether a failed consumer-validation run is safe to retry."""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path


TERMINAL_SUCCESS = {"success", "skipped"}


def is_runner_acquisition_failure(job: dict[str, object]) -> bool:
    """Return true only when GitHub cancelled a job before assigning a runner."""

    return (
        job.get("conclusion") == "cancelled"
        and not job.get("runner_id")
        and not job.get("runner_name")
        and not job.get("steps")
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("jobs_json", type=Path)
    parser.add_argument("--run-attempt", type=int, required=True)
    parser.add_argument("--max-attempts", type=int, default=3)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.run_attempt < 1:
        raise SystemExit("run attempt must be at least 1")
    if args.max_attempts < 1:
        raise SystemExit("max attempts must be at least 1")

    data = json.loads(args.jobs_json.read_text(encoding="utf-8"))
    jobs = data.get("jobs")
    if not isinstance(jobs, list) or not jobs:
        raise SystemExit("workflow jobs response does not contain any jobs")

    retryable: list[dict[str, object]] = []
    blocking: list[dict[str, object]] = []
    for job in jobs:
        if not isinstance(job, dict):
            raise SystemExit("workflow jobs response contains a non-object job")
        conclusion = job.get("conclusion")
        if conclusion in TERMINAL_SUCCESS:
            continue
        if is_runner_acquisition_failure(job):
            retryable.append(job)
        else:
            blocking.append(job)

    exhausted = args.run_attempt >= args.max_attempts
    should_retry = bool(retryable) and not blocking and not exhausted

    retry_names = ", ".join(str(job.get("name", "<unnamed>")) for job in retryable)
    blocking_names = ", ".join(str(job.get("name", "<unnamed>")) for job in blocking)

    if should_retry:
        print(
            f"retrying hosted-runner acquisition failure on attempt {args.run_attempt}: "
            f"{retry_names}"
        )
    elif blocking:
        print(f"not retrying because non-infrastructure jobs failed: {blocking_names}")
    elif exhausted and retryable:
        print(
            f"not retrying hosted-runner acquisition failure after attempt "
            f"{args.run_attempt}; maximum is {args.max_attempts}: {retry_names}"
        )
    else:
        print("not retrying because no hosted-runner acquisition failure was found")

    github_output = os.environ.get("GITHUB_OUTPUT")
    if github_output:
        with Path(github_output).open("a", encoding="utf-8") as handle:
            handle.write(f"retry={'true' if should_retry else 'false'}\n")

    return 0


if __name__ == "__main__":
    sys.exit(main())
