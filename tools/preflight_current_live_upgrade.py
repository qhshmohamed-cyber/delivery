#!/usr/bin/env python3
"""Fail-closed check for the ONE-SCRIPT-TAG TackHost deployment strategy.
Never writes or uploads any file. The baseline MUST be freshly copied from
the CURRENT production public_html/index.html; stale GitHub HTML is NOT usable.

Usage: python tools/preflight_current_live_upgrade.py --live live-index.html --candidate candidate-index.html
"""
import argparse
import hashlib
from pathlib import Path

TAG = '<script src="yourstaff-efficient-20261119.js?v=20261119-1"></script>'
REQUIRED_LIVE_MARKERS = (
    "gps-quality.js", "team-tools.js", "staff-entry.js",
    "dlv_update_location_v2", "feedback-owner.js?v=2"
)


def check(live: Path, candidate: Path) -> dict:
    original = live.read_bytes()
    updated = candidate.read_bytes()
    baseline = original.decode("utf-8")
    changed = updated.decode("utf-8")
    if len(original) < 350000:
        raise ValueError("Baseline is suspiciously small: do not use stale GitHub index.html")
    if any(marker not in baseline for marker in REQUIRED_LIVE_MARKERS):
        raise ValueError("Baseline lacks live-only fixes; do not proceed")
    if TAG in baseline:
        if changed != baseline:
            raise ValueError("Tag is already installed; leave production HTML unchanged")
    else:
        if changed.count(TAG) != 1 or changed.replace(TAG, "", 1) != baseline:
            raise ValueError("Only the single approved script tag may be added; refuse other changes")
    return {
        "checked": True,
        "live_sha256": hashlib.sha256(original).hexdigest(),
        "candidate_sha256": hashlib.sha256(updated).hexdigest(),
        "only_script_tag_added": TAG not in baseline,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--live", required=True, type=Path)
    parser.add_argument("--candidate", required=True, type=Path)
    args = parser.parse_args()
    result = check(args.live, args.candidate)
    print("PASS: live baseline preserved; script tag is the only allowed change")
    print("Source SHA256:", result["live_sha256"])
    print("Candidate SHA256:", result["candidate_sha256"])


if __name__ == "__main__":
    main()
