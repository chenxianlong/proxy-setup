# 开发服务器环境搭建（Debian）

把这台服务器从"裸机"配置成可用作**项目开发服务器**的完整记录，可直接复制到新机器。

---

## 0. 机器规格（本机）

| 项 | 值 |
|---|---|
| 系统 | Debian GNU/Linux 13 (trixie)，内核 6.12 |
| CPU | 1 vCPU（AMD EPYC 9374F）—— ⚠️ 偏弱，编译/多容器会吃力 |
| 内存 | 8 GiB，Swap 512 MiB |
| 磁盘 | 约 600 GiB（`/` 单根，LVM） |
| 网络 | 静态 IP，经 HTTP 代理出网 |

---

## 1. 总览清单

| 层 | 组件 | 本机版本 |
|---|---|---|
| 基础工具 | build-essential / cmake / git / jq / tmux … | — |
| Node | node / npm / pnpm / yarn | node 22.23.3 / npm 10.9.9 / pnpm 12.6.0 / yarn 1.22.22 |
| 进程守护 | PM2 | 7.0.4 |
| Web/反代 | nginx | 1.26.3 |
| 安全 | ufw / fail2ban / certbot | certbot 4.0.0 |
| AI 编码 | Devin CLI | 3000.11.3 |
| 代理 | 全局 HTTP 代理（本仓库脚本） | — |

---

## 2. 基础工具

```bash
sudo apt update
sudo apt install -y \
  build-essential cmake pkg-config autoconf automake libtool \
  git jq yq tree zip unzip rsync tmux htop btop ncdu fzf direnv \
  ca-certificates gnupg
```

- `build-essential/cmake`：编译 Node 原生模块（node-gyp）、C/C++ 项目
- `tmux`：**远程开发必备**，SSH 断了进程还在

---

## 3. Node 工具链

```bash
# Node（本机为官方 tarball，装在 /opt，软链 /usr/local/bin/node）
#   版本：node -v

# pnpm / yarn（通过 npm 安装，因为 corepack 不认代理，见下）
sudo npm install -g pnpm yarn

# npm 全局目录设为 /usr/local（已在默认 PATH）
npm config set prefix /usr/local --global
```

### ⚠️ 关于 corepack
node 自带的 `corepack` 用 Node 内置 fetch，**不读 `http_proxy`**，在代理环境里下载 pnpm/yarn 会超时。
所以这里改用能走代理的 `npm install -g`，并 `corepack disable`。

### 全局安装
```bash
sudo npm install -g <包名>          # prefix=/usr/local，需要 sudo
```

---

## 4. 代理

用本仓库脚本一键配置（详见 [`proxy-setup.md`](proxy-setup.md)）：

```bash
sudo ./apply-proxy.sh
```

要点：
- 写 `/etc/environment`（PAM）+ `/etc/profile.d/proxy.sh`（login shell）
- `no_proxy` 用**私有网段**覆盖本机（换 IP 不用改）
- apt 指定源（如 `mirrors.ustc.edu.cn`）走 `DIRECT` 直连

> pip / npm / git / devin / curl 都读环境变量；**corepack 例外**；**Docker 需单独配**。

---

## 5. PM2 + nginx + 应用部署

用本仓库脚本一键部署 Node 应用（详见 [`deploy-app.md`](deploy-app.md)）：

```bash
sudo ./deploy-app.sh --name myapp --port 3000 --domain app.example.com --user zilong
```

自动生成 PM2 ecosystem + nginx 反代 + logrotate + fail2ban。

### 关键约定
- Node **只监听 `127.0.0.1`**，对外统一走 nginx
- 应用目录 `/srv/<name>`、日志 `/var/log/<name>/`，属主为运行用户
- PM2 开机自启：`pm2 startup` + `pm2 save`（服务名 `pm2-<user>.service`）

```bash
# PM2 常用
sudo -u zilong pm2 list
sudo -u zilong pm2 logs <name>
sudo -u zilong pm2 restart <name>
```

---

## 6. 安全加固

```bash
sudo apt install -y ufw fail2ban certbot python3-certbot-nginx

# ufw：只放行 22/80/443（务必先放行 22 再 enable）
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp && sudo ufw allow 80/tcp && sudo ufw allow 443/tcp
sudo ufw --force enable
```

fail2ban：`/etc/fail2ban/jail.local` 里配全局策略 + `[sshd]`，应用再单独加 jail：
```ini
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
```

HTTPS（有域名后）：
```bash
sudo certbot --nginx -d app.example.com     # 自动续期由 certbot.timer 负责
```

> 命令速查见 [`proxy-setup.md`](proxy-setup.md) 与下文；被误封用 `fail2ban-client set <jail> unbanip <IP>`。

---

## 7. Devin CLI（AI 编码 agent）

```bash
# 安装（用户级）
curl -fsSL https://cli.devin.ai/install.sh | bash

# 登录（必须交互式，在 SSH 终端里）
devin auth login   # 或 devin setup
devin doctor       # 自检
```

- 位置：`~/.local/bin/devin`（`~/.profile` 已自动加 PATH）
- 联网走 `http_proxy/https_proxy`（reqwest 默认读环境变量）
- 完整说明见 [`devin-cli.md`](devin-cli.md)

---

## 8. 目录 / 日志规范

| 用途 | 路径 |
|---|---|
| 应用代码 | `/srv/<name>/` |
| 应用日志 | `/var/log/<name>/{out,err}.log` |
| nginx 站点 | `/etc/nginx/sites-available/<name>` → `sites-enabled/` |
| nginx 日志 | `/var/log/nginx/<name>.{access,error}.log` |
| logrotate | `/etc/logrotate.d/<name>` |
| fail2ban | `/etc/fail2ban/filter.d/<name>.conf` + `jail.local` |

---

## 9. 新机器复现步骤

```bash
# 1) 代理
git clone https://github.com/chenxianlong/proxy-setup.git && cd proxy-setup
sudo PROXY=http://<代理地址> APT_DIRECT_HOSTS="mirrors.ustc.edu.cn" ./apply-proxy.sh

# 2) 基础工具
sudo apt update && sudo apt install -y build-essential cmake pkg-config autoconf automake \
  libtool git jq yq tree zip unzip rsync tmux htop btop ncdu fzf direnv ca-certificates gnupg

# 3) Node + 包管理器
sudo npm install -g pm2 pnpm yarn
npm config set prefix /usr/local --global

# 4) 安全
sudo apt install -y ufw fail2ban certbot python3-certbot-nginx
#   ... 配 ufw / fail2ban（见第 6 节）

# 5) 部署应用
sudo ./deploy-app.sh --name myapp --port 3000 --domain app.example.com --user <用户>

# 6) Devin CLI
curl -fsSL https://cli.devin.ai/install.sh | bash
devin setup
```

---

## 10. 注意事项 / 已知坑

1. **corepack 在代理下不可用** → 用 `npm i -g` 代替。
2. **Docker 会绕过 ufw** → 容器端口绑 `127.0.0.1`，或单独配 iptables 规则。
3. **fail2ban 封的是 IP** → 固定 IP 建议加 `ignoreip`，防止把自己关在门外。
4. **systemd/cron 不继承代理环境变量** → 需要时用 `Environment=` 单独传。
5. **1 vCPU** → 编译慢、多容器/多实例会卡，建议升配。
6. **Swap 仅 512M** → 内存紧张可加 swapfile（见仓库 issue/PR 或自行 `fallocate`）。

---

*仓库其它文档：[代理配置](proxy-setup.md) · [Node 部署](deploy-app.md) · [Devin CLI](devin-cli.md)*
