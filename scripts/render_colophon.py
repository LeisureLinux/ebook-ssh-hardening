#!/usr/bin/env python3
"""
Render 99-colophon.md by substituting placeholders with values derived
from git tags + commit log.

Placeholders:
  {{CURRENT_VERSION}}      - latest published tag (e.g. v0.1.7)
  {{NEXT_VERSION}}          - computed next version (bump minor)
  {{RELEASE_DATE}}          - today's date (Asia/Shanghai)
  {{CURRENT_CHANGELOG}}     - git log since previous tag, bullet list
  {{HISTORY_TABLE}}         - rows for all previous versions

Usage:
  python3 scripts/render_colophon.py

This script writes the rendered content to the same file (99-colophon.md),
so the build pipeline picks it up naturally.
"""
import datetime
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
COLOPHON = REPO / "book" / "src" / "99-colophon.md"

# Tags sorted ascending, e.g. ['v0.1.0', 'v0.1.1', ...]
def list_tags():
    out = subprocess.run(
        ["git", "tag", "--list", "v*", "--sort=version:refname"],
        cwd=REPO, capture_output=True, text=True, check=True,
    ).stdout.strip().splitlines()
    return [t for t in out if t]


def parse_version(tag):
    # v0.1.7 -> (0, 1, 7)
    m = re.match(r"v(\d+)\.(\d+)\.(\d+)", tag)
    if not m:
        return None
    return tuple(int(x) for x in m.groups())


def bump_minor(prev_tag):
    """v0.1.7 -> v0.2.0 (next planned release)"""
    v = parse_version(prev_tag)
    if v is None:
        return "v0.2.0"
    major, minor, patch = v
    return f"v{major}.{minor + 1}.0"


def changelog_since(prev_tag):
    """git log --pretty=format bullet list between prev_tag..HEAD"""
    if prev_tag:
        rng = f"{prev_tag}..HEAD"
    else:
        rng = "HEAD"
    out = subprocess.run(
        ["git", "log", rng, "--pretty=format:- %s"],
        cwd=REPO, capture_output=True, text=True, check=True,
    ).stdout.strip()
    return out or "（无新提交）"


def all_versions_with_changelog():
    """Return list of (version, date, summary) tuples, newest first."""
    tags = list_tags()
    rows = []
    # Newest first for display
    for i, tag in enumerate(reversed(tags)):
        prev = tags[len(tags) - i - 1] if i + 1 < len(tags) else None
        # Find date of this tag
        date_str = subprocess.run(
            ["git", "log", "-1", "--format=%cd", "--date=short", tag],
            cwd=REPO, capture_output=True, text=True, check=True,
        ).stdout.strip()
        # First line of subject for the tag's commit
        subject = subprocess.run(
            ["git", "log", "-1", "--format=%s", tag],
            cwd=REPO, capture_output=True, text=True, check=True,
        ).stdout.strip()
        rows.append((tag, date_str, subject))
    return rows


def render_history_table():
    rows = all_versions_with_changelog()
    lines = []
    for tag, date, subj in rows:
        # Markdown table row
        lines.append(f"| {tag} | {date} | {subj} |")
    return "\n".join(lines) if lines else "| (无历史版本) | | |"


def main():
    if not COLOPHON.exists():
        print(f"colophon not found: {COLOPHON}", file=sys.stderr)
        sys.exit(1)

    tags = list_tags()
    current = tags[-1] if tags else "v0.0.0"
    next_v = bump_minor(current)
    today = datetime.datetime.now().strftime("%Y年%-m月%-d日")
    changelog = changelog_since(tags[-2] if len(tags) >= 2 else None)
    history = render_history_table()

    text = COLOPHON.read_text(encoding="utf-8")
    text = text.replace("{{CURRENT_VERSION}}", current)
    text = text.replace("{{NEXT_VERSION}}", next_v)
    text = text.replace("{{RELEASE_DATE}}", today)
    text = text.replace("{{CURRENT_CHANGELOG}}", changelog)
    text = text.replace("{{HISTORY_TABLE}}", history)

    COLOPHON.write_text(text, encoding="utf-8")
    print(f"rendered colophon:")
    print(f"  current = {current}")
    print(f"  next    = {next_v}")
    print(f"  date    = {today}")
    print(f"  log     = {len(changelog.splitlines())} commits")


if __name__ == "__main__":
    main()
