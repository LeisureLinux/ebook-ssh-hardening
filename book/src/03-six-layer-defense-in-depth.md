# 六层纵深防御体系

这一章是全文的核心。我们把 SSH 防御抽象成六层，自外而内、自网络到应用、自预防到响应。**每一层都假设上一层已经失守**，只有这样才能真正实现纵深。

```text
第 1 层：减少暴露面   — 让攻击者根本找不到你
第 2 层：认证加固     — 让攻击者即便找到了也进不来
第 3 层：访问控制     — 让攻击者即便进来了也不能随便做事
第 4 层：主动阻断     — 让攻击者反复尝试时付出代价
第 5 层：入侵检测     — 让攻击者已经进来了能被我们看到
第 6 层：审计与响应   — 让攻击者造成的损失可追溯、可止血
```

## 第 1 层：减少暴露面

减少暴露面是性价比最高的一层——攻击者扫不到你，后面所有的攻击手段都用不上。

### 防火墙最小化：nftables/iptables 的设计哲学

**防火墙最小化原则**：默认拒绝所有流量，仅放行业务需要的。这条原则在 SSH 防御里体现得最明显。

```bash
# nftables 示例：仅允许来自 10.0.0.0/8 内网的 SSH
nft add rule inet filter input ip saddr 10.0.0.0/8 tcp dport 22 accept
nft add rule inet filter input tcp dport 22 drop

# iptables 等价写法
iptables -A INPUT -p tcp --dport 22 -s 10.0.0.0/8 -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j DROP
```

**性能考量**：

- 在 10Gbps+ 的网络下，**iptables 的线性规则匹配**会成为瓶颈——每秒百万级包处理时，每多一条规则就多一次匹配

- **nftables 改进了**：用 nft 的集合（set）+ 哈希查找，规则量大时性能显著优于 iptables

- **ipset + iptables** 是另一种思路：把大量 IP 放在 ipset 哈希表里，单条 iptables 规则就能匹配整个集合

**位置策略**：

- **云主机**：在**安全组（Security Group）**层限制，这是最外层、最有效的

- **系统层**：在 OS 的 nftables/iptables 加一层兜底

- **网络层**：在 VPC 防火墙、SDN 控制器层再加一层

**纵深**：单层防火墙再严，仍然存在误配置风险——多层级联才能保证"一处失守、处处拦截"。

### 端口变更的真实收益

这一层最容易做错——很多人以为"改了端口就安全了"。前面我们量化过，**改端口能挡掉 95%+ 的扫描噪声，但挡不住定向攻击**。收益点在于：

- **降低日常告警噪声**：让 fail2ban、SIEM 不被淹没，能专注真正的异常

- **避免被自动 bot 列入"易得目标"**：很多 bot 见到非 22 端口直接跳过

- **赢得响应时间**：定向扫描需要时间，给运维更多反应窗口

我的推荐：**改端口是卫生习惯，应当做；但同时必须叠加认证加固**。改端口 + 密码认证 = 还是不安全；改端口 + 仅密钥认证 + 多因素 = 接近合理的默认配置。

### SSH over HTTPS / WebSocket

这是一个比较"硬核"的做法：**把 SSH 流量隐藏在 HTTPS 端口（443）后面**。思路是：

- 用 **stunnel**（stunnel.org）把 SSH 流量封装在 TLS 里，从外部看是 HTTPS

- 或者用 **websocketd**、**ssh-over-websocket**（GitHub: `vi/websocat`）把 SSH 包在 WebSocket 协议里，再走 HTTPS

**收益**：

- 在受限网络（如只能出 443 的环境）下仍能访问

- 让扫描器无法通过 banner 识别 SSH

- 配合反代（nginx + stream 模块）可以做更复杂的访问控制

**代价**：

- 性能开销：TLS 加密 + WebSocket 帧 = 10-20% 的吞吐量损失

- 配置复杂度高

- 真正的安全性并不提升（如果后端 sshd 还是密码认证 + 弱口令，照样被攻破）

**什么时候用**：适合**穿透企业防火墙**或**网络环境严苛**的场景，不适合一般业务。

### VPN / 堡垒机前置

**经典架构**：

```text
公网 ──VPN──> 堡垒机 ──> 目标服务器
```

SSH 端口完全不对公网暴露，攻击者只能看到 VPN 服务器的入口。VPN 自身的口令/证书 + 双因素 + 集中审计，比单台 SSH 服务器安全得多。

**优势**：

- SSH 服务"完全隐身"——除非先破 VPN

- 所有访问经过堡垒机，可做会话录像

- 集中化的认证、授权、审计

**经典开源堡垒机**：

- **Teleport**（goteleport.com）—— 开源版免费，企业版收费

- **Apache Guacamole**（guacamole.apache.org）—— 客户端 HTML5，免插件

- **Bastillion**（GitHub: `bastillion-io/Bastillion`）—— 轻量级堡垒机

**架构选型**：

- 小团队（< 50 人）：Teleport 开源版 + 单机部署

- 中型企业（50-500 人）：Teleport 企业版或 JumpServer

- 大型企业：商业方案 + 自建 PKI

### Cloudflare Tunnel / Tailscale SSH 的零暴露方案

这是 2020 年后的"新派"做法：**让 SSH 完全不出现在公网**。

**Cloudflare Tunnel**（developers.cloudflare.com/cloudflare-one/connections/connect-networks/）
- 在服务器上跑一个 `cloudflared` 守护进程

- 它向 Cloudflare 边缘节点**主动建立出站连接**（无需公网入站规则）

- 外部用户通过 Cloudflare 的 Zero Trust 策略访问

- **SSH 服务端口完全不对外暴露**——这是"零暴露"的最纯粹实现

**Tailscale SSH**（tailscale.com/ssh）
- 基于 WireGuard 的 mesh 网络

- 节点之间组成 overlay network

- Tailscale SSH 让节点间通过 Tailnet 内的身份认证访问，无需传统 SSH 凭据

- **完全跳过公网 SSH 端口**——同时跳过端口转发、防火墙配置的麻烦

**对比传统方案的革命性**：

- 传统方案：暴露端口 + 防火墙限制来源 + 强认证

- 新方案：**完全不暴露端口**——攻击者扫描全网都找不到你

**成本**：

- Cloudflare Tunnel：免费版有带宽限制，企业版 $5/月起

- Tailscale SSH：个人免费，企业按节点收费

**适用场景**：

- Cloudflare Tunnel：已用 Cloudflare 服务的中小企业

- Tailscale SSH：DevOps 团队、远程办公、跨云连接

**缺点**：

- 引入第三方依赖（Cloudflare/Tailscale 公司本身）

- 网络延迟可能增加（流量要绕道）

- 配置复杂度上升——小型团队需要学习成本

我的建议：**新项目优先考虑这套方案**，老项目逐步迁移。它代表 SSH 防御的未来方向。

## 第 2 层：认证加固

这一层是整个纵深防御体系的**核心中的核心**。无论前面几层做得多好，认证层一旦失守，前面全白搭。

### 密码认证为什么永远不够强

先讲原理：**密码认证本质上是一个"共享秘密"机制**。

服务器存储密码的哈希（理想情况下是 bcrypt/scrypt/Argon2），用户输入密码后，客户端发到服务器，服务器哈希比对。整个过程里：

- **密码必须通过网络传输**（即便 TLS 加密，攻击者仍然能拿到加密后的密文进行重放，除非协议本身有 challenge-response）

- **服务器端必须有"可还原"的验证信息**——哪怕是哈希，也存在被拖库后离线破解的可能

- **密码必须人能记住**——决定了它的熵不会太高（人类密码熵通常 30-40 bit，远低于 128 bit 的安全标准）

**密码的熵从哪来**？假设攻击者知道字典大小为 N，密码平均长度 L，那么攻击成本是 N 的 L 次方。但实际上：

- 90% 的用户密码都在 top10k 字典内（NTNU 2017 密码学研究）

- 80% 的用户密码在 5 个以内网站复用（LastPass 心理研究）

- 字典攻击实际成本远低于理论值

**密码学结论**：密码认证的安全性上限受限于人类认知，无法达到密码学强认证的标准。**这是数学决定的，不是工程能解决的**。

### 密钥认证原理：非对称加密 + 挑战-响应

SSH 密钥认证是另一种思路：**用密码学难题替代共享秘密**。

**核心流程**（简化版）：

```text
1. 用户生成密钥对：私钥（client 保留）+ 公钥（放到服务器的 authorized_keys）
2. 客户端连接时，服务器生成一个随机数（challenge）
3. 客户端用私钥对这个随机数签名
4. 服务器用预存的公钥验证签名
5. 验证通过 = 认证成功
```

**为什么这样安全**：

- **私钥永远不出客户端**（除非显式导出）——服务器拿不到私钥

- 服务器上没有"可被拖库"的认证材料——公钥是公开的，拖走也没用

- 即便中间人截获签名，没有私钥也无法伪造

- 攻击者即便完全控制了服务器，也无法冒用客户端的身份

**密钥认证的"挑战-响应"特性**：这跟密码认证的"对比字符串"有本质区别——密码认证是"我说出秘密，证明我是谁"，密钥认证是"我证明我有私钥，但不泄露私钥"。前者是静态对比，后者是动态证明。**这种差异让密钥认证在抗重放、抗拖库、抗中间人上都更强**。

### 密钥类型深度对比：RSA、ECDSA、Ed25519

不是所有 SSH 密钥都生而平等。我们深入对比三种主流：

**RSA**（1977 年由 Ron Rivest、Adi Shamir、Leonard Adleman 提出）
- **数学原理**：基于大整数分解难题——给定 n = p × q（两个大素数相乘），从 n 反推 p 和 q 是计算上不可行的

- **推荐长度**：3072 bit（保守），4096 bit（极致安全）

- **性能**：签名慢，验证快（特别在小设备上）

- **历史地位**：30 年的事实标准，所有 SSH 实现都支持

- **缺点**：密钥体积大（3072 bit 对应 384 字节），量子计算威胁下不安全（Shor 算法能多项式时间分解大整数）

**ECDSA**（Elliptic Curve Digital Signature Algorithm）
- **数学原理**：基于椭圆曲线离散对数难题——给定曲线上的点 P 和 Q = kP，求 k 是计算上不可行的

- **常用曲线**：P-256（secp256r1）、P-384、P-521

- **性能**：签名快，验证快，密钥小（256 bit = 32 字节）

- **历史地位**：NIST 标准，主流 SSH 实现支持

- **缺点**：曲线选择有政治敏感性（dual-EC-DRAG 后门事件），需要可信随机数生成（历史上出现过 SONY PS3 随机数问题导致 ECDSA 私钥恢复的著名事故）

**Ed25519**（Bernstein 等 2011 年提出）
- **数学原理**：基于 Edwards 曲线上的 Schnorr 签名

- **性能**：**所有算法中最快**——签名、验证都比 RSA/ECDSA 快一个数量级

- **安全性**：128 bit 安全级别，没有已知的弱曲线问题

- **密钥大小**：公钥 32 字节、私钥 32 字节——极小

- **缺点**：相对较新（2011 年），但 OpenSSH 6.5+（2014 年）已支持，现在所有主流实现都支持

**实战推荐**：

```bash
# Ed25519（首选）
ssh-keygen -t ed25519 -a 100 -C "your_email@example.com"

# RSA（兼容性最佳）
ssh-keygen -t rsa -b 4096 -o -a 100 -C "your_email@example.com"

# ECDSA（次选）
ssh-keygen -t ecdsa -b 521 -C "your_email@example.com"
```

`-a 100` 参数的意思是对私钥进行 100 轮 KDF（Key Derivation Function）迭代，让暴力破解更困难（即便攻击者拿到加密的私钥文件）。

**不要使用**：DSA（已被淘汰）、1024 bit RSA（可被 NSA 等机构破解）、ECDSA-P-224/256 在不信任 NIST 时的备选。

### ssh-keygen 参数详解

深入理解每个参数的含义：

| 参数 | 含义 | 推荐值 / 说明 |
|------|------|---------------|
| `-t` | 算法类型 | `rsa` / `dsa` / `ecdsa` / `ed25519`，选择决定密钥长度、签名性能、安全性 |
| `-b` | 密钥长度（仅 RSA/DSA） | RSA 推荐 3072 或 4096 bit，不要低于 2048，密钥越长越安全但越慢 |
| `-C` | 注释 | 通常写 email 或用途，不影响安全，仅做标识 |
| `-f` | 输出文件路径 | 默认 `~/.ssh/id_<算法>` 或 `~/.ssh/id_ed25519`，可自定义 |
| `-a` | KDF 轮数（保护私钥） | 默认 16，OpenSSH 7.8+ 提升到 100，越大越难暴力破解但加解密越慢 |
| `-o` | 使用新的 OpenSSH 格式 | 旧版用 PEM，新版用 OpenSSH 专属格式（更紧凑、抗量子），**应当启用** |
| `-E` | 指纹哈希算法 | 默认 SHA-256（OpenSSH 6.8+），老版本可能默认 MD5，应避免 |
| `-N` | 私钥 passphrase（密码短语） | **强烈推荐设置**——即便私钥文件被偷，没有 passphrase 攻击者仍然不能直接用；私钥文件本身被对称加密 |

**实战命令**：

```bash
# 推荐的 Ed25519 生成
ssh-keygen -t ed25519 -a 100 -C "axu@leisurelinux.com" -f ~/.ssh/id_ed25519

# 多个密钥管理（不同用途）
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_work -C "work"
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_personal -C "personal"

# 在 ~/.ssh/config 中配置不同密钥
cat >> ~/.ssh/config << 'EOF'
Host work-server
    HostName work.example.com
    User axu
    IdentityFile ~/.ssh/id_ed25519_work

Host github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_personal
EOF
```

### from= 在 authorized_keys 中的安全语义

`authorized_keys` 是服务器端的信任列表，每行一个公钥。`from=` 参数用来限制**该公钥只能从特定 IP/域名登录**：

```bash
# 仅允许从公司 IP 网段登录
from="10.0.0.*,*.leisurelinux.com" ssh-ed25519 AAAA... user@host

# 多个 IP 用逗号分隔，支持通配符和 ? 匹配
from="*.internal,192.168.1.0/24" ssh-ed25519 AAAA...

# 注意：from= 不是 CIDR，是 glob 匹配，192.168.1.0/24 不会按预期工作
# 正确写法是逐段写：from="192.168.1.*"
```

**安全意义**：即便私钥泄露，攻击者也必须从指定 IP 登录——这等于加了一层网络层防护。

**注意**：

- `from=` 是"软限制"，可以用 DNS rebinding、IP 伪造等方式绕过（除非配合防火墙）

- 真正严格的做法是**同时在 sshd_config 和 iptables 层双重限制**

- `from=` 不是 CIDR 语法，是 glob 匹配——很多新手会搞错

### command= / forced-command 的滥用与防护

`authorized_keys` 中还能指定 `command=` 参数——**强制该公钥登录后只能执行特定命令**：

```bash
# 强制该公钥只能执行 backup 脚本
command="/usr/local/bin/backup.sh" ssh-ed25519 AAAA... backup-runner@host
```

**用途**：

- 给 CI/CD 系统一个只能跑特定脚本的密钥

- 给 SFTP 用户限制只能访问特定目录

- 给运维自动化一个无 shell 登录权限的密钥

**滥用风险**：

- 配置错误的 `command=` 可能被绕过（如 sshd 启动时 environment 设置、shell 启动文件执行）

- 早期 OpenSSH 版本有过 `command=` 被忽略的 bug

- 命令本身的权限过大——`command="cat /etc/passwd"` 就是灾难

**防护**：

- `command=` 必须配合 `no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty`

- 即便如此，**绝对不要用 `command=` 替代正常的用户权限管理**——它是一个补充，不是替代

**完整示例**：

```bash
# 安全的 CI/CD 密钥：仅允许备份命令，无任何 shell 能力
command="/usr/local/bin/run-backup.sh",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty ssh-ed25519 AAAA... ci-runner@ci.example.com
```

### 多密钥策略：个人密钥 vs 自动化密钥 vs 应急密钥

单一密钥有"单点失效"问题——一旦泄露，所有机器失守。**纵深原则要求密钥分层**：

**个人日常密钥**（高安全级）
- Ed25519 + 强 passphrase

- 设置 from= 限制登录 IP

- 配置定期轮换（建议每 6-12 个月）

- 配备 YubiKey 等硬件密钥（私钥永不落盘）

**自动化密钥**（CI/CD 专用）
- 单独生成，与个人密钥隔离

- 设置 command=、no-port-forwarding 等限制

- 集中存放在 Vault 等密钥管理系统

- 短有效期，配合签名证书（短期凭证）

**应急密钥**（保命用）
- 单独保管在离线介质（加密 USB、智能卡）

- 仅在主密钥失效时使用

- 配备单独的强 passphrase（不与其他密码共用）

- 一旦启用，立即重新评估所有其他密钥

**多密钥的 ssh config 管理**：

```bash
# ~/.ssh/config
Host *
    AddKeysToAgent yes
    HashKnownHosts yes

Host prod-*
    IdentityFile ~/.ssh/id_ed25519_work
    IdentitiesOnly yes
    User ops

Host emergency
    HostName emergency.leisurelinux.com
    IdentityFile ~/.ssh/id_ed25519_emergency
    User root
    # 这个 host 必须显式指定才能用
```

`IdentitiesOnly yes` 是关键——它强制 SSH **只用指定密钥尝试认证**，不会被 ssh-agent 里其他密钥干扰（避免被服务端用于 fingerprint 探测）。

## 第 3 层：访问控制

认证解决"是不是这个人"，访问控制解决"这个人能做哪些事"。

### AllowUsers / AllowGroups / DenyUsers 的语义陷阱

sshd_config 中这几个指令看似简单，实际上有微妙差异：

```bash
# 仅允许指定用户登录
AllowUsers axu alice bob

# 仅允许指定组的成员登录
AllowGroups ssh-users devops

# 拒绝指定用户（其他允许）
DenyUsers root admin test
```

**优先级陷阱**：

- `DenyUsers` 比 `AllowUsers` 优先级**更高**——一旦拒绝，即便在 AllowUsers 列表里也无效

- `AllowUsers` / `AllowGroups` 是"白名单"——只允许列表中的，其他全部拒绝

- `DenyUsers` 是"黑名单"——只拒绝列表中的，其他允许

- **不要混用**——白名单和黑名单混用会产生逻辑混乱

**语义陷阱**：

- `AllowUsers axu` 匹配的是**用户名**，不是 UID——用户名重复会被忽略

- `AllowGroups ssh-users` 匹配的是用户**主组**，不是附加组

- 不写 `AllowUsers` / `AllowGroups` = 不限制 = 默认全部允许

**最佳实践**：

```bash
# sshd_config 推荐配置
AllowGroups ssh-users wheel        # 仅这两个组的成员能 SSH 登录
PermitRootLogin no                  # 永远禁止 root 直接登录
MaxAuthTries 3                      # 最多 3 次认证尝试
LoginGraceTime 30                   # 30 秒内必须完成认证
MaxSessions 5                       # 每个连接最多 5 个会话
```

### 非 root 登录 + sudo 提权的纵深价值

**禁止 root SSH 登录**（`PermitRootLogin no`）是 SSH 安全的**最基本也是最重要**的配置之一。原因：

1. **用户名隐藏**：root 是已知用户名，攻击者无需枚举；如果 root 都不能登录，攻击者必须先猜出有效的普通用户名——难度翻倍
2. **审计粒度**：每个用户登录都有独立日志；root 直接登录让审计变成"是 root 干的"，但不知道是谁
3. **纵深**：攻击者拿到普通账号后还要提权，而提权本身就是一个防御层
4. **配置变更可追溯**：所有 sudo 操作都有日志，可以定位到具体用户

**sudo 的纵深配置**：

```bash
# /etc/sudoers（用 visudo 编辑！）
# 仅允许 wheel 组通过 sudo 提权
%wheel ALL=(ALL) ALL

# 强制记录所有 sudo 操作
Defaults log_host, log_year, logfile=/var/log/sudo.log

# 限制环境变量传递（防止 LD_PRELOAD 等攻击）
Defaults env_reset
Defaults secure_path = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# 限制 sudo 超时时间（避免忘记退出）
Defaults timestamp_timeout=5
```

**更严格的做法**：限制特定用户只能 sudo 执行特定命令：

```bash
# 让 ops 用户只能 sudo 重启服务
ops ALL=(root) /usr/bin/systemctl restart nginx, /usr/bin/systemctl status nginx

# 这样即便 ops 账号被攻破，攻击者也只能重启 nginx，不能 rm -rf /
```

### PAM 栈原理：SSH 如何通过 PAM 调用系统认证

**PAM（Pluggable Authentication Modules，可插拔认证模块）**是 Linux 认证体系的核心。SSH 并不直接做密码验证，它把认证委托给 PAM。

**PAM 栈的工作原理**：

```text
sshd 接收认证请求
  ↓
调用 PAM 库（libpam）
  ↓
按配置文件顺序加载 PAM 模块
  ↓
每个模块返回 success / failure / ignore
  ↓
最终结果返回给 sshd
```

**PAM 配置文件路径**：

- `/etc/pam.d/sshd` —— SSH 专用配置

- `/etc/pam.d/login` —— 本地登录

- `/etc/pam.d/common-auth` —— 通用认证（被多个服务 include）

**典型 sshd 的 PAM 配置**：

```text
# /etc/pam.d/sshd
auth       required   pam_env.so
auth       sufficient pam_unix.so nullok try_first_pass
auth       required   pam_deny.so

account    required   pam_unix.so
session    required   pam_limits.so
session    optional   pam_lastlog.so
```

**关键词含义**：

- `required`：失败则最终失败，但继续评估后续模块（防止用户知道具体哪一步失败）

- `requisite`：失败立即终止（明确报错）

- `sufficient`：成功则立即通过，跳过后续

- `optional`：无论成功失败都不影响最终结果

**UsePAM 的作用**：

```bash
# sshd_config
UsePAM yes   # 让 SSH 使用 PAM 栈（默认开启）
```

**关闭 UsePAM 的后果**：

- 不能用 PAM 模块（包括 2FA、密码策略、登录限制等）

- 只能依赖 sshd 内置的认证机制

- **生产环境必须开启**

### PAM 模块深度定制：pam_access、pam_listfile、pam_tally2

**pam_access**：基于主机/用户/域限制登录

```text
# /etc/security/access.conf
# 拒绝所有来自 evil.com 的用户
-:ALL EXCEPT root:evil.com

# 仅允许 wheel 组从特定网段登录
+:wheel:10.0.0.0/24
-:ALL:ALL
```

**pam_listfile**：基于文件列表限制（如禁止特定用户）

```text
# /etc/pam.d/sshd 增加：
auth required pam_listfile.so onerr=succeed item=user sense=deny file=/etc/ssh/banned_users
```

**pam_tally2 / pam_faillock**：登录失败计数器

```text
# 失败 5 次锁定 30 分钟
auth required pam_faillock.so preauth deny=5 unlock_time=1800
auth sufficient pam_unix.so nullok try_first_pass
auth required pam_faillock.so authfail deny=5 unlock_time=1800
```

**实战组合拳**：

```text
# 在 PAM 中实现：仅允许 ops 和 dev 组成员从内网登录，失败 3 次锁定
auth required pam_env.so
auth required pam_listfile.so item=group sense=allow file=/etc/ssh/allowed_groups onerr=fail
auth required pam_access.so accessfile=/etc/security/access.conf
auth required pam_faillock.so preauth deny=3 unlock_time=900 even_deny_root
auth sufficient pam_unix.so nullok try_first_pass
auth required pam_faillock.so authfail deny=3 unlock_time=900
auth required pam_deny.so
```

**注意**：在不同 Linux 发行版上 PAM 模块名略有差异，Debian/Ubuntu 用 `pam_tally2`，RHEL/CentOS 新版用 `pam_faillock`。

### UsePAM / ChallengeResponseAuthentication / KerberosAuthentication 的取舍

sshd_config 中几个认证相关的开关容易混淆：

```bash
UsePAM yes                       # 是否使用 PAM（默认 yes）
PasswordAuthentication no        # 是否允许密码认证（推荐 no）
ChallengeResponseAuthentication no  # 是否允许 challenge-response（如键盘交互式）
PubkeyAuthentication yes         # 是否允许密钥认证（推荐 yes）
KbdInteractiveAuthentication no   # 是否允许键盘交互认证（通常 no）
KerberosAuthentication no        # 是否使用 Kerberos（默认 no）
GSSAPIAuthentication no          # GSSAPI 认证（默认 no）
```

**典型误配置**：

- `PasswordAuthentication no` 但 `ChallengeResponseAuthentication yes` —— 攻击者仍然可以通过键盘交互式认证输入密码（绕过你的禁止密码设置）

- `PubkeyAuthentication no` 但 `PasswordAuthentication yes` —— 退化成密码认证

- `UsePAM no` —— 禁用所有 PAM 模块，2FA、限制等都失效

**安全推荐配置**：

```bash
# 仅密钥 + PAM（含可能的 2FA）
UsePAM yes
PubkeyAuthentication yes
PasswordAuthentication no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
KerberosAuthentication no
GSSAPIAuthentication no
```

### MaxAuthTries / LoginGraceTime / MaxSessions 的安全语义

```bash
MaxAuthTries 3           # 每个连接最多允许的认证尝试次数
LoginGraceTime 30        # 认证超时时间（秒）
MaxSessions 10           # 每个网络连接允许的会话数
MaxStartups 3:50:10      # 并发未认证连接数限制
ClientAliveInterval 300  # 空闲超时（秒）
ClientAliveCountMax 2    # 多少次空闲探测后断开
```

**安全语义**：

- **MaxAuthTries 3**：每次连接允许最多 3 次失败，超过就断开。这限制了**单连接**的暴力破解速率

- **LoginGraceTime 30**：30 秒内未完成认证则断开。这防止攻击者慢速扫描"测探"协议细节

- **MaxSessions 10**：一个 SSH 连接最多开启 10 个会话（通道复用）。限制过大可能让攻击者用一条连接跑很多操作

- **MaxStartups 3:50:10**：未认证连接数限制。"3:50:10" 表示开始 3 个，后续每多一个连接增加 50% 概率拒绝，达到 10 个时全部拒绝。这防止 SYN flood

- **ClientAliveInterval + ClientAliveCountMax**：超时断开闲置连接

**注意**：

- MaxAuthTries **是每连接的次数**，不是每 IP 的总数——分布式攻击不会触发

- LoginGraceTime 太短会让网络慢的用户认证失败

- MaxSessions 限制太严格会影响多路复用

## 第 4 层：主动阻断

即便认证加固做得再好，攻击者还是会反复尝试。我们需要**主动阻断**让攻击者付出代价。

### fail2ban 的原理：日志正则 + 防火墙联动

**fail2ban**（fail2ban.org）是 SSH 防护的事实标准之一。它的原理很简单：

```text
1. 监控日志文件（/var/log/secure、/var/log/auth.log）
2. 用正则表达式匹配失败登录
3. 累计失败次数达到阈值 → 调用防火墙封禁 IP
4. 一段时间后解封
```

**核心组件**：

- **jail**：定义"监控哪个日志、匹配什么正则、阈值多少、封禁多久"

- **filter**：正则表达式集合（一个 filter 对应一种攻击模式）

- **action**：封禁动作（iptables / nftables / hostsdeny / 邮件通知 / 自定义脚本）

**默认 SSH jail 配置**（`/etc/fail2ban/jail.conf` 或 `jail.local`）：

```ini
[DEFAULT]
# 5 次失败封禁 1 小时
bantime  = 1h
findtime = 10m
maxretry = 5

# 忽略自己
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled = true
port    = ssh
filter  = sshd
logpath = %(sshd_log)s
backend = %(sshd_backend)s
```

### fail2ban 深度配置

**recidive 监狱**：防止"被解封后立刻回来"

```ini
[recidive]
enabled  = true
filter   = recidive
logpath  = /var/log/fail2ban.log
bantime  = 1w
findtime = 1d
maxretry = 5
# recidive 会扫描 fail2ban 自己的日志，看哪些 IP 多次被封
# 多次被封的 IP → 长期封禁
```

**bantime.increment**：渐进式封禁时长

```ini
[DEFAULT]
bantime.increment = true
# 第一次封禁 1 小时，第二次 2 小时，第三次 4 小时...指数增长
# 攻击者持续尝试的成本指数上升
```

**ignoreip 的合理使用**：

```ini
# 忽略可信 IP（公司出口、堡垒机、监控 IP）
ignoreip = 127.0.0.1/8 ::1 10.0.0.0/8 192.168.0.0/16 1.2.3.4
```

**自定义 SSH filter**：默认的 sshd filter 可能漏掉一些攻击模式，可以扩展：

```ini
# /etc/fail2ban/filter.d/sshd-custom.conf
[Definition]
failregex = ^%(__prefix_line)sFailed \S+ for invalid user \S+ from <HOST> port \d+ ssh2$
            ^%(__prefix_line)sConnection closed by authenticating user \S+ <HOST> port \d+
            ^%(__prefix_line)sInvalid user \S+ from <HOST>
            ^%(__prefix_line)sDid not receive identification string from <HOST>
            ^%(__prefix_line)sConnection reset by <HOST>

ignoreregex =
```

### CrowdSec 的架构升级：去中心化威胁情报

fail2ban 的局限很明显：它是单机决策，没有跨机器的情报共享。**CrowdSec**（crowdsec.net）就是为了解决这个问题。

**CrowdSec 的核心创新**：

```text
本地检测 → 决策（ban）→ 上报攻击者 IP 到中心
                                    ↓
                          其他 CrowdSec 实例同步该 IP
                                    ↓
                          全网共享威胁情报
```

**架构组件**：

- **Agent（本地代理）**：每台机器运行，分析本地日志

- **Local API（LAPI）**：本地 API，存储本地的 ban 决策

- **Central API（CAPI）**：CrowdSec 官方中心 API，跨社区共享威胁情报

- **Bouncers**：执行 ban 动作（iptables、nginx、Cloudflare 等）

**与传统 fail2ban 的对比**：

| 维度 | fail2ban | CrowdSec |
|---|---|---|
| 决策范围 | 单机 | 单机 + 跨机器 |
| 威胁情报 | 无 | CAPI 共享 |
| 扩展性 | 中等 | 高（多语言 parser） |
| 性能开销 | 低 | 中等（Go 重写） |
| 社区生态 | 大 | 快速增长 |
| 学习曲线 | 低 | 中等 |

**适用场景**：

- 单机/小团队：fail2ban 足够

- 多机器/中型企业：CrowdSec 显著优于 fail2ban

- 跨地域/多云：CrowdSec + CAPI 是最优解

### SSH 黑名单订阅

除了 fail2ban/CrowdSec 的"自动检测"，还可以**主动订阅已知恶意 IP 的黑名单**：

- **FireHOL**（firehol.org）：整合了 30+ 个公开黑名单的 curated 列表

- **Spamhaus DROP/EDROP**：Spamhaus 维护的"don't route or peer"列表，针对已知恶意 IP

- **Emerging Threats**（rules.emergingthreats.net）：ET 维护的 compromised/blocked IP 列表

- **AbuseIPDB**（abuseipdb.com）：社区上报的恶意 IP

- **CINS Army**（cinsscore.com）：基于多源的恶意 IP 评分

**在 nftables 中订阅黑名单**：

```bash
#!/bin/bash
# /usr/local/bin/update-ssh-blacklist.sh

# 下载并合并黑名单
{
  curl -s https://iplists.firehol.org/files/firehol_level1.netset
  curl -s https://www.spamhaus.org/drop/drop.txt | awk '{print $1}'
} | sort -u > /tmp/ssh_blacklist.txt

# 用 nft set 替换
nft replace set inet filter ssh_blacklist "{ type ipv4_addr; flags interval; elements = { $(cat /tmp/ssh_blacklist.txt | tr '\n' ','); } }"

# 在 input chain 中 drop
nft add rule inet filter input ip saddr @ssh_blacklist drop
```

**注意**：订阅公开黑名单可能误伤（false positive）——某些 IP 可能被错误列入。要定期审查白名单。

### iptables vs nftables 在 fail2ban 中的性能与特性对比

**iptables 现状**：

- 老牌、文档丰富、绝大多数运维熟悉

- 单机规则数 < 1 万条时性能良好

- 大量规则时**线性匹配**导致性能下降

- ipset 解决了部分性能问题（哈希集合）

**nftables 现状**：

- iptables 的下一代，由同团队开发

- 内置集合（set）+ 哈希查找，大规则集性能优势明显

- 语法更现代、支持原子替换

- 与 RHEL 8+ / Debian 10+ / Ubuntu 20.04+ 集成良好

**性能数据**（来自 nftables 官方 benchmark）：

- 1 万条规则：iptables ≈ nftables

- 10 万条规则：nftables 比 iptables 快 5-10 倍

- 100 万条规则：nftables 优势更明显

**fail2ban 的选择建议**：

- < 1000 个被封 IP：iptables + ipset 足够

- 1000-100000 个被封 IP：nftables 更优

- > 100000 个被封 IP：考虑使用 ipset/nft set 的 hash 模式而非 bitmap

### ipset 在大规模封禁中的优势

**ipset**（ipset.netfilter.org）是 iptables 的扩展，用于管理大量 IP/CIDR/port 集合：

```bash
# 创建 hash:net 类型集合（IPv4 网段）
ipset create ssh_blacklist hash:net hashsize 4096 maxelem 100000

# 添加 IP 到集合
ipset add ssh_blacklist 1.2.3.0/24

# iptables 引用集合（单条规则处理整个集合）
iptables -A INPUT -m set --match-set ssh_blacklist src -j DROP
```

**优势**：

- 单条 iptables 规则匹配整个集合（哈希查找 O(1)）

- 支持自动过期（timeout 参数）

- 支持多类型（hash:ip、hash:net、hash:port、hash:mac 等）

**nftables 等价**：

```bash
# 创建集合
nft add set inet filter ssh_blacklist "{ type ipv4_addr; flags interval; }"

# 添加 IP
nft add element inet filter ssh_blacklist { 1.2.3.4, 5.6.7.0/24 }

# 引用
nft add rule inet filter input ip saddr @ssh_blacklist drop
```

**实战推荐**：在大型生产环境，用 ipset 或 nftables 的 set 管理 fail2ban/CrowdSec 的封禁列表。

## 第 5 层：入侵检测

前四层是"挡住攻击者"，第五层是"看到攻击者"——即便所有防线都失败，攻击者开始行动了，我们要能立刻知道。

### auditd 的内核机制：Linux Audit Subsystem 原理

**auditd**（Linux Audit Subsystem）是 Linux 内核级的审计框架，它能记录**细粒度**的系统调用和文件访问。

**核心原理**：

```text
用户态程序（ls, cat, sshd）
  ↓
系统调用（execve, open, read, write）
  ↓
内核 Audit 子系统
  ↓
匹配规则 → 生成事件
  ↓
用户态 auditd 写入 /var/log/audit/audit.log
```

**关键能力**：

- 记录**谁**在**什么时候**对**什么文件**做了什么操作

- 监控**系统调用**（execve, open, connect, setuid 等）

- 监控**文件路径**（用 watch 规则）

- 监控**系统调用参数**（如 connect 的目标地址）

### SSH 关键审计事件

**与 SSH 相关的 audit 事件**：

- **login**：用户登录事件
  ```
  type=USER_LOGIN msg=audit(1234567890.123:456): user pid=1234 uid=0 auid=1000 ...
  ```
- **auth**：认证尝试
  ```
  type=USER_AUTH msg=audit(...): user pid=... uid=... auid=... ...
  ```
- **pam**：PAM 模块调用
  ```
  type=USER_CMD msg=audit(...): user pid=... auid=... cmd=...
  ```
- **key_load**：SSH 密钥加载
  ```
  type=CRYPTO_KEY_USER msg=audit(...): user pid=... auid=... ...
  ```
- **execve**：命令执行
  ```
  type=EXECVE msg=audit(...): argc=2 a0="bash" a1="script.sh"
  ```
- **socket_connect**：网络连接（SSH 反向隧道检测）

**audit 规则示例**（`/etc/audit/rules.d/audit.rules`）：

```bash
# 监控 SSH 配置文件
-w /etc/ssh/sshd_config -p wa -k sshd_config
-w /etc/ssh/ssh_config -p wa -k ssh_config
-w /etc/ssh/ssh_host_ -p wa -k ssh_host_keys
-w /root/.ssh -p wa -k root_ssh_keys

# 监控用户 SSH 目录
-w /home/%u/.ssh -p wa -k user_ssh_keys

# 监控 sshd 可执行文件
-w /usr/sbin/sshd -p x -k sshd_exec

# 监控可疑命令
-w /usr/bin/wget -p x -k wget
-w /usr/bin/curl -p x -k curl
-w /bin/nc -p x -k netcat
-w /usr/bin/ssh -p x -k ssh_client

# 监控 systemd 服务创建
-w /etc/systemd -p wa -k systemd_config

# 监控 crontab
-w /etc/crontab -p wa -k crontab
-w /var/spool/cron -p wa -k crontab
```

### ausearch / aureport 在 SSH 取证中的应用

**ausearch**：搜索 audit 日志

```bash
# 查找某用户的 SSH 登录
ausearch -m USER_LOGIN -ua axu

# 查找最近 1 小时的 SSH 认证
ausearch -m USER_AUTH --start recent

# 查找 SSH 配置变更
ausearch -k sshd_config

# 查找所有 su/sudo 操作
ausearch -m USER_CMD
```

**aureport**：生成 audit 统计报告

```bash
# 登录统计
aureport -l

# 认证失败统计
aureport -au --failed

# 可疑命令统计
aureport -x --summary

# 按时间生成报告
aureport -t
```

**实战取证脚本**：

```bash
#!/bin/bash
# 当 SSH 被攻破时，第一时间收集证据
echo "=== 最近 24 小时登录用户 ==="
ausearch -m USER_LOGIN --start yesterday

echo "=== 最近 24 小时认证失败 ==="
ausearch -m USER_AUTH --start yesterday --failed

echo "=== 最近 24 小时所有执行的命令 ==="
ausearch -m EXECVE --start yesterday

echo "=== 可疑的关键命令 ==="
ausearch -m EXECVE --start yesterday | grep -E 'wget|curl|nc|ssh-keygen|nmap'
```

### 文件完整性监控：AIDE、Tripwire、Samhain 的差异

**AIDE**（Advanced Intrusion Detection Environment）
- 开源、广泛使用

- 基于文件哈希 + 属性的完整性检查

- 配置灵活，支持忽略规则

**Tripwire**（开源版 + 商业版）
- 经典 FIM（File Integrity Monitoring）工具

- 开源版功能受限，商业版功能完整

- 策略文件驱动

**Samhain**
- 跨平台（Linux/Unix/Windows）

- 支持集中管理（多个客户端 → 一个服务器）

- 内置完整性数据库签名

**三者的对比**：

| 维度 | AIDE | Tripwire | Samhain |
|---|---|---|---|
| 开源 | 是 | 仅开源版 | 是 |
| 集中管理 | 需自建 | 商业版支持 | 原生支持 |
| 性能 | 中等 | 中等 | 较好 |
| 学习曲线 | 中等 | 中等偏高 | 中等 |
| 适用场景 | 中小规模 | 中大规模 | 跨主机环境 |

**AIDE 的实战配置**：

```bash
# /etc/aide/aide.conf
/etc Full
/bin Full
/sbin Full
/usr/sbin Full
/etc/ssh Full
/root/.ssh Full
/home/.*/.ssh Full

# 初始化数据库
aide --init
mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db

# 定期检查
aide --check

# 配合 cron 定期跑
echo "0 3 * * * root /usr/bin/aide --check | mail -s 'AIDE Report' admin@example.com" > /etc/cron.d/aide
```

### 主机入侵检测：osquery、Wazuh、OSSEC 的架构对比

**osquery**（osquery.io）
- 把操作系统暴露成 SQL 表

- 用 SQL 查询系统状态、进程、网络、文件

- 跨平台（Linux/macOS/Windows）

- 由 Facebook 开源

- 适合实时监控、应急响应

**Wazuh**（wazuh.com）
- 基于 OSSEC 的现代 HIDS

- 完整的 SIEM 能力（日志聚合、告警、规则、可视化）

- 内置合规检查（PCI DSS、HIPAA、GDPR）

- 免费开源

**OSSEC**（ossec.net）
- 老牌开源 HIDS

- 文件完整性监控 + 日志分析 + rootkit 检测

- 客户端/服务器架构（C/S）

- Wazuh 的前身

**三者的架构对比**：

```text
osquery 架构：
  Agent（每台机器） → 本地 SQL 查询 / 推送到 Fleet 管理器
  ↓
  Fleet Manager（可选，osquery 出品的 Kolide Fleet 或商用 Uptycs 等）

Wazuh 架构：
  Agent（每台机器） → Indexer/OpenSearch → Dashboard
  ↓
  Server 集群（可选，多机 HA）

OSSEC 架构：
  Agent → Server（日志聚合、规则引擎、告警）
  ↓
  Server 生成告警（邮件/Syslog）
```

**选择建议**：

- **osquery**：技术驱动型团队、需要灵活查询、应急响应为主

- **Wazuh**：需要完整 SIEM、合规要求、多机器集中管理

- **OSSEC**：老牌稳定、资源占用小、小规模部署

### 异常登录检测：last、lastb、wtmp/btmp/utmp 的取证价值

Linux 中三个关键的日志文件：

- **/var/log/wtmp**：所有成功登录的记录（二进制）

- **/var/log/btmp**：所有失败登录的记录（二进制）

- **/var/run/utmp**：当前登录用户的信息（二进制）

**关键命令**：

```bash
# 最后 10 次成功登录
last -n 10

# 显示完整日期、IP
last -F -i

# 失败登录尝试
lastb -n 20

# 当前登录用户
who

# wtmp 中的所有登录
last -f /var/log/wtmp

# btmp 中的所有失败登录
lastb -f /var/log/btmp
```

**取证价值**：

- `wtmp` 不能轻易伪造（攻击者通常只清理日志，不清理二进制 wtmp——除非他知道怎么操作）

- `btmp` 是判断"暴力破解尝试次数"的最直接数据

- `last -i` 显示 IP，可以做地理分布分析

**注意**：攻击者往往会 `echo > /var/log/wtmp` 清空日志，或者用专用工具（如 utmpcleaner）伪造 wtmp 条目。**审计的最后防线是 auditd 的二进制日志 + 远程日志聚合**。

### Rootkit 检测：rkhunter、chkrootkit 的局限

**rkhunter**（rkhunter.sourceforge.net）
- 检查已知 rootkit 特征

- 检查文件/目录的异常属性（SUID、隐藏属性）

- 检查常见命令是否被替换（ls、ps、netstat）

**chkrootkit**（chkrootkit.org）
- 检查已知 rootkit

- 检查字符串异常

- 检查网络接口的 promiscuous 模式

**两者的局限**：

- **基于特征库**——对未公开 rootkit 完全失效

- **对内核级 rootkit 几乎无效**——LKM rootkit 可以 hook 系统调用，绕过一切用户态检测

- **高级攻击者会主动规避**——修改 rkhunter 的特征库、hook 系统调用、修改 ls 输出

**更强的 rootkit 检测**：

- **内核完整性检查**：用 Linux 的 IMA（Integrity Measurement Architecture）

- **离线扫描**：从另一个可信系统启动扫描

- **UEFI/固件级检查**：Secure Boot、TPM 远程证明

**实战建议**：

- rkhunter 和 chkrootkit 作为基础检查（每周跑一次）

- 但不要把它们当作"核心防御"——它们的真正价值是"发现粗心攻击者"

## 第 6 层：审计与响应

最后一层是**审计与响应**——即便前面所有层都被绕过，我们也要能快速发现、快速止血、快速复盘。

### 日志集中架构：rsyslog → ELK / Loki + Grafana

**为什么必须集中日志**：

- 攻击者拿到 root 后第一件事就是清理本地日志（`/var/log/secure`、`/var/log/wtmp`、`history`）

- 集中的日志在另一台机器上，攻击者清理不到

- 集中后才能做关联分析（一个用户的多台机器的 SSH 活动）

**架构选择**：

**ELK Stack**（Elasticsearch + Logstash + Kibana）
- 主流选择

- Elasticsearch 强查询能力

- Kibana 可视化强

- 资源占用大（每节点建议 16GB+ 内存）

**Loki + Grafana**
- Grafana Labs 出品

- 类似 Prometheus 的标签索引

- 资源占用小

- 适合云原生环境

**Vector + ClickHouse**
- 新派选择

- 高性能、低资源

- SQL 查询

**rsyslog 集中配置示例**：

```bash
# /etc/rsyslog.d/remote.conf（客户端）
# 把 auth 日志发到中心服务器
auth.* @@logserver.example.com:514

# /etc/rsyslog.conf（服务端）
# 接收远程日志
module(load="imtcp")
input(type="imtcp" port="514")

# 单独存储 SSH 认证日志
:inputname, contains, "sshd" /var/log/remote/sshd.log
```

**注意**：用 TLS 加密 rsyslog 传输，避免日志明文在网络上传输。

### SSH 日志关联分析

**单条日志的价值有限，关联才有价值**：

- 同一时间窗口内，登录成功 + 立即执行高危命令 → **高优先级告警**

- 同一用户从两个不同地理位置登录 → **中优先级告警（可能是 session 复用或账号被盗）**

- 登录失败 → 成功 → 大量下载文件 → **APT 渗透特征**

**典型关联查询（用 Splunk/ELK 语法示例）**：

```text
# 失败登录后短时间内成功登录
index=ssh "Failed password" | stats count by src_ip | where count > 5
| join src_ip type=inner [search index=ssh "Accepted password" OR "Accepted publickey"]

# 同一 src_ip 的失败-成功模式
index=ssh (Failed password OR Accepted *)
| transaction src_ip maxspan=5m
| where eventcount > 10
```

### SIEM 告警规则设计：如何减少误报

**告警疲劳（Alert Fatigue）**是 SIEM 失效的最常见原因——告警太多，运维麻木了，真正重要的信号被淹没。

**设计原则**：

- **少而精**：每个告警必须有明确的响应动作（playbook）

- **分级**：Critical / High / Medium / Low，每级有不同响应

- **抑制（Suppression）**：已知误报模式直接抑制

- **聚合（Aggregation）**：同一类型 1 分钟内多次只发一次

- **去重（Deduplication）**：相同的告警在 N 小时内只发一次

**SSH 高价值告警规则**：

```yaml
# Critical: 同一 IP 10 分钟内 50+ 失败登录
- name: SSH_BruteForce_High
  condition: ssh_failed_count > 50 within 10m grouped by src_ip
  action: alert + ban_ip

# High: 失败登录后立即成功（典型撞库成功）
- name: SSH_BruteForce_Success
  condition: ssh_failed_count > 5 within 5m AND ssh_success within 30s
  action: alert + investigate

# Medium: 凌晨 3-5 点登录
- name: SSH_Login_OffHour
  condition: ssh_success time between 03:00-05:00
  action: alert

# Medium: root 登录（应当被禁止）
- name: SSH_Root_Login
  condition: ssh_success user=root
  action: alert + investigate

# Low: 来自非常见国家的登录
- name: SSH_Login_NewGeo
  condition: ssh_success from new country for user
  action: alert
```

### 应急响应剧本

**SSH 服务器被入侵后的标准响应流程**：

**阶段 1：取证（保留证据）** —— 不要立刻重启或清理！
```bash
# 1. 拍摄内存（如果可能）
sudo apt install lime-forensics
sudo lime-forensics -o /mnt/usb/mem.dump

# 2. 复制关键日志
sudo tar czf /mnt/usb/logs.tgz /var/log/

# 3. 记录当前时间、活跃会话、网络连接
date
w
netstat -antp > /mnt/usb/netstat.txt
ps auxf > /mnt/usb/ps.txt

# 4. 复制 SSH 相关文件
sudo tar czf /mnt/usb/ssh.tgz /etc/ssh /root/.ssh /home/*/.ssh

# 5. 复制用户历史
sudo tar czf /mnt/usb/history.tgz /root/.bash_history /home/*/.bash_history

# 6. 复制 crontab 和 systemd 单元
sudo crontab -l > /mnt/usb/root_crontab.txt
sudo cp -r /etc/cron* /mnt/usb/
sudo cp -r /etc/systemd/system /mnt/usb/systemd_system
```

**阶段 2：隔离（切断入侵者访问）**
```bash
# 1. 阻断所有外部 SSH
sudo iptables -A INPUT -p tcp --dport 22 -j DROP
# 或者直接关闭 sshd
sudo systemctl stop sshd

# 2. 强制所有用户登出
sudo pkill -9 -u <compromised_user>

# 3. 封锁攻击者已知 IP
sudo iptables -A INPUT -s <attacker_ip> -j DROP
```

**阶段 3：修复（消除入侵路径）**
```bash
# 1. 修改所有 SSH 密钥对的 passphrase
# 2. 撤销所有 authorized_keys 中的可疑密钥
# 3. 轮换所有密码
# 4. 更新系统补丁
sudo apt update && sudo apt upgrade -y

# 5. 重新生成 SSH host key
sudo rm /etc/ssh/ssh_host_*
sudo ssh-keygen -A
sudo systemctl restart sshd

# 6. 检查所有 cron 和 systemd 服务是否有可疑项
sudo systemctl list-unit-files --state=enabled
```

**阶段 4：复盘（文档化教训）**
- 写 incident report：发生了什么、怎么发生的、为什么发生、影响范围、修复措施

- 更新检测规则（加入新的 IOC）

- 培训团队：从这次事件中学到什么

### 取证关键命令：黄金组合

**取证时的"黄金五连"**：

```bash
# 1. 当前登录用户与活跃会话
w
who -a
last -F | head -50

# 2. 进程列表（注意：可能被 rootkit 隐藏，需用 /proc 交叉验证）
ps auxf
ls -la /proc/*/exe 2>/dev/null | grep -v 'deleted'

# 3. 网络连接
ss -antp
netstat -antp
lsof -i

# 4. 历史命令
cat /root/.bash_history
cat /home/*/.bash_history

# 5. SSH 认证日志
sudo ausearch -m USER_LOGIN,USER_AUTH,EXECVE --start yesterday
sudo lastb -n 100
```

**进阶：用 /proc 验证 ps**：

```bash
# 直接遍历 /proc 获取进程（即便 rootkit hook 了 ps）
for pid in /proc/[0-9]*; do
  cmdline=$(cat $pid/cmdline 2>/dev/null | tr '\0' ' ')
  exe=$(readlink $pid/exe 2>/dev/null)
  echo "$pid $exe $cmdline"
done
```

---
