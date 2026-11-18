"""Offline test of safe real-live-index modularization. Run from repository root:
python -m unittest discover -s tests -p 'test_prepare_live_index_modularization.py'
"""
from __future__ import annotations
import tempfile
import unittest
from pathlib import Path
from tools.prepare_live_index_modularization import prepare

class IndexSplitTests(unittest.TestCase):
    def test_preserves_source_and_reverses_exactly(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            live = root / "public_html"
            live.mkdir()
            source = live / "index.html"
            js = "\n".join(["const _x = 12345;"] * 8000)
            doc = f'<!doctype html><html><head></head><body><script>{js}</script><script src="other.js"></script></body></html>'
            original = doc.encode("utf-8")
            source.write_bytes(original)
            dest = root / "private" / "candidate-01"
            manifest = prepare(source, dest)
            self.assertEqual(source.read_bytes(), original)
            self.assertLess(manifest["html_bytes_after"], len(original) - 100000)
            self.assertEqual((dest / manifest["asset_name"]).read_text("utf-8"), js)
            altered = (dest / "index.html").read_text("utf-8")
            self.assertEqual(
                altered.replace(f'<script src="{manifest["asset_name"]}"></script>',
                                f'<script>{js}</script>', 1), doc)
            self.assertTrue((dest / "manifest.json").is_file())

    def test_refuses_inline_document_current_script(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "public_html" / "index.html"
            source.parent.mkdir()
            source.write_text("<script>document.currentScript;\n"+"let x=12345;\n"*10000+"</script>")
            with self.assertRaises(ValueError):
                prepare(source,root / "private" / "candidate-02")

    def test_refuses_output_under_web_root(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "public_html" / "index.html"
            source.parent.mkdir()
            source.write_text("<script>"+"let x=12345;\n"*10000+"</script>")
            with self.assertRaises(ValueError):
                prepare(source,source.parent / "candidate-03")

if __name__ == "__main__":
    unittest.main()
