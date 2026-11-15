"""Prevent untranslated Cyrillic text from returning to tracked project files."""
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
CYRILLIC = re.compile(r"[\u0400-\u052f]")


class EnglishSources(unittest.TestCase):
    def test_tracked_project_text_has_no_cyrillic(self):
        names = subprocess.check_output(
            ["git", "ls-files", "-z"], cwd=ROOT
        ).decode("utf-8").split("\0")
        remaining = []
        for name in filter(None, names):
            if CYRILLIC.search(name):
                remaining.append(name + " (filename)")
            path = ROOT / name
            if not path.is_file():
                continue
            try:
                content = path.read_text("utf-8-sig")
            except UnicodeDecodeError:
                continue
            for number, line in enumerate(content.splitlines(), 1):
                if CYRILLIC.search(line):
                    remaining.append(f"{name}:{number}")
        self.assertEqual(
            0, len(remaining),
            "Untranslated text (first 30 locations): " + ", ".join(remaining[:30]),
        )


if __name__ == "__main__":
    unittest.main()
