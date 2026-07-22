# 高级防御技术

这一章我们讨论一些"非主流但很有价值"的高级技术——它们不一定要全用，但理解原理能帮你在特定场景下做出更好的决策。

## Port Knocking（敲门认证）

### 原理：SYN 包序列号作为认证

**Port Knocking** 是一种"序列敲门"机制：

```text
客户端按特定顺序连接一组关闭的端口（如 7000, 8000, 9000）
   ↓
服务端（knockd）监听所有端口的 SYN 包
   ↓
匹配到正确序列 → 临时打开 SSH 端口给该 IP
   ↓
SSH 连接进来后，再次按规则关闭或超时关闭
```

**本质上**：用"SYN 包序列号"作为一个共享秘密，攻击者不知道序列就无法敲门。

**安全性分析**：

- **优点**：SSH 端口对外完全不可见，扫描器看不见

- **缺点**：

  - 序列号可通过嗅探（如果攻击者在同一网段）

  - 序列泄露后失去保护作用

  - 实现复杂，维护成本高

  - 现代 knockd 实现有抗重放机制，但仍非完美

### 实现：knockd、fwknop 的对比

**knockd**（zeroknock.alioth.debian.org）
- 经典实现

- 配置简单（knockd.conf）

- 仅基于端口序列

- 无加密、无认证（明文序列）

**fwknop**（www.cipherdyne.org/fwknop/）
- **SPA（Single Packet Authorization）**：单个加密包完成认证

- 加密的认证包（默认 AES）

- HMAC 防篡改

- 抗重放

- 比 knockd 安全得多

### SPA（Single Packet Authorization）的优势

SPA 是 fwknop 的核心创新：

```text
客户端：
1. 生成临时对称密钥（基于用户密码/PKCS#11）
2. 用密钥加密认证信息（IP、时间戳、动作）
3. 计算 HMAC
4. 打包成单个 UDP 包（默认端口 62201）

服务端：
1. 收到 UDP 包
2. 验证 HMAC（防篡改）
3. 解密内容
4. 检查时间戳（防重放）
5. 匹配规则 → 临时开放 SSH
```

**优势**：

- 单包完成认证（延迟低）

- 加密传输（嗅探不到）

- HMAC 防篡改

- 时间戳防重放

### 在抗侧信道攻击中的价值

**侧信道攻击**包括：

- **流量分析**：通过观察哪些 IP 频繁访问 SSH 来推断暴露面

- **时序分析**：通过响应时间推断服务状态

SPA 减少了被流量分析的可能性——攻击者看到的 UDP 包与普通 UDP 流量无法区分。

## 双因素认证（2FA）

### TOTP 原理：基于时间的一次性密码

**TOTP（Time-based One-Time Password，RFC 6238）** 是最常见的 2FA 算法。

**原理**：

```text
服务器端：

  - 与客户端共享一个密钥 K（base32 编码）

  - 计算 T = floor((当前时间 - T0) / X)

  - OTP = HMAC-SHA1(K, T) 截取后 6 位数字

客户端：

  - 用同样的 K 和同样的时间 T

  - 计算相同的 OTP

  - 用户输入 OTP

服务器验证：

  - 当前 OTP 与上一步/下一步 OTP 匹配（容错 ±1 步）

```

**核心要素**：

- **密钥 K**：必须保密，泄露 = 2FA 失效

- **时间同步**：客户端和服务器时间偏差应在 ±30 秒内

- **OTP 寿命**：默认 30 秒

**Google Authenticator、Authy、Microsoft Authenticator** 都是 TOTP 的实现。

### Google Authenticator PAM 模块的部署

**在 SSH 上启用 Google Authenticator**：

```bash
# 安装
sudo apt install libpam-google-authenticator

# 每个用户运行（生成密钥 + 二维码）
google-authenticator

# 提示：
# - Time-based tokens (T) 还是 Counter-based (H)？选 T
# - 扫描二维码或保存 secret key
# - 生成 emergency scratch codes（应急码）

# 配置 PAM
# /etc/pam.d/sshd
auth required pam_google_authenticator.so

# 配置 sshd
# /etc/ssh/sshd_config
ChallengeResponseAuthentication yes
AuthenticationMethods publickey,keyboard-interactive

# 重启 sshd
sudo systemctl restart sshd
```

**关键点**：

- `AuthenticationMethods publickey,keyboard-interactive` —— 密钥 + TOTP 双因素

- 用户**先过密钥认证**，**再过 TOTP 验证**——任何一步失败都拒绝

### YubiKey / FIDO2 的硬件密钥方案

**YubiKey** 是 Yubico 出品的硬件密钥设备。它支持多种协议：

- **OTP**：传统一次性密码

- **OATH-HOTP / OATH-TOTP**：基于 HMAC 的 OTP

- **FIDO U2F**：Universal 2nd Factor，浏览器友好

- **FIDO2 / WebAuthn**：现代无密码认证

**SSH 用 YubiKey**：

```bash
# FIDO2 密钥（OpenSSH 8.2+）
ssh-keygen -t ed25519-sk -O resident -O verify-required

# 插入 YubiKey 后按提示操作
# 私钥存储在 YubiKey 硬件里，无法导出
```

**优势**：

- 私钥**永不落盘**——硬件提取不出来

- 抗中间人：FIDO2 协议本身就设计抗钓鱼

- 抗侧信道：硬件内计算，密钥不进入内存

**劣势**：

- 设备丢失 = 不能登录（必须有备用）

- 成本（YubiKey 5 系列约 $50/个）

- 不是所有场景都支持（SSH 是支持的，但其他服务可能不支持）

### SSH 2FA 的几种实现路径对比

| 路径 | 安全性 | 易用性 | 成本 | 适用场景 |
|---|---|---|---|---|
| Google Authenticator | 中高 | 中 | 免费 | 一般运维 |
| FreeOTP / Authy | 中高 | 中 | 免费 | 一般运维 |
| YubiKey FIDO2 | 极高 | 高 | $50/个 | 高安全要求 |
| FIDO2 平台认证器 | 极高 | 高 | 内置 | 个人设备 |
| Duo Security | 高 | 高 | 收费 | 企业级 |
| 自建 TOTP 服务器 | 中高 | 低 | 自建 | 内部系统 |

**推荐组合**：

- **个人开发者**：YubiKey 或 FIDO2 平台认证器

- **小团队**：Google Authenticator + 备份应急码

- **企业**：Duo / Okta 等托管方案

## 证书认证（SSH CA）

### 与传统 authorized_keys 的本质区别

传统 SSH 认证是**直接信任公钥**——你信任某台机器上的某个 `id_ed25519.pub`，因为它出现在 `authorized_keys` 里。

**SSH CA 认证**是**通过证书签名链间接信任**：

```text
用户生成密钥对 (priv, pub)
   ↓
用户把 pub 发送给 CA（自己的 CA 或组织的 CA）
   ↓
CA 验证用户身份后，用 CA 的私钥签名 pub，生成证书
   ↓
证书里包含：用户名、有效期、可登录的主机列表、principal 等
   ↓
用户登录时，把证书 + 自己的私钥发给服务端
   ↓
服务端用 CA 的公钥验证证书签名
   ↓
证书有效 → 允许登录
```

**核心区别**：

- **传统方式**：每台机器维护一张 `authorized_keys` 列表

- **CA 方式**：每台机器只信任**一个 CA 公钥**，用户的证书由 CA 签发

**优势**：

- **集中管理**：撤销一个用户只需要让 CA 不再签新证书

- **短期凭证**：证书可以设 1 小时有效，过期自动失效

- **细粒度控制**：证书里可以指定用户能登录哪些主机、什么 principal

- **无需每台机器更新**：用户密钥变更不需要 push 到每台服务器

### 主机证书 + 用户证书的完整 PKI 架构

**完整的 SSH PKI 包含两个 CA**：

**Host CA（主机证书）**：签发主机公钥
- 客户端 ssh-known-hosts 中只信任 Host CA 的公钥

- 任何主机上线时，由 Host CA 签发证书

- 客户端验证主机时用 Host CA 的公钥验证

**User CA（用户证书）**：签发用户公钥
- 服务器 authorized_keys 中只放 User CA 的公钥

- 任何用户登录时，由 User CA 签发证书

- 服务器验证用户时用 User CA 的公钥验证

**典型配置文件**：

```text
# /etc/ssh/sshd_config
TrustedUserCAKeys /etc/ssh/user_ca.pub
HostCertificate /etc/ssh/ssh_host_ed25519_cert.pub

# /etc/ssh/ssh_known_hosts（客户端）
@cert-authority * ssh-ed25519 AAAA...host_ca_pub_key
```

### 证书生命周期管理：签发、吊销、轮换

**签发**：

```bash
# 生成 CA 密钥对
ssh-keygen -t ed25519 -f user_ca -C "User CA"

# 用户提交公钥，CA 签发证书
ssh-keygen -s user_ca -I "user_id" -n axu -V +1h user_key.pub
# -s: 签名密钥
# -I: 证书 ID（用于审计）
# -n: principal（用户名）
# -V +1h: 有效期 1 小时

# 限制证书只能在某些主机登录
ssh-keygen -s user_ca -I "user_id" -n axu -V +1h \
  -O source-address=10.0.0.0/8 \
  -O force-command=/usr/bin/whoami \
  user_key.pub
```

**吊销**：

SSH CA 没有原生的 CRL（Certificate Revocation List）——这是 SSH 证书体系的局限。但可以用以下方式间接实现：

| 方法 | 说明 |
|------|------|
| 短期证书 | 签发 1 小时或 1 天有效期的证书，过期即失效 |
| CRL 文件 | 在 SSH 配置中用 `RevokedKeys`（OpenSSH 8.6+） |
| 定期轮换 | 用户每次需要新证书 |

**轮换**：

```bash
# 1. 生成新 CA 密钥
ssh-keygen -t ed25519 -f new_user_ca -C "User CA 2026"

# 2. 让所有 sshd 信任新 CA
echo "$(cat new_user_ca.pub)" >> /etc/ssh/user_ca.pub

# 3. 旧 CA 的信任保留一段时间（让旧证书过期）
# 4. 一段时间后移除旧 CA
```

### 适用场景

| 场景 | 适用性 |
|------|--------|
| 大规模集群 | 数百台机器、数百个用户 |
| CI/CD 环境 | 短期凭证、自动轮换 |
| 临时权限 | 运维临时登录、第三方合作 |
| 多云/混合云 | 跨云统一身份 |

### Hashicorp Vault SSH 签发模式

**Vault**（vaultproject.io）作为 SSH CA 的中央管理：

```text
用户请求短期凭证 → Vault 验证用户身份（OIDC、LDAP 等）
   ↓
Vault 用其 CA 私钥签发证书（默认 1 小时有效）
   ↓
用户拿到证书，登录目标机器
   ↓
1 小时后证书自动失效
```

**Vault SSH Secrets Engine**（developer.hashicorp.com/vault/docs/secrets/ssh）提供：

- 动态签发证书

- 与外部身份系统集成（Active Directory、LDAP、OIDC）

- 审计所有签发请求

- 与 Vault 的动态凭证（数据库、API 密钥）统一管理

**实战命令**：

```bash
# 用户登录 Vault 拿到 SSH 证书
vault ssh -role=my-role -mode=ca axu@target-host

# Vault 自动：验证用户 → 签发证书 → ssh 登录目标主机
```

## 堡垒机（Bastion Host）

### 攻击面收敛原理

**传统架构**：
```text
公网 → 防火墙 → [开发机、数据库、缓存、应用服务器...]
```
每台机器都有 SSH 端口对外（或对内网）暴露，攻击面是 N 个。

**堡垒机架构**：
```text
公网 → [堡垒机] → [开发机、数据库、缓存、应用服务器...]
```
所有 SSH 访问必须经过堡垒机，**目标机器的 SSH 完全对外不可见**。攻击面收敛到 1。

### Session Recording 的两种实现

**实现 1：SSH Proxy（代理型）**
- 堡垒机作为 SSH 代理，客户端 SSH 到堡垒机，堡垒机再 SSH 到目标

- 堡垒机可以录制整个会话的输入输出

- 例：**Teleport**、**Bastillion**

**实现 2：旁路审计**
- 堡垒机不作为代理，而是用其他方式审计（如 auditd 推送、SOC agent）

- 目标机器仍然对外可达（仅 IP 限制）

- 例：**JumpServer** 的部分模式

**两种对比**：

| 维度 | SSH Proxy | 旁路审计 |
|---|---|---|
| 安全性 | 高（不暴露目标） | 中（目标仍可达） |
| 性能开销 | 中（流量代理） | 低（仅审计） |
| 用户体验 | 中（多跳登录） | 好（直连目标） |
| 审计完整性 | 完整（所有 IO） | 部分（依赖 agent） |
| 配置复杂度 | 中 | 高 |

### 开源方案：Teleport、Apache Guacamole、Bastillion

**Teleport**（goteleport.com）
- **架构**：统一的 SSH/K8s/DB/应用 访问网关

- **特色**：

  - 内置 MFA（WebAuthn、TOTP）

  - 内置 RBAC（基于角色的访问控制）

  - 内置会话录像 + 回放

  - 联邦能力（跨集群）

  - K8s 原生支持

- **开源版**：免费，限制 15 个节点

- **企业版**：按节点收费，$20-200/节点/月

**Apache Guacamole**（guacamole.apache.org）
- **架构**：客户端 HTML5 + 后端 guacd 守护进程

- **特色**：

  - 无客户端插件（纯浏览器）

  - 支持 SSH、RDP、VNC

  - 录制、转发、剪切板控制

- **适用**：临时访问、远程支持

**Bastillion**（bastillion.io）
- **架构**：Web 界面 + SSH 代理

- **特色**：

  - 轻量级、易部署

  - 内置密钥管理

  - 会话录像

- **适用**：小团队

### 商业方案对比：JumpServer、Teleport Enterprise、CipherTrust

**JumpServer**（jumpserver.org）
- 国内开源堡垒机的代表

- 4A 架构（认证、授权、账号、审计）

- 中文界面好

- 中大型企业用户多

- **开源版**：免费

**Teleport Enterprise**
- 见上面，加商业功能（SSO、合规报告、SLA）

**CipherTrust / Thales**
- 企业级密钥管理 + 加密

- 与 SSH 集成较弱，更专注于加密和合规

### 堡垒机自身的纵深防御

堡垒机本身是"王冠上的明珠"——攻破堡垒机 = 攻破所有机器。它的纵深防御必须到位：

- **多因素认证**（YubiKey、TOTP）

- **严格的 IP 白名单**

- **高强度审计日志**（集中到独立 SIEM）

- **自身最小化**（只跑堡垒机软件，不跑其他服务）

- **定期安全更新**

- **物理安全**（云上 = 严格 IAM）

- **应急访问机制**（堡垒机失联时怎么办？）

## Zero Trust 架构下的 SSH

### BeyondCorp 思想

**BeyondCorp** 是 Google 2014 年提出的零信任架构模型，核心思想：

- 不信任内网（"内网 ≠ 可信"）

- 每次访问都基于**身份 + 设备 + 上下文**做鉴权

- 访问代理统一处理所有访问请求

**在 SSH 中的体现**：

```text
传统 SSH：内网机器默认互相 SSH 可信
BeyondCorp 风格 SSH：每次 SSH 都验证身份、设备状态、上下文
```

### Teleport / Tailscale SSH 的设计哲学

**Teleport**：

- 把 SSH 封装成基于身份的服务

- 用户身份通过 SSO（Google、Okta、GitHub）验证

- 设备证书（Device Trust）证明设备合规

- 每次 SSH 都通过 Teleport Proxy 鉴权

- **零信任 + 强审计 + 用户友好**

**Tailscale SSH**：

- 基于 WireGuard mesh 网络

- 节点间通过 Tailnet 内部身份认证

- SSH 端口只对 Tailnet 内部开放

- 不需要传统 SSH 凭据——身份由 Tailscale 控制平面签发

- **零暴露 + 简化认证 + 跨云无缝**

### WireGuard + SSH 的组合

**WireGuard**（wireguard.com）是现代 VPN 协议，基于：

- Curve25519 密钥交换

- ChaCha20 加密

- Poly1305 MAC

- 极简代码（4 千行 vs OpenVPN 10 万行）

**组合架构**：

```text
客户端（WireGuard） → WireGuard mesh → 目标机器（WireGuard + SSH）
                                    ↑
                            SSH 只监听 WireGuard 接口
                            不监听公网接口
```

**优势**：

- WireGuard 暴露的端口远少于 SSH

- 即使 WireGuard 被扫描到，密钥认证难度大

- SSH 端口完全隐藏在内层

- 性能极佳（WireGuard 内核态运行）

### Cloudflare Access 的 SSH over Zero Trust

**Cloudflare Access**（developers.cloudflare.com/cloudflare-one/policies/access/）通过 Cloudflare Tunnel 提供 SSH 访问：

```text
用户 → Cloudflare Edge（鉴权） → Cloudflare Tunnel → 目标 SSH
```

**优势**：

- SSH 服务**完全无公网暴露**

- Cloudflare 的全球边缘鉴权（含 MFA）

- 集中化的访问策略

- 与 Cloudflare 生态集成（Zero Trust、WARP）

**部署命令**：

```bash
# 在目标机器上
cloudflared service install <token>

# Cloudflare Dashboard 配置 Access 应用
# 策略：哪些用户/群组可以 SSH 到哪些机器
```

**代价**：依赖 Cloudflare 服务，每月 $3-7/用户。

---
