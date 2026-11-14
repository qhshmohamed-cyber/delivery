#!/usr/bin/env python3
"""Zero-dependency static release smoke test. Not a substitute for live security tests."""
from html.parser import HTMLParser
from pathlib import Path
import re
import subprocess
import tempfile

class Scripts(HTMLParser):
    def __init__(self):
        super().__init__()
        self.in_inline = False
        self.parts = []
    def handle_starttag(self, tag, attrs):
        if tag == "script":
            self.in_inline = not dict(attrs).get("src")
            if self.in_inline:
                self.parts.append("")
    def handle_endtag(self, tag):
        if tag == "script":
            self.in_inline = False
    def handle_data(self, data):
        if self.in_inline:
            self.parts[-1] += data

html = Path("index.html").read_text(encoding="utf-8")
parser = Scripts()
parser.feed(html)
assert html.lstrip().lower().startswith("<!doctype html>"), "HTML doctype missing"
assert 'lang="ar"' in html and 'dir="rtl"' in html, "Arabic RTL missing"
assert parser.parts, "No inline JavaScript found"
assert not re.search(r"(?i)(?:service_role|sb_secret_)[A-Za-z0-9_-]*\s*[:=]\s*['\"]", html), "Possible secret key exposure"
for token in ("dlv_assign_driver", "dlv_update_location", "dlv_my_driver_duty",
              "dlv_set_my_driver_duty", "dlv_complaint_inbox"):
    assert token in html, f"Required workflow reference missing: {token}"
assert "ensureDriverShiftForAssignment" in html, "Driver shift startup missing"
with tempfile.TemporaryDirectory() as directory:
    for i, script in enumerate(parser.parts):
        path = Path(directory) / f"inline_{i}.js"
        path.write_text(script, encoding="utf-8")
        subprocess.run(["node", "--check", str(path)], check=True)
print(f"PASS: HTML structure, key workflows, basic secret pattern, {len(parser.parts)} inline JS syntax checks")
