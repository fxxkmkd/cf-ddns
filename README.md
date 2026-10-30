# Cloudflare 轻量级 DDNS 脚本 

一个轻量、无需手动查找 Zone ID 的 Cloudflare 动态域名解析 (DDNS) 自动化脚本。仅需提供邮箱、域名和 API Token，脚本即可自动追溯 Zone 匹配所属站点并同步更新 DNS 记录。支持精确到秒级的后台守护进程、系统级开机自启、多级子域名以及 IPv4 / IPv6 双栈支持。

---

## 目录
- [功能特性](#功能特性)
- [系统依赖与安装](#系统依赖与安装)
- [一键拉取与部署](#一键拉取与部署)
- [使用与配置指南](#使用与配置指南)
- [Cloudflare 凭证获取指引](#cloudflare-凭证获取指引)
- [配置文件与目录结构](#配置文件与目录结构)
- [常见问题 (FAQ)](#常见问题-faq)

---

## 功能特性

* **免手填 Zone ID**：脚本自动根据输入的域名逐级向上递归查询所属主域名与 Zone ID，无需登录控制台翻找。
* **兼容双鉴权模式**：原生支持官方推荐的限定权限 **API Token (Bearer)**，并向下兼容 **Global API Key**。
* **秒级后台守护**：突破传统 Crontab 只能按分钟执行的限制，支持以**秒**为单位配置轮询间隔（最低 5 秒）。
* **原生守护机制**：在 Root/Systemd 环境下自动注册为 Systemd 服务并开启开机自启；非 Root 或无 Systemd 环境下自动降级为 Nohup 守护。
* **智能 IP 比对缓存**：本地缓存上一次同步的公网 IP，IP 无变动时不发起更新请求，防止触发 API 速率限制。
* **支持 A 与 AAAA 记录**：支持 IPv4 (A 记录) 与 IPv6 (AAAA 记录)，支持一键开关 Cloudflare 代理加速（小黄云）。

---

## 系统依赖与安装

脚本基于原生 Bash 编写，依赖 `curl`、`bash`、`coreutils`（如 `sed`, `grep`, `tr`, `tail`）以及 `procps`。在绝大多数常见 Linux 发行版中均可直接运行。

### 各发行版安装依赖

#### 1. Debian / Ubuntu / Armbian / Kali
```bash
sudo apt update
sudo apt install -y curl bash coreutils procps
```

#### 2. CentOS / RHEL / Rocky Linux / AlmaLinux / Fedora
```bash
# CentOS 8+ / Rocky Linux / AlmaLinux / Fedora
sudo dnf install -y curl bash coreutils procps-ng

# CentOS 7
sudo yum install -y curl bash coreutils procps-ng
```

#### 3. Alpine Linux
```bash
apk update
apk add --no-cache curl bash coreutils procps
```

#### 4. Arch Linux / Manjaro
```bash
sudo pacman -Sy --noconfirm curl bash coreutils procps-ng
```

#### 5. OpenWrt
```bash
opkg update
opkg install curl bash coreutils-wc coreutils-tail sed grep
```

---

## 一键拉取与部署

你可以在终端中执行以下命令将脚本下载到本地并赋予执行权限：

### 方式 A：通过 cURL 直接下载
```bash
curl -fsSL https://raw.githubusercontent.com/fxxkmkd/cf-ddns/main/cf-ddns.sh -o cf-ddns.sh
chmod +x cf-ddns.sh
```

### 方式 B：通过 Wget 下载
```bash
wget -qO cf-ddns.sh https://raw.githubusercontent.com/fxxkmkd/cf-ddns/main/cf-ddns.sh
chmod +x cf-ddns.sh
```

### 方式 C：通过 Git 仓库克隆
```bash
git clone https://github.com/fxxkmkd/cf-ddns.git
cd cf-ddns
chmod +x cf-ddns.sh
```

---

## 使用与配置指南

直接在终端执行脚本（脚本支持重命名为任意文件名运行）：

```bash
sudo ./cf-ddns.sh
```
> **提示**：若需要将守护进程注册为开机自启的 Systemd 服务，建议使用 `sudo` 或 `root` 权限执行；若以普通用户权限运行，脚本会自动降级为 `nohup` 守护模式。

### 交互菜单选项

```text
=========================================
     Cloudflare 轻量级 DDNS 管理脚本     
=========================================
  1. 配置 DDNS (仅需邮箱 + 域名 + Token)
  2. 立即执行一次 DDNS 同步 (测试/强制刷新)
  3. 开启 / 修改后台定时任务 (按秒设置)
  4. 停止后台定时任务
  5. 查看当前状态与运行日志
  0. 退出脚本
=========================================
```

### 1. 配置 DDNS 信息
初次使用请选择 `1`，按照提示输入以下配置项：
* **Cloudflare 邮箱**：你的 Cloudflare 注册登录邮箱。
* **DDNS 域名**：需要绑定的完整二级/三级域名（例如 `home.example.com` 或 `nas.vpn.example.com`）。
* **API Token**：具有 DNS 编辑权限的 API 密钥。
* **解析类型**：输入 `1` 为 IPv4 (A 记录)，输入 `2` 为 IPv6 (AAAA 记录)。
* **小黄云 CDN 代理**：输入 `1` 为仅 DNS 解析（关闭 CDN，适合直连/端口映射），输入 `2` 为开启 CDN。

配置完成后，脚本会自动测试凭据有效性、查找匹配站点 Zone ID，并立即触发一次初次解析。

### 2. 开启后台定时任务
选择 `3`，输入你希望检测更新的时间间隔：
* 单位为**秒**。
* 支持最小 **5** 秒检测一次。
* 默认推荐为 **120** 秒。

设置完成后，后台会自动驻留守护进程，并在网络 IP 发生变化时更新 Cloudflare 解析记录。

### 3. 查看状态与日志
选择 `5` 即可实时查看当前的绑定配置、公网 IP、最近一次检测时间戳以及后台执行的最近 15 条同步日志。

---

## Cloudflare 凭证获取指引

建议创建仅授予 DNS 编辑权限的专用 Token，以保障账号安全：

1. 登录 [Cloudflare 控制台](https://dash.cloudflare.com/)。
2. 点击右上角头像 -> **我的个人资料 (My Profile)** -> **API 令牌 (API Tokens)**。
3. 点击 **创建令牌 (Create Token)**，选择 **编辑区域 DNS (Edit zone DNS)** 模板。
4. 配置权限参数：
   * **权限 (Permissions)**：保持默认的 `区域 (Zone)` - `DNS` - `编辑 (Edit)`。
   * **区域资源 (Zone Resources)**：选择 `包括 (Include)` - `特定区域 (Specific zone)` - 选中你的目标域名。
5. 点击 **继续以显示摘要** -> **创建令牌**，复制生成的长字符串 Token 即可。

---

## 配置文件与目录结构

脚本产生的所有数据与日志均统一保存在用户主目录下的隐藏文件夹中：

```text
~/.cf_ddns/
├── config.conf       # DDNS 配置核心文件 (包含邮箱、Token、Zone ID 等)
├── interval.conf     # 后台循环定时间隔 (单位: 秒)
├── last_ip.txt       # 上次同步成功的 IP 缓存 (避免重复请求)
├── last_check.txt    # 最近一次心跳检测时间戳
├── ddns.log          # 运行日志文件 (自动滚动保留最近 200 行)
└── ddns.pid          # 后台运行进程 PID 标识文件
```

---

## 常见问题 (FAQ)

#### Q1: 定时间隔设置得太短（如 5 秒）会导致 Cloudflare 封号或限流吗？
脚本内部具有 IP 本地缓存比对机制。只有在本机获取到的公网 IP 与本地缓存中记录的 IP **不一致**时，才会向 Cloudflare API 发送写入请求。IP 未发生变动时仅执行本地比对，不会向 Cloudflare 产生高频 API 流量。

#### Q2: 为什么日志中看不到每一轮定时检测的记录？
为了避免日志无限膨胀，当本机公网 IP 保持不变时，脚本仅刷新 `last_check.txt` 时间戳而不往日志中写入冗余信息。你可以在菜单中选择 `5`，通过 **“最后检测”** 时间确认守护进程是否在按设定的秒数正常轮询。

#### Q3: 运行脚本提示 `无法获取本机公网 IP`？
请确认你的机器具备公网访问权限，或者在终端中测试公网 IP 查询源是否畅通：
```bash
curl -4 https://ipv4.icanhazip.com
curl -4 https://api.ipify.org
```
