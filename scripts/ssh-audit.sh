#!/usr/bin/env bash
# ============================================================================
# ssh-audit.sh — SSH 安全基线审计脚本
# 配套电子书：《SSH 纵深加固：从攻击链到六层防御体系》
# 仓库：https://github.com/LeisureLinux/ebook-ssh-hardening
#
# 用法：
#   sudo bash ssh-audit.sh              # 完整审计
#   sudo bash ssh-audit.sh --quiet      # 仅输出不合规项
#   sudo bash ssh-audit.sh --json       # JSON 格式输出
#
# 对齐：CIS Benchmark for OpenSSH / NIST SP 800-53 / DISA STIG
# ============================================================================

set -euo pipefail

# ── 颜色 ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── 参数解析 ──
QUIET=false
JSON_OUT=false
for arg in "$@"; do
  case "$arg" in
    --quiet) QUIET=true ;;
    --json)  JSON_OUT=true ;;
  esac
done

# ── 计数器 ──
PASS=0
FAIL=0
WARN=0
RESULTS=()

# ── 工具函数 ──
check_pass() {
  ((PASS++)) || true
  RESULTS+=("PASS|$1|$2")
  $QUIET || echo -e "  ${GREEN}[PASS]${NC} $1 — $2"
}

check_fail() {
  ((FAIL++)) || true
  RESULTS+=("FAIL|$1|$2")
  echo -e "  ${RED}[FAIL]${NC} $1 — $2"
}

check_warn() {
  ((WARN++)) || true
  RESULTS+=("WARN|$1|$2")
  $QUIET || echo -e "  ${YELLOW}[WARN]${NC} $1 — $2"
}

# ── 获取 sshd 配置值 ──
get_sshd_config() {
  local key="$1"
  # 优先从 sshd_config.d 读取（OpenSSH 8.x+ 推荐方式）
  local val=""
  if [[ -d /etc/ssh/sshd_config.d ]]; then
    val=$(grep -ri "^${key}" /etc/ssh/sshd_config.d/ 2>/dev/null \
          | tail -1 | awk '{print $2}' || true)
  fi
  if [[ -z "$val" ]] && [[ -f /etc/ssh/sshd_config ]]; then
    val=$(grep -i "^${key}" /etc/ssh/sshd_config 2>/dev/null \
          | tail -1 | awk '{print $2}' || true)
  fi
  echo "$val"
}

# ── 检查命令是否存在 ──
has_cmd() { command -v "$1" &>/dev/null; }

# ============================================================================
echo -e "\n${BOLD}${CYAN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║   SSH 安全基线审计 — ssh-audit.sh v1.0           ║${NC}"
echo -e "${BOLD}${CYAN}║   配套：《SSH 纵深加固》电子书                    ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════╝${NC}"
echo -e "  审计时间: $(date '+%Y-%m-%d %H:%M:%S %Z')\n"

# ── 0. 前置检查 ──
echo -e "${BOLD}[0] 前置检查${NC}"
if [[ $EUID -ne 0 ]]; then
  echo -e "  ${RED}[ERROR]${NC} 需要 root 权限运行此脚本"
  exit 1
fi

if ! has_cmd sshd; then
  check_fail "OpenSSH 安装" "sshd 未找到，请先安装 openssh-server"
  echo -e "\n${RED}审计中止：OpenSSH 未安装${NC}"
  exit 1
fi

SSHD_VERSION=$(sshd -V 2>&1 | head -1 || ssh -V 2>&1 | head -1 || echo "unknown")
check_pass "OpenSSH 安装" "$SSHD_VERSION"

# ── 1. 认证层审计 ──
echo -e "\n${BOLD}[1] 认证层审计${NC}"

# 1.1 密码认证
val=$(get_sshd_config "PasswordAuthentication")
if [[ "$val" == "no" ]]; then
  check_pass "密码认证" "已禁用 (PasswordAuthentication no)"
elif [[ -z "$val" ]]; then
  check_warn "密码认证" "未显式设置（默认值可能因发行版而异）"
else
  check_fail "密码认证" "仍然启用 (PasswordAuthentication $val)"
fi

# 1.2 root 登录
val=$(get_sshd_config "PermitRootLogin")
if [[ "$val" == "no" ]]; then
  check_pass "Root 登录" "已禁用 (PermitRootLogin no)"
elif [[ "$val" == "prohibit-password" ]]; then
  check_warn "Root 登录" "仅禁止密码登录，仍允许密钥登录 (prohibit-password)"
elif [[ -z "$val" ]]; then
  check_warn "Root 登录" "未显式设置（建议设为 no）"
else
  check_fail "Root 登录" "仍然允许 (PermitRootLogin $val)"
fi

# 1.3 公钥认证
val=$(get_sshd_config "PubkeyAuthentication")
if [[ "$val" == "yes" ]] || [[ -z "$val" ]]; then
  check_pass "公钥认证" "已启用"
else
  check_fail "公钥认证" "未启用 (PubkeyAuthentication $val)"
fi

# 1.4 空密码
val=$(get_sshd_config "PermitEmptyPasswords")
if [[ "$val" == "no" ]] || [[ -z "$val" ]]; then
  check_pass "空密码" "已禁止"
else
  check_fail "空密码" "仍然允许 (PermitEmptyPasswords $val)"
fi

# 1.5 MaxAuthTries
val=$(get_sshd_config "MaxAuthTries")
if [[ -n "$val" ]] && [[ "$val" -le 5 ]]; then
  check_pass "MaxAuthTries" "已设置为 $val (≤5)"
elif [[ -z "$val" ]]; then
  check_warn "MaxAuthTries" "未显式设置（默认 6，建议设为 3-5）"
else
  check_fail "MaxAuthTries" "设置过大 ($val)，建议 ≤5"
fi

# 1.6 LoginGraceTime
val=$(get_sshd_config "LoginGraceTime")
if [[ -n "$val" ]]; then
  # 转换为秒比较
  seconds="$val"
  if [[ "$val" =~ ^[0-9]+m$ ]]; then
    seconds=$(( ${val%m} * 60 ))
  fi
  if [[ "$seconds" -le 60 ]]; then
    check_pass "LoginGraceTime" "已设置为 $val (≤60s)"
  else
    check_fail "LoginGraceTime" "设置过长 ($val)，建议 ≤60s"
  fi
else
  check_warn "LoginGraceTime" "未显式设置（默认 120s，建议设为 30-60）"
fi

# ── 2. 密码学审计 ──
echo -e "\n${BOLD}[2] 密码学审计${NC}"

# 2.1 协议版本
val=$(get_sshd_config "Protocol")
if [[ "$val" == "1" ]]; then
  check_fail "SSH 协议" "使用 v1（极不安全，必须使用 v2）"
else
  check_pass "SSH 协议" "v2（OpenSSH 7.4+ 已移除 v1 支持）"
fi

# 2.2 弱加密算法检查
weak_ciphers="3des-cbc ariacbc aes128-cbc aes192-cbc aes256-cbc"
for cipher in $weak_ciphers; do
  if sshd -T 2>/dev/null | grep -qi "ciphers.*${cipher}"; then
    check_fail "弱加密算法" "发现已启用的弱 cipher: $cipher"
  fi
done
# 检查是否使用了推荐的现代 cipher
if sshd -T 2>/dev/null | grep -qi "chacha20-poly1305\|aes.*-gcm"; then
  check_pass "现代加密算法" "已启用 ChaCha20-Poly1305 或 AES-GCM"
else
  check_warn "现代加密算法" "未检测到推荐的 ChaCha20-Poly1305/AES-GCM"
fi

# 2.3 弱 MAC 算法
if sshd -T 2>/dev/null | grep -qi "macs.*hmac-md5\|macs.*hmac-sha1-96\|macs.*hmac-md5-96"; then
  check_fail "弱 MAC 算法" "发现已启用的弱 MAC (MD5/96-bit)"
else
  check_pass "弱 MAC 算法" "未检测到弱 MAC 算法"
fi

# 2.4 HostKey 类型
if sshd -T 2>/dev/null | grep -qi "hostkeyalgorithms.*ssh-ed25519\|hostkeyalgorithms.*rsa-sha2"; then
  check_pass "HostKey 算法" "使用 Ed25519 或 RSA-SHA2"
else
  check_warn "HostKey 算法" "未检测到推荐的 Ed25519/RSA-SHA2 算法"
fi

# ── 3. 网络层审计 ──
echo -e "\n${BOLD}[3] 网络层审计${NC}"

# 3.1 SSH 端口
val=$(get_sshd_config "Port")
if [[ -z "$val" ]] || [[ "$val" == "22" ]]; then
  check_warn "SSH 端口" "使用默认端口 22（改端口是卫生措施，不是安全屏障）"
else
  check_pass "SSH 端口" "已更改为 $val"
fi

# 3.2 X11Forwarding
val=$(get_sshd_config "X11Forwarding")
if [[ "$val" == "no" ]] || [[ -z "$val" ]]; then
  check_pass "X11 转发" "已禁用"
else
  check_fail "X11 转发" "仍然启用 (X11Forwarding $val)"
fi

# 3.3 TCP 转发
val=$(get_sshd_config "AllowTcpForwarding")
if [[ "$val" == "no" ]]; then
  check_pass "TCP 转发" "已禁用"
elif [[ -z "$val" ]]; then
  check_warn "TCP 转发" "未显式设置（默认允许，建议按需求禁用）"
else
  check_warn "TCP 转发" "已启用 (AllowTcpForwarding $val)"
fi

# 3.4 LogLevel
val=$(get_sshd_config "LogLevel")
if [[ "$val" == "VERBOSE" ]] || [[ "$val" == "DEBUG" ]]; then
  check_pass "日志级别" "已设置为 $val（适合安全审计）"
elif [[ -z "$val" ]] || [[ "$val" == "INFO" ]]; then
  check_warn "日志级别" "当前为 $val（建议设为 VERBOSE 以记录密钥指纹）"
else
  check_warn "日志级别" "当前为 $val"
fi

# ── 4. 主动防护审计 ──
echo -e "\n${BOLD}[4] 主动防护审计${NC}"

# 4.1 fail2ban
if has_cmd fail2ban-client; then
  if fail2ban-client status sshd &>/dev/null || fail2ban-client status ssh &>/dev/null; then
    check_pass "fail2ban" "已安装且 SSH jail 已激活"
  else
    check_warn "fail2ban" "已安装但 SSH jail 未激活"
  fi
else
  check_warn "fail2ban" "未安装（建议部署 fail2ban 或 CrowdSec）"
fi

# 4.2 CrowdSec
if has_cmd cscli; then
  if cscli hub list 2>/dev/null | grep -qi "crowdsecurity/sshd"; then
    check_pass "CrowdSec" "已安装且 SSH 场景已启用"
  else
    check_warn "CrowdSec" "已安装但 SSH 场景未启用"
  fi
fi

# ── 5. 入侵检测审计 ──
echo -e "\n${BOLD}[5] 入侵检测审计${NC}"

# 5.1 auditd
if has_cmd auditctl; then
  if auditctl -l 2>/dev/null | grep -qi "ssh\|sshd"; then
    check_pass "auditd SSH 规则" "已配置 SSH 相关审计规则"
  else
    check_warn "auditd SSH 规则" "auditd 已安装但未配置 SSH 审计规则"
  fi
else
  check_warn "auditd" "未安装（建议部署 auditd 用于 SSH 会话审计）"
fi

# 5.2 文件完整性监控
for fim in aide tripwire samhain; do
  if has_cmd "$fim"; then
    check_pass "文件完整性监控" "$fim 已安装"
    break
  fi
done

# ── 6. 密钥审计 ──
echo -e "\n${BOLD}[6] 主机密钥审计${NC}"

for keyfile in /etc/ssh/ssh_host_*_key; do
  [[ -f "$keyfile" ]] || continue
  keytype=$(ssh-keygen -lf "$keyfile" 2>/dev/null || echo "unknown")
  basename_key=$(basename "$keyfile")

  # 检查密钥类型
  if [[ "$keyfile" == *"_rsa_key" ]]; then
    bits=$(ssh-keygen -lf "$keyfile" 2>/dev/null | awk '{print $1}')
    if [[ -n "$bits" ]] && [[ "$bits" -ge 4096 ]]; then
      check_pass "RSA 主机密钥 ($basename_key)" "${bits} 位 (≥4096)"
    elif [[ -n "$bits" ]]; then
      check_warn "RSA 主机密钥 ($basename_key)" "${bits} 位（建议 ≥4096 或迁移到 Ed25519）"
    fi
  elif [[ "$keyfile" == *"_ed25519_key" ]]; then
    check_pass "Ed25519 主机密钥 ($basename_key)" "已配置（推荐）"
  elif [[ "$keyfile" == *"_ecdsa_key" ]]; then
    check_warn "ECDSA 主机密钥 ($basename_key)" "存在（ECDSA 有 NIST 曲线信任问题，建议优先 Ed25519）"
  elif [[ "$keyfile" == *"_dsa_key" ]]; then
    check_fail "DSA 主机密钥 ($basename_key)" "DSA 已废弃，请立即删除"
  fi
done

# ── 汇总报告 ──
echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════════════${NC}"
echo -e "${BOLD}审计结果汇总${NC}"
echo -e "  ${GREEN}通过 (PASS): $PASS${NC}"
echo -e "  ${RED}失败 (FAIL): $FAIL${NC}"
echo -e "  ${YELLOW}警告 (WARN): $WARN${NC}"
TOTAL=$((PASS + FAIL + WARN))
if [[ $TOTAL -gt 0 ]]; then
  SCORE=$(( (PASS * 100) / TOTAL ))
  echo -e "  安全评分: ${BOLD}${SCORE}%${NC}"
fi
echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════${NC}"

# ── JSON 输出 ──
if $JSON_OUT; then
  echo -e "\n{"
  echo "  \"timestamp\": \"$(date -Iseconds)\","
  echo "  \"sshd_version\": \"$SSHD_VERSION\","
  echo "  \"summary\": {\"pass\": $PASS, \"fail\": $FAIL, \"warn\": $WARN},"
  echo "  \"results\": ["
  for i in "${!RESULTS[@]}"; do
    IFS='|' read -r status check detail <<< "${RESULTS[$i]}"
    comma=","
    [[ $i -eq $((${#RESULTS[@]} - 1)) ]] && comma=""
    echo "    {\"status\": \"$status\", \"check\": \"$check\", \"detail\": \"$detail\"}$comma"
  done
  echo "  ]"
  echo "}"
fi

# ── 退出码 ──
if [[ $FAIL -gt 0 ]]; then
  echo -e "\n${RED}发现 $FAIL 项不合规，请尽快修复。${NC}"
  echo -e "参考：https://leisurelinux.github.io/ebook-ssh-hardening/"
  exit 1
else
  echo -e "\n${GREEN}所有检查项通过或仅有警告。${NC}"
  exit 0
fi
