# 版本信息

> 本页为电子书的自动生成元数据，会出现在 PDF / ePub / HTML 三个格式的最后一页。

| 字段 | 值 |
|------|----|
| 当前版本 | v0.1.7 |
| 下一待发布版本 | v0.2.0 |
| 发布日期 | 2026年7月22日 |
| 仓库 | https://github.com/LeisureLinux/ebook-ssh-hardening |
| 在线阅读 | https://leisurelinux.github.io/ebook-ssh-hardening/ |
| 许可 | MIT License — © 2026 LeisureLinux |

## 本次版本修订记录 (v0.1.7)

- 修改 bash code block, 去掉郭大侠词汇
- fix(ebook): revert over-eager bullet separation + soft-wrap long URLs
- fix(ebook): colophon YAML title overrode metadata.yml title

## 历史版本

| 版本 | 日期 | 主要变更 |
|------|------|----------|
| v0.1.7 | 2026-07-22 | fix(ebook): revert over-eager bullet separation + soft-wrap long URLs |
| v0.1.6 | 2026-07-22 | fix(workflow): move strip_landmarks to scripts/strip_landmarks.py |
| v0.1.5 | 2026-07-22 | fix(ebook): bullet 换行 + 代码块围栏 + 关于作者最后一句 |
| v0.1.4 | 2026-07-22 | fix(ebook): ePub 排版 6 项问题 |
| v0.1.3 | 2026-07-22 | fix(ebook): ePub CJK font fallback + cover SVG re-render with CJK |
| v0.1.2 | 2026-07-22 | fix(ebook): promote H4 to H3 so subsections render as 3.1.1 not 3.1.0.1 |
| v0.1.0 | 2026-07-22 | fix(workflow): add pages:write and id-token:write permissions |

---

> 本书使用 [Pandoc](https://pandoc.org/) + [XeLaTeX](https://tug.org/xetex/) 构建，
> 字体采用 [Noto Serif CJK SC](https://github.com/notofonts/noto-cjk)，
> 通过 GitHub Actions 自动构建并发布到 GitHub Pages。
