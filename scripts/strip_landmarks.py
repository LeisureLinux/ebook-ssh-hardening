#!/usr/bin/env python3
"""
Strip the ePub3 landmarks nav block from EPUB/nav.xhtml.

Pandoc emits a <nav epub:type="landmarks"> with entries for Cover /
Title Page / Table of Contents. These appear at the end of the TOC
even though they're already listed in the main TOC. This script
removes that nav block after pandoc has finished.
"""
import re
import shutil
import sys
import zipfile
from pathlib import Path

EPUB_PATH = Path(sys.argv[1] if len(sys.argv) > 1 else "dist/ssh-hardening.epub")
TMP_PATH = EPUB_PATH.with_suffix(EPUB_PATH.suffix + ".tmp")

LANDMARKS_NAV_RE = re.compile(
    r'<nav[^>]*epub:type="landmarks"[^>]*>.*?</nav>',
    re.DOTALL,
)


def main():
    if not EPUB_PATH.exists():
        print(f"epub not found: {EPUB_PATH}", file=sys.stderr)
        sys.exit(1)

    stripped = False
    with zipfile.ZipFile(EPUB_PATH, "r") as zin, \
         zipfile.ZipFile(TMP_PATH, "w", zipfile.ZIP_DEFLATED) as zout:
        for item in zin.infolist():
            data = zin.read(item.filename)
            if item.filename == "EPUB/nav.xhtml":
                txt = data.decode("utf-8")
                new = LANDMARKS_NAV_RE.sub("", txt)
                if new != txt:
                    stripped = True
                data = new.encode("utf-8")
            zout.writestr(item, data)

    shutil.move(TMP_PATH, EPUB_PATH)
    if stripped:
        print(f"stripped landmarks nav from {EPUB_PATH}")
    else:
        print(f"no landmarks nav found in {EPUB_PATH}")


if __name__ == "__main__":
    main()
