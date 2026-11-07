#!/usr/bin/env python3
"""Decide whether a failed consumer-validation run is safe to retry."""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path


TERMINAL_SUCCESS = {"success", "skipped"}
RUNNER_ACQUISITION_FAILURE = (
    "The job was not acquired by Runner of type hosted even after multiple attempts"
)


def has_runner_acquisition_annotation(
    job: dict[str, object], annotations_dir: Path
) -> bool:
    job_id = job.get("id")
    if not isinstance(job_id, int):
        return False

    annotations_path = annotations_dir / f"{job_id}.json"
    if not annotations_path.is_file():
        return False

    annotations = json.loads(annotations_path.read_text(encoding="utf-8"))
    if not isinstance(annotations, list):
        return False

    return any(
        isinstance(annotation, dict)
        and annotation.get("annotation_level") == "failure"
        and annotation.get("message") == RUNNER_ACQUISITION_FAILURE
        for annotation in annotations
    )


def is_runner_acquisition_failure(
    job: dict[str, object], annotations_dir: Path
) -> bool:
    """Return true only for GitHub-confirmed hosted-runner acquisition failures."""

    return (
        job.get("conclusion") == "cancelled"
        and not job.get("runner_id")
        and not job.get("runner_name")
        and not job.get("steps")
        and has_runner_acquisition_annotation(job, annotations_dir)
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("jobs_json", type=Path)
    parser.add_argument("--annotations-dir", type=Path, required=True)
    parser.add_argument("--run-attempt", type=int, required=True)
    parser.add_argument("--max-attempts", type=int, default=3)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.run_attempt < 1:
        raise SystemExit("run attempt must be at least 1")
    if args.max_attempts < 1:
        raise SystemExit("max attempts must be at least 1")
    if not args.annotations_dir.is_dir():
        raise SystemExit(f"annotations directory does not exist: {args.annotations_dir}")

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
        if is_runner_acquisition_failure(job, args.annotations_dir):
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
