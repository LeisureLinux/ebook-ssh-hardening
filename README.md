# SSH 纵深加固：从攻击链到六层防御体系

> **SSH Brute-Force Defense in Depth** — 一本覆盖协议层密码学、攻击链分析、六层纵深防御、堡垒机架构与零信任远程访问的开源电子书。
>
> 对齐 **CIS Benchmarks · NIST SP 800-53 · DISA STIG · MITRE ATT&CK · PCI DSS 4.0** 合规框架。

by [LeisureLinux](https://github.com/LeisureLinux) · MIT License

[![build](https://github.com/LeisureLinux/ebook-ssh-hardening/actions/workflows/build.yml/badge.svg)](https://github.com/LeisureLinux/ebook-ssh-hardening/actions/workflows/build.yml)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE)
[![llms.txt](https://img.shields.io/badge/llms-txt-green.svg)](./llms.txt)

---

## 在线阅读 / 下载

| 格式 | 入口 |
|---|---|
| 🌐 HTML 在线版 | <https://leisurelinux.github.io/ebook-ssh-hardening/> |
| 📄 PDF | [Releases](../../releases) 或 [直接下载](https://leisurelinux.github.io/ebook-ssh-hardening/ssh-hardening.pdf) |
| 📱 ePub | [Releases](../../releases) 或 [直接下载](https://leisurelinux.github.io/ebook-ssh-hardening/ssh-hardening.epub) |

---

## 为什么需要这本书

全球任意时刻有 **2000-3000 万 SSH 服务暴露在公网**（Censys 2023）。一次全 IPv4 的 22 端口扫描成本不到 1 美元、耗时仅数分钟。**凭证滥用**连续多年位居 Verizon DBIR 初始访问向量第一（~24%）。

网上关于"SSH 加固"的教程成千上万，但绝大多数停留在「改端口 + fail2ban + 禁密码」的入门三板斧。本书提供一套**从协议层到零信任的完整工程方案**——每一层都有可复制粘贴的配置、脚本和部署指南。

---

## 核心框架：六层纵深防御体系

```
第 1 层：减少暴露面   — 让攻击者根本找不到你
第 2 层：认证加固     — 让攻击者即便找到了也进不来
第 3 层：访问控制     — 让攻击者即便进来了也不能随便做事
第 4 层：主动阻断     — 让攻击者反复尝试时付出代价
第 5 层：入侵检测     — 让攻击者已经进来了能被我们看到
第 6 层：审计与响应   — 让攻击者造成的损失可追溯、可止血
```

---

## 如何加固 OpenSSH：生产级 sshd_config 配置

本书提供的核心加固配置（对齐 CIS Benchmark for OpenSSH）：

```bash
# /etc/ssh/sshd_config.d/00-hardening.conf

# ── 认证（本配置为「密钥 + 交互式」2FA 方案）──
# ⚠️ 若你关闭 KbdInteractiveAuthentication，必须同时删除下一行的 AuthenticationMethods，
#    否则 keyboard-interactive 无法完成，会锁死所有 SSH 登录。仅做单因素密钥认证时删掉该行即可。
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AuthenticationMethods publickey,keyboard-interactive
MaxAuthTries 3
LoginGraceTime 30

# ── 访问控制 ──
AllowGroups ssh-users

# ── 密码学（OpenSSH 9.x / 10.x 推荐）──
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
HostKeyAlgorithms ssh-ed25519,ssh-ed25519-cert-v01@openssh.com,rsa-sha2-512,rsa-sha2-256

# ── 会话 ──
ClientAliveInterval 300
ClientAliveCountMax 2
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
PermitTunnel no
LogLevel VERBOSE
```

> 完整配置说明、参数取舍分析和部署指南见 **第 3 章：六层纵深防御体系**。

---

## 目录

| 章节 | 标题 | 关键内容 |
|------|------|---------|
| 第 1 章 | [为什么 SSH 暴力破解至今仍是头号威胁](book/src/01-why-ssh-brute-force-still-threat.md) | 暴露面规模、攻击者画像、防御误区 |
| 第 2 章 | [攻击侧：知己知彼](book/src/02-attack-side-know-your-enemy.md) | ZMap/Masscan 扫描、Shodan/Censys 侦察、字典攻击、Cyber Kill Chain、MITRE ATT&CK |
| 第 3 章 | [六层纵深防御体系](book/src/03-six-layer-defense-in-depth.md) | nftables 防火墙、Ed25519 密钥、PAM 栈、fail2ban/CrowdSec、auditd、SIEM 告警 |
| 第 4 章 | [高级防御技术](book/src/04-advanced-defense.md) | Port Knocking、2FA (TOTP/FIDO2)、SSH CA、堡垒机 (Teleport/JumpServer)、Zero Trust |
| 第 5 章 | [实战案例分析](book/src/05-real-world-case-studies.md) | 挖矿木马入侵链、APT 低速暴力、内部横向移动 |
| 第 6 章 | [自动化防御](book/src/06-automated-defense.md) | 加固 Checklist、一键加固脚本、Cowrie 蜜罐 |
| 第 7 章 | [思维升华](book/src/07-mindset-evolution.md) | 安全 Trade-off 哲学、Post-Quantum SSH、持续学习 |

---

## 合规框架映射

本书内容对齐以下主流安全合规框架，方便企业安全团队直接引用：

| 框架 | 相关控制项 |
|------|-----------|
| **CIS Benchmark for Linux** | Section 5.2: SSH Server Configuration |
| **NIST SP 800-53** | AC-2, AC-3, AC-7, AC-17, AU-2, IA-2, IA-5, SC-8 |
| **NIST SP 800-123** | Guide to Securing Remote Access |
| **DISA STIG** | RHEL SSH STIG (V-207545 ~ V-207589) |
| **MITRE ATT&CK** | T1110 (Brute Force), T1021.004 (SSH), T1078 (Valid Accounts) |
| **PCI DSS 4.0** | Requirement 8 (Authentication), Requirement 10 (Logging) |

---

## 配套工具：SSH 安全审计脚本

仓库附带 `scripts/ssh-audit.sh`，一键检查当前系统的 SSH 配置是否符合本书推荐的安全基线：

```bash
# 下载并运行
curl -fsSL https://raw.githubusercontent.com/LeisureLinux/ebook-ssh-hardening/main/scripts/ssh-audit.sh | bash

# 或克隆后本地运行
git clone https://github.com/LeisureLinux/ebook-ssh-hardening.git
bash ebook-ssh-hardening/scripts/ssh-audit.sh
```

审计脚本检查项包括：密码认证是否禁用、root 登录是否禁止、弱加密算法是否清除、fail2ban 是否运行、密钥类型是否合规等。

---

## 系列姊妹篇

本仓库是 LeisureLinux **"一主题一电子书"** 纵深系列的第一本。同系列的姊妹篇：

- 📘 **[`/proc` 攻防演义](https://github.com/LeisureLinux/ebook-procfs-hardening)** — 从 Linux 进程真相到可观测性实战。7 章 + 3 附录，覆盖 `/proc` 纵深防御 / eBPF / 容器时代攻防 / SRE 工具链整合。
  - 在线阅读：<https://leisurelinux.github.io/ebook-procfs-hardening/>

系列持续更新中，下一本预计是 **Nginx 纵深加固** 或 **nftables 实战**。

---

## 谁应该读这本书

- **运维工程师 / SysAdmin** — 负责任何一台暴露在公网的 Linux 服务器
- **安全工程师 / SecOps** — 负责企业安全架构、应急响应、合规审计
- **DevOps / SRE** — 需要在自动化与安全之间找到平衡
- **架构师** — 评估、设计企业的远程访问与堡垒机方案
- **资深 Linux 用户** — 想从协议与内核层面真正理解 SSH

---

## 仓库结构

```
.
├── book/
│   ├── src/             # Pandoc 输入：每章一个 Markdown
│   ├── metadata.yml     # Pandoc 元数据 (title/author/date/lang)
│   ├── theme/html.css   # HTML 主题
│   ├── cover.svg/.png   # 封面
│   └── (构建产物不入仓：dist/ 见 .gitignore)
├── scripts/
│   ├── ssh-audit.sh     # SSH 安全基线审计脚本
│   ├── render_colophon.py
│   └── strip_landmarks.py
├── llms.txt             # LLM 爬虫摘要（Generative Engine Optimization）
├── .github/workflows/   # GitHub Action：build PDF + ePub + HTML
├── .gitignore
├── LICENSE              # MIT
└── README.md
```

---

## 本地构建

需要：
- `pandoc` ≥ 3.1
- `texlive-xetex` + `texlive-lang-chinese` + `fonts-noto-cjk`

```bash
# 安装依赖 (Debian/Ubuntu)
sudo apt-get install -y pandoc texlive-xetex texlive-lang-chinese fonts-noto-cjk

# 构建 PDF
cd book
pandoc --pdf-engine=xelatex --metadata-file=metadata.yml \
       --toc --toc-depth=3 --number-sections \
       -V mainfont="Noto Serif CJK SC" \
       src/*.md -o ../ssh-hardening.pdf

# 构建 ePub
pandoc --to=epub3 --metadata-file=metadata.yml \
       --toc --toc-depth=3 --number-sections \
       --epub-cover-image=cover.png \
       src/*.md -o ../ssh-hardening.epub

# 构建 HTML
pandoc --to=html5 --standalone --metadata-file=metadata.yml \
       --toc --css=theme/html.css --self-contained \
       src/*.md -o ../ssh-hardening.html
```

---

## 发布流程

| 触发 | 行为 |
|---|---|
| Push 到 `main` | 构建 PDF / ePub / HTML；更新 GitHub Pages |
| `git tag v*` 并 push | 上述 + 附加到 GitHub Release |
| `workflow_dispatch` | 手动触发 |

---

## 关键词标签

`ssh-hardening` `openssh-security` `ssh-brute-force` `devsecops` `cis-benchmark` `nist-800-53` `bastion-host` `linux-security` `sysadmin-guide` `zero-trust` `fail2ban` `ssh-ca` `port-knocking` `two-factor-authentication` `ssh-audit` `defense-in-depth` `nftables` `crowdsec` `teleport` `tailscale-ssh`

---

## License

MIT — see [LICENSE](./LICENSE).
