#!/usr/bin/env python3
"""
Render 99-colophon.md by substituting placeholders with values derived
from git tags + commit log.

Approach: build the output entirely in memory from a canonical template
string (the file on disk is treated as the template). This avoids the
fragility of trying to "restore" placeholders from a previously-rendered
file.
"""
import datetime
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
COLOPHON = REPO / "book" / "src" / "99-colophon.md"

# Canonical template. Single source of truth; do NOT edit on disk
# outside of this script (any local edit will be overwritten on next run).
TEMPLATE = """# 版本信息

> 本页为电子书的自动生成元数据，会出现在 PDF / ePub / HTML 三个格式的最后一页。

| 字段 | 值 |
|------|----|
| 当前版本 | {{CURRENT_VERSION}} |
| 下一待发布版本 | {{NEXT_VERSION}} |
| 发布日期 | {{RELEASE_DATE}} |
| 仓库 | https://github.com/LeisureLinux/ebook-ssh-hardening |
| 在线阅读 | https://leisurelinux.github.io/ebook-ssh-hardening/ |
| 许可 | MIT License — © 2026 LeisureLinux |

## 本次版本修订记录 ({{CURRENT_VERSION}})

{{CURRENT_CHANGELOG}}

## 历史版本

| 版本 | 日期 | 主要变更 |
|------|------|----------|
{{HISTORY_TABLE}}

---

> 本书使用 [Pandoc](https://pandoc.org/) + [XeLaTeX](https://tug.org/xetex/) 构建，
> 字体采用 [Noto Serif CJK SC](https://github.com/notofonts/noto-cjk)，
> 通过 GitHub Actions 自动构建并发布到 GitHub Pages。
"""


def list_tags():
    out = subprocess.run(
        ["git", "tag", "--list", "v*", "--sort=version:refname"],
        cwd=REPO, capture_output=True, text=True, check=True,
    ).stdout.strip().splitlines()
    return [t for t in out if t]


def parse_version(tag):
    m = re.match(r"v(\d+)\.(\d+)\.(\d+)", tag)
    if not m:
        return None
    return tuple(int(x) for x in m.groups())


def bump_minor(prev_tag):
    v = parse_version(prev_tag)
    if v is None:
        return "v0.2.0"
    major, minor, patch = v
    return f"v{major}.{minor + 1}.0"


def changelog_between(prev_tag, current_tag):
    if prev_tag:
        rng = f"{prev_tag}..{current_tag}"
    else:
        # First release - use the current tag's commit only
        sha = subprocess.run(
            ["git", "rev-list", "-n", "1", current_tag],
            cwd=REPO, capture_output=True, text=True, check=True,
        ).stdout.strip()
        rng = sha
    out = subprocess.run(
        ["git", "log", rng, "--pretty=format:- %s"],
        cwd=REPO, capture_output=True, text=True, check=True,
    ).stdout.strip()
    return out or "（无提交记录）"


def render_history_table():
    tags = list_tags()
    lines = []
    # Newest first
    for tag in reversed(tags):
        date_str = subprocess.run(
            ["git", "log", "-1", "--format=%cd", "--date=short", tag],
            cwd=REPO, capture_output=True, text=True, check=True,
        ).stdout.strip()
        subject = subprocess.run(
            ["git", "log", "-1", "--format=%s", tag],
            cwd=REPO, capture_output=True, text=True, check=True,
        ).stdout.strip()
        lines.append(f"| {tag} | {date_str} | {subject} |")
    return "\n".join(lines) if lines else "| (无历史版本) | | |"


def main():
    tags = list_tags()
    current = tags[-1] if tags else "v0.0.0"
    next_v = bump_minor(current)
    today = datetime.datetime.now().strftime("%Y年%-m月%-d日")

    prev_tag = tags[-2] if len(tags) >= 2 else None
    changelog = changelog_between(prev_tag, current)
    history = render_history_table()

    # Always render from the canonical template (ignore disk state)
    text = TEMPLATE
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
