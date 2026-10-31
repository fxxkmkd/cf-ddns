# CF-DDNS

<p align="center">
  <a href="https://github.com/fxxkmkd/cf-ddns/stargazers"><img src="https://img.shields.io/github/stars/fxxkmkd/cf-ddns?style=flat-square&logo=github" alt="Stars Badge"/></a>
  <a href="https://github.com/fxxkmkd/cf-ddns/network/members"><img src="https://img.shields.io/github/forks/fxxkmkd/cf-ddns?style=flat-square&logo=github" alt="Forks Badge"/></a>
  <a href="https://github.com/fxxkmkd/cf-ddns/issues"><img src="https://img.shields.io/github/issues/fxxkmkd/cf-ddns?style=flat-square&logo=github" alt="Issues Badge"/></a>
  <a href="https://github.com/fxxkmkd/cf-ddns/blob/main/LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square" alt="License"/></a>
</p>

专为 Linux / Unix 环境打造的高性能、轻量级双平台动态域名解析（DDNS）管理脚本。

原生集成 **Cloudflare**（纯 Shell 实现，零外部重型依赖）与 **华为云**（支持 TTL=1 秒极速生效，全版本通用 Python3 签名），兼具超低资源开销、秒级定时守护与自动容灾调度。

---

## 核心特性

- **双平台深度适配**：
  - **Cloudflare**：纯 Shell 原生实现，仅依赖系统内置 `curl`，无需 Python 或任何重型环境，适合 64M/128M 超低配 VPS、OpenWrt 路由器与容器。
  - **华为云 (Huawei Cloud)**：支持解析记录 TTL 最低设为 **1 秒**，解析切换秒级生效；内置签名引擎完美兼容 Python 3.6 至 Python 3.12+ 全系列版本。
- **智能双栈与多源容灾**：
  - 全面支持 **IPv4 (A 记录)** 与 **IPv6 (AAAA 记录)**。
  - 内置**国际多源优先 + 国内纯文本源智能兜底**（`icanhazip`、`ipify`、`ipw.cn` 等）。
  - 纯 Bash 语法严格校验 IP 格式与数值范围，杜绝将网关拦截页、403/502 报错解析进 DNS。
- **低资源开销与智能缓存**：
  - 本地缓存已解析 IP，IP 无变动时绝不向云端发出多余的请求。
  - 自动向上递归推导并匹配顶级 Zone ID，无需手动查找或粘贴复杂的区域 ID。
- **秒级后台守护与保活**：
  - 支持自定义**秒级**检测间隔（默认 120 秒，支持最低 5 秒）。
  - **Root 权限**：自动注册并配置 Systemd 守护服务（`cf-ddns.service`），支持进程崩溃自启与开机自启。
  - **非 Root 权限**：自动降级为 `nohup` 后台守护，并自动写入当前用户 `@reboot` crontab 计划任务。
  - 配置修改即时唤醒，无需手动重启后台服务即可使新配置立刻生效。

---

## 快速安装与一键运行

### 方式一：一键脚本运行（推荐）

在终端中直接执行以下命令之一即可立即拉取并启动：

**使用 `curl`：**
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/fxxkmkd/cf-ddns/main/cf-ddns.sh)
```

**使用 `wget`：**
```bash
bash <(wget -qO- https://raw.githubusercontent.com/fxxkmkd/cf-ddns/main/cf-ddns.sh)
```

### 方式二：克隆仓库运行

```bash
git clone https://github.com/fxxkmkd/cf-ddns.git
cd cf-ddns
chmod +x cf-ddns.sh
sudo ./cf-ddns.sh
```

> **提示**：推荐使用 `sudo` 或 `root` 权限运行，以便脚本自动注册 Systemd 系统级守护进程及开机自启。

---

## 使用指南

启动脚本后将显示如下交互式菜单：

```text
=========================================
     多平台轻量级 DDNS 管理脚本          
=========================================
  1. 初次配置 DDNS (Cloudflare / 华为云)
  2. 修改现有配置 (二级菜单单项修改)
  3. 立即执行一次 DDNS 同步 (测试/强制刷新)
  4. 开启 / 修改后台定时任务 (按秒设置)
  5. 停止后台定时任务
  6. 查看当前状态与运行日志
  7. 彻底卸载脚本 (停止服务并清除所有文件)
  0. 退出脚本
=========================================
```

### 步骤 1：完成初次配置（选项 1）

在主菜单输入 `1` 进入向导，按提示输入解析平台所需参数：

#### 方案 A：Cloudflare
1. **邮箱**：您的 Cloudflare 注册邮箱。
2. **DDNS 域名**：要更新的解析域名（例如：`ddns.example.com`）。
3. **API Token**：具有 `Zone.DNS:Edit` 权限的 API Token（或 Global API Key）。
4. **解析类型**：`1` 为 IPv4 (A 记录)，`2` 为 IPv6 (AAAA 记录)。
5. **小黄云代理**：是否开启 CDN Proxy（`1` 关闭 / `2` 开启）。

#### 方案 B：华为云
1. **Access Key ID (AK)**：华为云访问密钥 AK。
2. **Secret Access Key (SK)**：华为云访问密钥 SK。
3. **DDNS 域名**：已在华为云云解析添加的域名（例如：`ddns.example.com`）。
4. **解析类型**：`1` 为 IPv4 (A 记录)，`2` 为 IPv6 (AAAA 记录)。
5. **TTL 秒数**：缓存周期（回车默认 `1` 秒，实现秒级极速切换）。

> **说明**：配置成功后，脚本会**立即同步一次当前公网 IP**，但此时后台自动定时任务**尚未开启**。

### 步骤 2：开启后台定时任务（选项 4）

为了让脚本持续在后台自动检测 IP 并在变动时自动更新，请在菜单输入 `4`：
1. **输入间隔时间**：单位为秒（例如输入 `60` 即为每分钟检测一次，回车默认 `120` 秒）。
2. **系统自动托管**：
   - **Root 模式**：自动创建 `/etc/systemd/system/cf-ddns.service` 并通过 `systemctl enable --now` 启动。
   - **普通用户模式**：通过 `nohup` 放入后台，并写入 `crontab -e` 维持开机自启。

### 步骤 3：查看状态与日志（选项 6）

随时输入 `6` 即可查看运行状态：
- 当前生效的服务商、解析域名、本地 IP 缓存、最近一次检测时间戳。
- 定时任务运行状态（PID 与检测间隔周期）。
- 最近 15 条同步日志。

你也可以在终端直接查看完整的历史日志：
```bash
cat ~/.cf_ddns/ddns.log
```

---

## 常用服务管理命令 (Systemd)

若以 Root 权限安装了后台定时任务，可直接通过标准系统命令进行管理：

```bash
# 查看服务运行状态
systemctl status cf-ddns.service

# 跟踪查看实时运行日志
journalctl -u cf-ddns.service -f

# 启动 / 停止 / 重启服务
systemctl start cf-ddns.service
systemctl stop cf-ddns.service
systemctl restart cf-ddns.service
```

---

## 目录结构与数据说明

脚本遵循最小干扰原则，自身代码保持无状态，所有运行数据独立存放在配置目录中：

| 文件 / 路径 | 说明 |
| :--- | :--- |
| `~/.cf_ddns/config.conf` | 服务商凭据、域名、Zone ID 等配置（权限设为 `600`） |
| `~/.cf_ddns/interval.conf` | 后台检测周期（秒） |
| `~/.cf_ddns/last_ip.txt` | 记录上次成功推送至云端的公网 IP |
| `~/.cf_ddns/last_check.txt` | 记录最近一次检查执行的时间戳 |
| `~/.cf_ddns/ddns.log` | 运行日志（自动回滚，保留最近 200 行） |
| `~/.cf_ddns/ddns.pid` | 后台进程 PID 标记 |
| `/etc/systemd/system/cf-ddns.service` | Root 模式下注册的 Systemd 服务单元 |

---

## 彻底卸载

如需移除本脚本与相关配置：
1. 运行 `./cf-ddns.sh` 并在主菜单中选择 **`7. 彻底卸载脚本`**。
2. 脚本将自动停止后台守护、清理 Systemd 服务或 Crontab 任务，并彻底删除 `~/.cf_ddns` 目录及脚本本体。

---

## 常见问题 (FAQ)

### Q1: 华为云报错 `SyntaxError: f-string expression part cannot include a backslash`？
这是低版本 Python（Python 3.11 及以下）的语法限制。最新版本已经将签名逻辑里的表达式独立提炼，完美兼容 Python 3.6 至 3.12+ 全版本，直接拉取最新版脚本即可解决。

### Q2: 可以在 OpenWrt / Alpine 等软路由或精简系统上运行吗？
完全支持。脚本具备 `ash` 与 `bash` 的平滑过渡机制，且针对 Cloudflare 模式只需基础的 `curl` 依赖。

### Q3: 为什么修改配置后不需要重启后台进程？
脚本内置了进程信号响应与配置文件动态热重载机制，任何菜单内的配置改动都会直接发送唤醒信号，新配置即时生效。

---

## 鸣谢与支持

如果觉得这个项目对你有帮助，欢迎在 GitHub 点一个 ⭐️ **Star**！

仓库地址：[https://github.com/fxxkmkd/cf-ddns](https://github.com/fxxkmkd/cf-ddns)