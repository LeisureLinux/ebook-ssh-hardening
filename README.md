# SSH 纵深加固：从攻击链到六层防御体系

> 一本关于 SSH 暴力破解深度防御与堡垒机架构的电子书。by [LeisureLinux](https://github.com/LeisureLinux).

[![build](https://github.com/LeisureLinux/ebook-ssh-hardening/actions/workflows/build.yml/badge.svg)](https://github.com/LeisureLinux/ebook-ssh-hardening/actions/workflows/build.yml)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE)

## 在线阅读 / 下载

| 格式 | 入口 |
|---|---|
| HTML 在线版 | <https://leisurelinux.github.io/ebook-ssh-hardening/> |
| PDF | [Releases](../../releases) 或 [直接下载](https://leisurelinux.github.io/ebook-ssh-hardening/ssh-hardening.pdf) |
| ePub | [Releases](../../releases) 或 [直接下载](https://leisurelinux.github.io/ebook-ssh-hardening/ssh-hardening.epub) |

## 目录

- **第 1 章** — 为什么 SSH 暴力破解至今仍是头号威胁
- **第 2 章** — 攻击侧：知己知彼
- **第 3 章** — 六层纵深防御体系（核心章节）
- **第 4 章** — 高级防御技术（Port Knocking / 2FA / SSH CA / 堡垒机 / Zero Trust）
- **第 5 章** — 实战案例分析
- **第 6 章** — 自动化防御
- **第 7 章** — 思维升华

## 系列姊妹篇

本仓库是 LeisureLinux **"一主题一电子书"** 纵深系列的第一本。同系列的姊妹篇：

- 📘 **[`/proc` 攻防演义](https://github.com/LeisureLinux/ebook-procfs-hardening)** — 从 Linux 进程真相到可观测性实战。7 章 + 3 附录，覆盖 `/proc` 纵深防御 / eBPF / 容器时代攻防 / SRE 工具链整合。
  - 在线阅读：<https://leisurelinux.github.io/ebook-procfs-hardening/>

系列持续更新中，下一本预计是 **Nginx 纵深加固** 或 **nftables 实战**。

## 仓库结构

```
.
├── book/
│   ├── src/             # Pandoc 输入：每章一个 Markdown
│   ├── metadata.yml     # Pandoc 元数据 (title/author/date/lang)
│   ├── theme/html.css   # HTML 主题
│   ├── cover.svg/.png   # 封面
│   └── (构建产物不入仓：dist/ 见 .gitignore)
├── .github/workflows/   # GitHub Action：build PDF + ePub + HTML
├── .gitignore
├── LICENSE              # MIT
└── README.md
```

## 本地构建

需要：
- `pandoc` ≥ 3.1
- `texlive-xetex` + `texlive-lang-chinese` + `fonts-noto-cjk`

```bash
# 安装依赖 (Debian/Ubuntu)
sudo apt-get install -y pandoc texlive-xetex texlive-lang-chinese fonts-noto-cjk

# 构建
cd book
pandoc --pdf-engine=xelatex --metadata-file=metadata.yml \
       --toc --toc-depth=3 --number-sections \
       -V mainfont="Noto Serif CJK SC" \
       src/*.md -o ../ssh-hardening.pdf

pandoc --to=epub3 --metadata-file=metadata.yml \
       --toc --toc-depth=3 --number-sections \
       --epub-cover-image=cover.png \
       src/*.md -o ../ssh-hardening.epub

pandoc --to=html5 --standalone --metadata-file=metadata.yml \
       --toc --css=theme/html.css --self-contained \
       src/*.md -o ../ssh-hardening.html
```

## 发布流程

| 触发 | 行为 |
|---|---|
| Push 到 `main` | 构建 PDF / ePub / HTML；更新 GitHub Pages |
| `git tag v*` 并 push | 上述 + 附加到 GitHub Release |
| `workflow_dispatch` | 手动触发 |

## License

MIT — see [LICENSE](./LICENSE).
