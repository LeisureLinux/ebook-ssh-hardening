## 第 2 章：攻击侧：知己知彼

### 2.1 攻击者怎么发现你

#### 2.1.1 全网扫描原理：ZMap 和 Masscan 的 stateless 扫描

要理解"被发现"，首先要理解**全网扫描**是怎么做到的。

传统的 TCP SYN 扫描（nmap 默认模式）需要维护每个目标的状态——发送 SYN、等待 SYN-ACK、记录结果、最后发 RST 关闭连接。当目标数量达到亿级别，主机的端口状态表会爆炸。这就是为什么 nmap 适合扫描一个 C 段，扫全网几乎不可能。

**ZMap**（密歇根大学 2013 年发布，GitHub: `zmap/zmap`）和 **Masscan**（Robert Graham 发布）是两种典型的 **stateless（无状态）扫描器**。它们的核心思想是：

- **不要维护每个目标的状态表**，而是基于"反馈回来什么就推断什么"
- 关键技巧：**猜测目标主机的 IPID、TCP 序列号、IP 标识符**，借此反推 SYN-ACK 是来自哪台主机
- 发送速度可达到**每秒数百万到一千万个 SYN 包**

Masscan 的官方文档里有个夸张的例子：它能在 5 分钟内扫完全部 IPv4 的某个端口（在配置良好的网络下）。这种速率靠的是 raw socket + 内核旁路（PF_RING、netmap）。

**为什么要关心这些？** 因为：
1. **22 端口被扫描一遍的速度，远比你想的快**
2. 扫描的流量特征是"源 IP 极度分散 + 单一目标端口 + 包长异常小"
3. 防御侧可以通过 BGP flowspec、SDN 控制器在边缘丢弃异常扫描流量

#### 2.1.2 资产测绘平台：Censys、Shodan、FOFA、ZoomEye

除了主动扫描，攻击者还会利用**资产测绘平台**——这是攻防双方共同依赖的情报源：

- **Shodan**（shodan.io）：2009 年由 John Matherly 创立，持续扫描全网并打 banner，被称作"互联网的黑暗谷歌"
- **Censys**（censys.io）：密歇根大学项目，更学术化，数据免费给研究人员查询
- **FOFA**（fofa.info）：白帽汇出品，中文场景数据全
- **ZoomEye**（zoomeye.org）：知道创宇出品，国内另一大资产测绘引擎

这些平台的原理是：**周期性扫描全网 → 收集 banner（协议握手时的响应指纹）→ 索引到数据库 → 提供查询接口**。攻击者只要在 Shodan 搜 `port:22 country:CN`，几秒钟就能拿到中国所有暴露的 SSH 服务器列表。

**banner 指纹的学问**：不同版本的 OpenSSH 在握手时会返回不同的版本字符串（如 `OpenSSH_8.0p1`）。这个 banner 看似无害，实际上给了攻击者**精确的版本信息**，可以关联到该版本的所有已知 CVE（比如 OpenSSH 的 regreSSHion CVE-2024-6387）。**这就是为什么 OpenSSH 默认版本字符串里也带有一定混淆机制**——它能在最小化泄露的同时保留兼容性。

**对抗手段**：
- 在 sshd_config 中设置 `DebianBanner no`（Debian/Ubuntu 专属）
- 自定义 banner 内容干扰指纹识别
- 更彻底的做法：把 SSH 藏在 VPN/Zero Trust 后面，让扫描器根本摸不到

#### 2.1.3 蜜罐识别：攻击者如何避开蜜罐

你以为把 SSH 暴露出去，别人看到 banner 才来试密码——但有经验的攻击者会**先判断这台是不是蜜罐**。

蜜罐识别的常见方法：

- **延迟探测**：扫描蜜罐端口的响应时间往往跟正常服务有微妙差异（蜜罐是 Python 写的，响应慢）
- **行为指纹**：蜜罐对错误密码的响应格式、对畸形协议的处理方式与真实 sshd 有差异
- **资源探测**：蜜罐的 CPU、内存、磁盘 I/O 行为异常（除非是 high-interaction 蜜罐）
- **诱饵文件检查**：蜜罐常部署有"刻意"的文件（如 Honey cred 文件），攻击者会避开
- **IP地址黑名单**：很多公开蜜罐的 IP 段在社区里被共享

这就是为什么 Cowrie 这种成熟蜜罐（GitHub: `cowrie/cowrie`）要做得很"像"——它不仅模拟 SSH 协议，还要模拟文件系统、shell 命令，让攻击者花更多时间在里面。

#### 2.1.4 默认 22 端口 vs 改端口的收益量化

**改端口的真实收益**到底有多大？我从生产环境的日志统计过，给大家一个量化的认知：

| 端口策略 | 每日暴力破解尝试次数（公网 IP，22 端口） | 每日暴力破解尝试次数（同一台机器，改 2222） |
|---|---|---|
| 启用 SSH 第一周 | 5000-20000 | 50-200 |
| 启用 SSH 一个月后 | 3000-8000 | 100-500 |
| 启用 SSH 半年后 | 2000-5000 | 200-800 |

结论：
- 改端口能挡掉 **95%-99%** 的扫描噪声
- 但**挡不住定向攻击**——攻击者跑一次全端口扫描就能发现你
- 改端口带来的副作用是**真实误报减少**，运维同学体验更好
- 对经验丰富的攻击者，**改端口是负面信号**——说明这台机器的管理员有安全意识，可能更有价值

所以我的建议是：**改端口是一个"低成本高收益"的卫生措施，应当做；但不要把它当作"安全措施"**。它帮你减少噪声、让你更专注于真正有价值的告警。

### 2.2 攻击者怎么试密码

#### 2.2.1 字典攻击原理：从 top10k 到 RockYou

字典攻击的基础是"假设用户的密码在某个可枚举的集合中"。攻击者常用的字典：

- **top10k.txt**：GitHub 上 `danielmiessler/SecLists` 仓库的 `Passwords/Common-Credentials/` 目录下，是从公开泄露数据中统计出的高频密码前 10000 个
- **top100k.txt / top1M.txt**：扩展到 10 万、100 万、1000 万
- **RockYou.txt**：2009 年 RockYou 公司 SQL 注入泄露的 3200 万明文密码，是字典攻击的"圣经"，至今仍是最常用的字典
- **自定义字典**：基于目标公司名、产品名、域名拼音、生日常见格式构造

攻击工具最经典的是 **THC-Hydra**、**Medusa**、**Ncrack**，以及 SSH 专用的 **ssh-audit**、**Crowbar**。它们的核心逻辑都是：

```
for user in user_list:
    for pass in pass_list:
        try_login(user, pass)
        sleep(throttle)
```

暴力破解的工程化非常成熟，GitHub 上的 `nmap/scripts/ssh-brute.nse`、Metasploit 的 `auxiliary/scanner/ssh/ssh_login` 模块都是现成的。

#### 2.2.2 撞库与凭证填充

**撞库（Credential Stuffing）**比字典攻击更高级：它假设用户在多个站点复用了同一个密码。攻击者从过去的泄露数据库（如 Collection #1-#5，包含数十亿条凭证）中取出 `email:password` 组合，直接到目标站点测试。

**Have I Been Pwned（HIBP）** 由 Troy Hunt 维护，是查询"我的邮箱是否泄露过"的权威站点。它的 API 返回的密码哈希前缀（如前 5 位 SHA-1）让用户能验证自己的密码是否在泄露集中。

**凭证填充的工程化**：
- **账号枚举**：先收集目标公司员工邮箱（LinkedIn、WHOIS、企业邮筒公开信息）
- **泄露数据库导入**：从 Collection 系列、脱裤论坛购买"原始数据"
- **分布式执行**：用几千台肉鸡分布式测试，避免单 IP 触发频率告警
- **慢速化**：每分钟只测 1-5 次，绕开绝大多数检测规则

防御侧：
- 强制用户使用**一次性密码**
- 启用 **HSTS、Cookie 完整性保护**
- 对 SSH 来说，最直接的防御是：**根本不让密码登录**（PubkeyAuthentication yes + PasswordAuthentication no）

#### 2.2.3 慢速攻击：Throttling、Jitter、分布 IP

现代攻击者早就知道"高频会触发告警"，他们用三种手段降低被检测概率：

**Throttling（速率控制）**
- 每分钟/每小时只发一次尝试
- 单源速率降到人类打字水平
- 每次尝试之间 sleep 60-120 秒

**Jitter（抖动）**
- 在 throttle 的基础上加随机抖动（±20-50%）
- 让攻击流量看起来更像自然行为

**Distribution（分布式）**
- Botnet 协同，每个肉鸡只负责少量账号
- 单 IP 永远不触发阈值
- 累计起来，每小时可能完成数千次尝试

举例来说，一个 1000 台肉鸡的 botnet 每台每天只试 5 次密码，一天就是 5000 次。这种攻击**fail2ban 完全拦不住**，因为每个 IP 都没达到触发阈值。

#### 2.2.4 时序攻击：键盘时序模拟

更高级的攻击者会**模拟人类行为**：
- 不同的密码尝试之间间隔不同（模拟人类思考、被打断）
- 工作时间集中在 UTC 8-22（中国工作时间）
- 周末降低活动（避免管理员警觉）
- 登录失败的"打字速度"符合人类特征（包长分布相似）

这种"行为对齐"让基于行为分析的 IDS 也失效。**唯一的对抗是设备指纹**（同一攻击者用同一组肉鸡，TCP/IP 指纹会相似），但这需要更高级的检测能力。

#### 2.2.5 凭证填充的完整工程链

把上面整合一下，一次完整的现代 SSH 暴力破解攻击链是这样的：

1. **目标识别**：从 Shodan/FOFA 拉 SSH 暴露列表
2. **资产画像**：识别机器用途（看 banner、HTTP 响应、猜测用途）
3. **蜜罐检测**：判断目标是不是 honeypot
4. **账号枚举**：通过公司邮箱格式、GitHub 提交记录、错误信息泄露等渠道拿到用户名
5. **凭证准备**：从泄露数据库 + 字典生成候选密码集
6. **分布式攻击**：1000+ 肉鸡、每分钟 0.5 次、模拟人类行为
7. **成功登录**：立即启动后续动作（植入后门、横向、清理痕迹）

看到没？**单点防御在这个攻击链面前形同虚设**。我们必须构建纵深防御，让攻击者在每一步都暴露风险。

### 2.3 完整攻击链拆解

#### 2.3.1 洛克希德·马丁 Cyber Kill Chain 在 SSH 攻击中的应用

洛克希德·马丁公司 2011 年提出的 **Cyber Kill Chain**（网络杀伤链）模型描述了攻击的 7 个阶段：

1. **Reconnaissance（侦察）**：Shodan 扫描、资产识别、员工画像
2. **Weaponization（武器化）**：构造攻击载荷（字典、漏洞利用脚本）
3. **Delivery（投递）**：实际发起攻击（SSH 暴力破解）
4. **Exploitation（利用）**：成功登录、漏洞利用
5. **Installation（安装）**：部署后门、植入挖矿程序
6. **Command & Control（C2）**：建立控制通道
7. **Actions on Objectives（目标行动）**：数据窃取、破坏、勒索

**SSH 暴力破解对应的是第 3、4 阶段**。我们的纵深防御需要在每一阶段都设置障碍——这才是"纵深"的真正含义。

#### 2.3.2 MITRE ATT&CK 中的 SSH 相关技术

**MITRE ATT&CK**（attack.mitre.org）是攻击者技战术的标准化分类。在 Enterprise Matrix 中，与 SSH 强相关的技术有：

- **T1078 - Valid Accounts（有效账号）**：使用合法凭证登录
  - T1078.003 - Local Accounts
  - T1078.004 - Cloud Accounts
- **T1110 - Brute Force（暴力破解）**：
  - T1110.001 - Password Guessing
  - T1110.002 - Password Cracking（离线破解）
  - T1110.003 - Password Spraying（密码喷洒，一个密码试多账号）
  - T1110.004 - Credential Stuffing（凭证填充）
- **T1021.004 - Remote Services: SSH**：SSH 作为远程服务被滥用
- **T1078.003 / T1078.004**：合法凭证的滥用
- **T1552.004 - Unsecured Credentials: Private Keys**：暴露的 SSH 私钥
- **T1550.004 - Use Alternate Authentication Material: Web Session Cookie**（间接相关）
- **T1059.004 - Command and Scripting Interpreter: Unix Shell**：SSH 登录后执行 shell 命令

理解这些技术编号有什么用？它帮我们**用统一语言描述攻击**，对接 SIEM 规则、威胁情报、检测脚本时不再有歧义。

#### 2.3.3 从 SSH 暴力破解到内网横向的完整 TTP

把攻击链展开到底：

**初始访问阶段**
- T1110.001 Password Guessing（密码猜测）—— 在 SSH 上
- T1078 Valid Accounts（一旦成功登录，攻击者获得了"合法凭证"身份）

**执行阶段**
- T1059.004 Unix Shell：执行 shell 命令
- T1059.006 Python：上传 Python 脚本
- T1053.003 Cron：持久化

**持久化阶段**
- T1098 Account Manipulation：增加新账号
- T1543.002 Systemd Service：注册 systemd 服务
- T1556 Modify Authentication Process：修改 PAM

**提权阶段**
- T1068 Exploitation for Privilege Escalation：内核漏洞（DirtyPipe 等）
- T1548.003 Sudo and Sudo Caching：滥用 sudo 配置
- T1078.003 Local Accounts：寻找本地账号

**防御绕过阶段**
- T1070 Indicator Removal：清理日志（`/var/log/secure`、`/var/log/wtmp`、`history`）
- T1027 Obfuscated Files or Information：混淆的二进制
- T1562.001 Disable or Modify Tools：停用 fail2ban、auditd

**凭证访问阶段**
- T1552.004 Private Keys：读取其他用户的 `~/.ssh/id_rsa`
- T1003 OS Credential Dumping：抓 shadow 文件、内存中的凭证
- T1555 Credentials from Password Stores：浏览器、密码管理器

**横向移动阶段**
- T1021.004 SSH：内网 SSH 横向
- T1570 Lateral Tool Transfer：横向传输工具

**数据外泄阶段**
- T1041 Exfiltration Over C2 Channel：通过 SSH 隧道外泄
- T1567 Exfiltration Over Web Service：上传到外部网盘

**影响的阶段**
- T1486 Data Encrypted for Impact：勒索软件加密
- T1496 Resource Hijacking：挖矿

这就是为什么我说"**SSH 暴力破解从来不是单一攻击**"——它是这一长串技术的触发器。防御它，需要在每一个阶段都设置障碍。

---

