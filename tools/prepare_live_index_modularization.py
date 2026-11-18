#!/usr/bin/env python3
"""Stage a byte-preserving, HTML-lightening candidate from the ACTUAL live index.html.

Does not touch the original or upload files. It externalizes ONLY the single largest
classic inline <script> without attributes, then verifies byte-for-byte reversibility.
This is a candidate for TackHost Test, NOT an automatic production change.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

PATTERN = re.compile(r"(?is)<script\b([^>]*)>(.*?)</script\s*>")
UNSAFE = re.compile(r"\bdocument\s*\.\s*(?:currentScript|write)\b|\bimport\s*\.\s*meta\b")


def prepare(source: Path, output_dir: Path) -> dict:
    source = source.resolve()
    output_dir = output_dir.resolve()
    if not source.is_file() or source.name.lower() != "index.html":
        raise ValueError("Source must be the actual current index.html file")
    if source.parent == output_dir or source.parent in output_dir.parents:
        raise ValueError("Staging must be OUTSIDE the public website directory")
    if output_dir.exists():
        raise FileExistsError("Staging directory exists. Choose a new location; never overwrite it")
    original_bytes = source.read_bytes()
    original = original_bytes.decode("utf-8")
    if original.encode("utf-8") != original_bytes:
        raise ValueError("Input encoding is not lossless UTF-8")
    candidates = [
        match for match in PATTERN.finditer(original)
        if not match.group(1).strip()
        and len(match.group(2).encode("utf-8")) >= 100_000
    ]
    if not candidates:
        raise ValueError("No eligible large plain inline classic script; do not rewrite manually")
    match = max(candidates, key=lambda m: len(m.group(2)))
    script = match.group(2)
    if UNSAFE.search(script):
        raise ValueError("Script depends on inline execution context; automatic extraction unsafe")
    js_hash = hashlib.sha256(script.encode("utf-8")).hexdigest()
    asset_name = f"ys-live-runtime-{js_hash[:16]}.js"
    tag = f'<script src="{asset_name}"></script>'
    rewritten = original[:match.start()] + tag + original[match.end():]
    if rewritten.replace(tag, match.group(0), 1) != original:
        raise AssertionError("Conversion is not reversible")
    reduction = len(original_bytes) - len(rewritten.encode("utf-8"))
    if reduction < 100_000:
        raise AssertionError("HTML did not get materially smaller")

    output_dir.mkdir(parents=True, exist_ok=False)
    (output_dir / "index.html").write_bytes(rewritten.encode("utf-8"))
    (output_dir / asset_name).write_bytes(script.encode("utf-8"))
    manifest = {
        "source_sha256": hashlib.sha256(original_bytes).hexdigest(),
        "staged_html_sha256": hashlib.sha256(rewritten.encode("utf-8")).hexdigest(),
        "extracted_js_sha256": js_hash,
        "asset_name": asset_name,
        "html_bytes_before": len(original_bytes),
        "html_bytes_after": len(rewritten.encode("utf-8")),
        "note": "Test load order, cache/PWA offline support, browser behavior and WAF logs BEFORE deployment",
    }
    (output_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    print(json.dumps(prepare(args.source, args.out), indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
