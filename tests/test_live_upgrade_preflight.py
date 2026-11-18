"""Offline regression tests: python -m unittest discover -s tests -p 'test_live_upgrade_preflight.py'"""
import tempfile
import unittest
from pathlib import Path
from tools.preflight_current_live_upgrade import TAG, REQUIRED_LIVE_MARKERS, check


class ReleasePreflightTest(unittest.TestCase):
    def make(self, root, text, filename):
        p = root / filename
        p.write_text(text, encoding="utf-8")
        return p

    def test_one_exact_tag_only(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            raw = "<html>" + " ".join(REQUIRED_LIVE_MARKERS) + "." * 360000 + "</body></html>"
            live = self.make(base, raw, "live.html")
            candidate = self.make(base, raw.replace("</body>", TAG + "</body>"), "new.html")
            self.assertTrue(check(live, candidate)["only_script_tag_added"])
            candidate.write_text(raw.replace("</body>", TAG + TAG + "</body>"))
            with self.assertRaises(ValueError):
                check(live, candidate)
            candidate.write_text(raw.replace("</body>", TAG + "<script>alert(1)</script></body>"))
            with self.assertRaises(ValueError):
                check(live, candidate)

    def test_old_github_index_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            live = self.make(base, "<html>" + "." * 357000 + "</html>", "old.html")
            candidate = self.make(base, live.read_text() + TAG, "new.html")
            with self.assertRaises(ValueError):
                check(live, candidate)


if __name__ == "__main__":
    unittest.main()
