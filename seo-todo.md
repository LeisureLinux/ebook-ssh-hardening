# GEO/SEO 社区互动待办清单

> 本文档记录了通过技术社区互动提升电子书可见度的具体行动计划。
> 核心原则：**先提供价值，再自然引用**。不要硬广，要做技术解答。

---

## 📋 优先级说明

| 优先级 | 含义 | 建议时间 |
|--------|------|----------|
| P0 | 高杠杆，立即执行 | 本周 |
| P1 | 中等杠杆，持续投入 | 本月 |
| P2 | 长期积累，定期维护 | 持续 |

---

## 🔥 P0: Stack Overflow / Server Fault

### 目标问题（按搜索量排序）

#### 1. SSH 加固基础类
- [ ] [How to secure SSH server?](https://serverfault.com/questions/372050/how-to-secure-ssh-server)
  - **回答要点**: 六层纵深防御框架，从禁用密码到 fail2ban
  - **引用**: 第 3 章配置示例
  - **状态**: ⏳ 待回答

- [ ] [Best practices for hardening SSH on Linux](https://stackoverflow.com/questions/tagged/ssh+hardening)
  - **回答要点**: 提供完整的 sshd_config 加固配置
  - **引用**: llms.txt 中的配置块
  - **状态**: ⏳ 待回答

#### 2. 密码学相关
- [ ] [SSH key types: RSA vs DSA vs ECDSA vs Ed25519](https://stackoverflow.com/questions/4662960/ssh-key-types)
  - **回答要点**: 详细对比各算法安全性，推荐 Ed25519
  - **引用**: 第 3 章"密钥类型深度对比"
  - **状态**: ⏳ 待回答

- [ ] [Disable weak ciphers in OpenSSH](https://serverfault.com/questions/641083/disable-weak-ciphers-in-openssh)
  - **回答要点**: 提供 OpenSSH 9.x 推荐的 Ciphers/MACs/KexAlgorithms
  - **引用**: 第 3 章密码学配置
  - **状态**: ⏳ 待回答

#### 3. 高级主题
- [ ] [SSH Certificate Authority setup](https://serverfault.com/questions/713665/setting-up-an-ssh-certificate-authority)
  - **回答要点**: SSH CA 架构设计，签发流程
  - **引用**: 第 4 章"证书认证（SSH CA）"
  - **状态**: ⏳ 待回答

- [ ] [fail2ban vs CrowdSec for SSH protection](https://serverfault.com/questions/1094782/fail2ban-vs-crowdsec)
  - **回答要点**: 架构对比，适用场景
  - **引用**: 第 3 章"第 4 层：主动阻断"
  - **状态**: ⏳ 待回答

### 回答模板

```markdown
针对 [问题描述]，推荐采用**纵深防御**策略：

## 1. 认证加固
```bash
# /etc/ssh/sshd_config.d/00-hardening.conf
PasswordAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
```

## 2. 密码学配置（OpenSSH 9.x）
```bash
KexAlgorithms curve25519-sha256,diffie-hellman-group16-sha512
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
```

## 3. 主动阻断（fail2ban）
```ini
# /etc/fail2ban/jail.local
[sshd]
enabled = true
maxretry = 3
bantime = 3600
```

完整方案可参考《SSH 纵深加固》电子书：
- 在线阅读: https://leisurelinux.github.io/ebook-ssh-hardening/
- GitHub: https://github.com/LeisureLinux/ebook-ssh-hardening

审计脚本（一键检查配置）:
```bash
curl -fsSL https://raw.githubusercontent.com/LeisureLinux/ebook-ssh-hardening/main/scripts/ssh-audit.sh | bash
```
```

---

## 🎯 P1: Reddit 技术社区

### 目标 Subreddit

#### r/sysadmin (1.2M 成员)
- [ ] **帖子标题**: `Open-source SSH hardening guide with 6-layer defense framework (CIS/NIST aligned)`
- [ ] **内容要点**:
  - 为什么"改端口+fail2ban"不够
  - 六层防御框架图解
  - 生产级 sshd_config 配置
  - 合规框架映射（CIS/NIST/DISA）
- [ ] **链接**: GitHub 仓库 + 在线阅读
- **状态**: ⏳ 待发布

#### r/netsec (800K 成员)
- [ ] **帖子标题**: `Deep dive: SSH attack chain analysis + defense in depth (from protocol to Zero Trust)`
- [ ] **内容要点**:
  - 攻击者视角：ZMap/Masscan 全网扫描原理
  - MITRE ATT&CK 映射（T1110, T1021.004）
  - 从暴力破解到内网横向的完整 TTP
  - 防御方案：SSH CA + Bastion + Zero Trust
- [ ] **链接**: 第 2 章 + 第 4 章
- **状态**: ⏳ 待发布

#### r/linuxadmin (200K 成员)
- [ ] **帖子标题**: `SSH audit script: one-command security baseline check (CIS Benchmark aligned)`
- [ ] **内容要点**:
  - 演示 ssh-audit.sh 输出
  - 检查项列表（认证/密码学/网络/防护/检测/密钥）
  - 如何集成到 CI/CD
- [ ] **链接**: scripts/ssh-audit.sh
- **状态**: ⏳ 待发布

### Reddit 帖子模板

```markdown
# Title: [技术话题] + [价值主张]

## TL;DR
[3-5 句话总结核心价值]

## Background
[为什么写这个/解决什么问题]

## Key Points
1. [要点 1 + 代码/配置示例]
2. [要点 2 + 代码/配置示例]
3. [要点 3 + 代码/配置示例]

## Resources
- 📖 Full guide: [在线阅读链接]
- 💻 Source code: [GitHub 链接]
- 🔧 Audit script: `curl -fsSL [脚本URL] | bash`

## Feedback
欢迎提 issue 或 PR，特别是：
- 遗漏的检查项
- 更好的配置建议
- 翻译贡献

---
*Disclaimer: I'm the author, but this is MIT-licensed and community-driven.*
```

---

## 🚀 P1: Hacker News (Show HN)

### 帖子计划

- [ ] **标题**: `Show HN: Open-source SSH hardening guide with 6-layer defense (CIS/NIST aligned)`
- [ ] **URL**: https://leisurelinux.github.io/ebook-ssh-hardening/
- [ ] **内容要点**:
  - 为什么写这个（Verizon DBIR 数据：凭证滥用占 24%）
  - 六层防御框架（不是单点加固）
  - 合规框架映射（企业可直接引用）
  - 配套工具（ssh-audit.sh）
- [ ] **评论策略**: 主动回复技术问题，分享更多细节

### Show HN 帖子模板

```markdown
Hi HN,

I've been working on an open-source SSH hardening guide that covers:

1. **Attack chain analysis** - from ZMap/Masscan scanning to MITRE ATT&CK mapping
2. **6-layer defense framework** - not just "change port + fail2ban", but defense in depth
3. **Compliance mapping** - CIS Benchmarks, NIST SP 800-53, DISA STIG, PCI DSS 4.0
4. **Production configs** - copy-paste sshd_config for OpenSSH 9.x
5. **Audit tool** - ssh-audit.sh for one-command security baseline check

Why I wrote this:
- Verizon DBIR 2024: credential abuse is #1 initial access vector (~24%)
- 20-30M SSH services exposed on public internet (Censys 2023)
- Most "SSH hardening" guides stop at basics, miss protocol-level defense

Tech decisions:
- Why Ed25519 over RSA (no NIST curve trust issues)
- Why ChaCha20-Poly1305 (better performance on ARM, no AES-NI needed)
- Why SSH CA for orgs with >20 servers (eliminates authorized_keys sprawl)

Feedback welcome, especially on:
- Missing compliance frameworks
- Better cipher recommendations
- Additional audit checks

GitHub: https://github.com/LeisureLinux/ebook-ssh-hardening
Online: https://leisurelinux.github.io/ebook-ssh-hardening/

MIT licensed. PRs welcome.
```

---

## 📝 P1: Dev.to / Medium 技术文章

### 文章计划

#### Dev.to 文章 1
- [ ] **标题**: `SSH Hardening in 2026: Beyond "Change Port + Fail2ban"`
- [ ] **标签**: `#security` `#linux` `#ssh` `#devops` `#sysadmin`
- [ ] **内容大纲**:
  1. 为什么基础加固不够（APT 低速攻击）
  2. 六层纵深防御框架
  3. 生产级配置示例
  4. 审计脚本使用方法
- [ ] **链接**: 电子书 + GitHub
- **状态**: ⏳ 待撰写

#### Dev.to 文章 2
- [ ] **标题**: `How to Audit Your SSH Configuration in One Command`
- [ ] **标签**: `#security` `#automation` `#bash` `#linux`
- [ ] **内容大纲**:
  1. 演示 ssh-audit.sh 输出
  2. 检查项详解（6 大类 20+ 项）
  3. 如何集成到 CI/CD
  4. 自定义检查项
- [ ] **链接**: scripts/ssh-audit.sh
- **状态**: ⏳ 待撰写

#### Medium 文章（可选）
- [ ] **标题**: `SSH Certificate Authority: Why Your Organization Needs It`
- [ ] **内容大纲**:
  1. authorized_keys 管理痛点
  2. SSH CA 架构设计
  3. 签发流程详解
  4. HashiCorp Vault 集成
- [ ] **链接**: 第 4 章"证书认证"
- **状态**: ⏳ 待撰写

---

## 🌟 P2: Awesome-List PR 提交

### 目标仓库

#### awesome-sysadmin
- [ ] **仓库**: https://github.com/awesome-foss/awesome-sysadmin
- [ ] **分类**: Security → SSH
- [ ] **提交内容**:
  ```markdown
  - [SSH Hardening Guide](https://github.com/LeisureLinux/ebook-ssh-hardening) - Open-source ebook on SSH brute-force defense with 6-layer defense framework, CIS/NIST aligned.
  ```
- **状态**: ⏳ 待提交 PR

#### awesome-linux-security
- [ ] **仓库**: https://github.com/trimstray/the-practical-linux-hardening-guide (或类似仓库)
- [ ] **分类**: Tools / SSH
- [ ] **提交内容**: 同上
- **状态**: ⏳ 待查找合适仓库

#### awesome-security
- [ ] **仓库**: https://github.com/sbilly/awesome-security
- [ ] **分类**: SSH / Hardening
- [ ] **提交内容**: 同上
- **状态**: ⏳ 待提交 PR

### PR 模板

```markdown
## Adding: SSH Hardening Guide

### Description
Open-source ebook covering SSH brute-force defense with 6-layer defense framework:
- Attack chain analysis (ZMap/Masscan, MITRE ATT&CK)
- Defense in depth (firewall → auth → access control → active blocking → IDS → audit)
- Compliance mapping (CIS Benchmarks, NIST SP 800-53, DISA STIG)
- Production configs (OpenSSH 9.x sshd_config)
- Audit tool (ssh-audit.sh)

### Why it belongs here
- Comprehensive SSH security resource
- MIT licensed, community-driven
- Includes executable audit script
- Aligned with industry compliance frameworks

### Checklist
- [x] Added to appropriate section
- [x] Alphabetically sorted
- [x] Description is concise and informative
- [x] Link is valid

Thanks for reviewing!
```

---

## 📊 P2: 技术问答平台持续监控

### 关键词订阅

#### Stack Overflow
- [ ] 订阅标签: `ssh`, `openssh`, `ssh-hardening`, `linux-security`
- [ ] 设置邮件通知: 每周一次
- [ ] 目标: 每周回答 2-3 个相关问题

#### Server Fault
- [ ] 订阅标签: `ssh`, `linux`, `security`
- [ ] 目标: 每周回答 1-2 个高票问题

#### Reddit
- [ ] 订阅 subreddit: r/sysadmin, r/netsec, r/linuxadmin
- [ ] 设置关键词提醒: "SSH hardening", "SSH security", "fail2ban"

#### GitHub Discussions
- [ ] 监控相关仓库的 Discussions:
  - `fail2ban/fail2ban`
  - `crowdsecurity/crowdsec`
  - `gravitational/teleport`
- [ ] 在相关讨论中引用本书

---

## 📈 效果追踪

### 指标记录表

| 日期 | 平台 | 动作 | 链接 | 效果 |
|------|------|------|------|------|
| 2026-08-01 | GitHub | Release v0.2.0 | [link](https://github.com/LeisureLinux/ebook-ssh-hardening/releases/tag/v0.2.0) | - |
| 2026-08-01 | GitHub | Topics 设置 | [repo](https://github.com/LeisureLinux/ebook-ssh-hardening) | - |
| - | Stack Overflow | 待回答 | - | - |
| - | Reddit | 待发布 | - | - |
| - | Hacker News | 待发布 | - | - |

### 月度复盘

- [ ] 每月 1 号统计:
  - GitHub stars / forks / watchers 增长
  - 在线阅读量（GitHub Pages analytics）
  - 下载量（Release assets）
  - 社区互动数（回答/帖子/PR）
- [ ] 调整策略:
  - 哪些平台效果最好？
  - 哪些话题最受欢迎？
  - 需要补充什么内容？

---

## 🎯 执行建议

### 第一周（P0）
1. Stack Overflow 回答 3-5 个高票问题
2. 准备 Reddit/HN 帖子草稿

### 第二周（P1）
1. 发布 Reddit 帖子（r/sysadmin）
2. 发布 Hacker News Show HN
3. 提交 Awesome-List PR

### 第三周（P1）
1. 撰写 Dev.to 文章
2. 继续 Stack Overflow 回答
3. 监控社区反馈

### 持续（P2）
1. 每周回答 2-3 个技术问题
2. 每月复盘调整策略
3. 根据社区反馈更新电子书

---

## ⚠️ 注意事项

1. **不要硬广**: 先提供价值，再自然引用
2. **遵守规则**: 每个平台都有自己的 self-promotion 规则
3. **保持一致**: 用户名、头像、简介要统一
4. **及时回复**: 有人评论要及时回应
5. **记录反馈**: 社区反馈是改进电子书的宝贵资源

---

*最后更新: 2026-08-01*
*维护者: LeisureLinux*
