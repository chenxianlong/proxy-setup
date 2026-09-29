# 服务器代理设置手册（可复用）

> 记录一次完整的「全局 HTTP 代理 + 局域网/本机绕过 + apt 指定源直连」配置过程。
> 一键脚本见仓库根目录 [`apply-proxy.sh`](apply-proxy.sh)（幂等，可重复执行）。

---

## 1. 适用场景

- 机器能直连公网，但被要求**默认走 HTTP 代理**；
- 同时希望**局域网网段、本机地址、环回地址不走代理**；
- apt 的某个镜像源（如 `mirrors.ustc.edu.cn`）希望**绕过代理直连**。

需要按环境调整的参数：

| 参数 | 示例值 | 说明 |
|---|---|---|
| `PROXY` | `http://10.75.0.6:6789` | 代理地址 |
| `APT_DIRECT_HOSTS` | `mirrors.ustc.edu.cn` | 需要直连的 apt 主机（空格分隔多个） |

> **本机地址不写死**：`no_proxy` 统一用私有网段（`10.0.0.0/8` 等）覆盖，
> 这样 DHCP 换 IP、只要还在同一网段，规则都不用改。

---

## 2. 涉及的配置文件一览

| 文件 | 作用 | 加载时机 |
|---|---|---|
| `/etc/environment` | 全局代理变量 + `no_proxy` | PAM 登录（ssh / `su -` / 图形登录）时 |
| `/etc/profile.d/proxy.sh` | 全局代理变量 + `no_proxy` | login shell 启动（`/etc/profile`）时 |
| `/etc/apt/apt.conf.d/80proxy` | apt 全局代理 | apt 每次运行 |
| `/etc/apt/apt.conf.d/81proxy-direct` | apt 指定主机直连（DIRECT） | apt 每次运行（编号大，优先于 80） |

> **为什么要写两处（`/etc/environment` 和 `/etc/profile.d/proxy.sh`）？**
> 两者加载机制不同：
> - `/etc/environment` 只对**走 PAM 的登录**生效；
> - `/etc/profile.d/*.sh` 只对**login shell** 生效（例如 `bash -l` 不经 PAM）。
>
> 两边都写，才能让所有登录方式都带上代理和 `no_proxy`。

---

## 3. 一键配置

```bash
# 克隆
git clone https://github.com/chenxianlong/proxy-setup.git
cd proxy-setup

# 以 root 运行（默认值见脚本顶部，可用环境变量覆盖）
sudo PROXY=http://10.75.0.6:6789 \
     APT_DIRECT_HOSTS="mirrors.ustc.edu.cn" \
     ./apply-proxy.sh
```

脚本逻辑（幂等：先删除旧的 `no_proxy` 行再追加；代理变量已存在则不重复写）：

1. `/etc/environment` —— 写入代理变量 + `no_proxy`
2. `/etc/profile.d/proxy.sh` —— 写入代理变量 + `no_proxy`
3. `/etc/apt/apt.conf.d/80proxy` —— apt 全局代理（已存在则备份）
4. `/etc/apt/apt.conf.d/81proxy-direct` —— apt 对指定主机 `DIRECT`

关键片段：

```bash
# 私有网段 / 环回 / 链路本地 绕过清单
# 用整个网段覆盖本机，DHCP 换 IP 也不用改
NO_PROXY_VAL="localhost,127.0.0.1,::1,0.0.0.0"
NO_PROXY_VAL="${NO_PROXY_VAL},10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
NO_PROXY_VAL="${NO_PROXY_VAL},169.254.0.0/16,fc00::/7,fe80::/10"
```

---

## 4. 实际写入的内容

### `no_proxy`（`/etc/environment` 与 `/etc/profile.d/proxy.sh` 一致）
```
localhost,127.0.0.1,::1,0.0.0.0,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,169.254.0.0/16,fc00::/7,fe80::/10
```

### `/etc/environment`
```
http_proxy="http://10.75.0.6:6789"
https_proxy="http://10.75.0.6:6789"
HTTP_PROXY="http://10.75.0.6:6789"
HTTPS_PROXY="http://10.75.0.6:6789"
ALL_PROXY="http://10.75.0.6:6789"
all_proxy="http://10.75.0.6:6789"
no_proxy="localhost,127.0.0.1,::1,0.0.0.0,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,169.254.0.0/16,fc00::/7,fe80::/10"
NO_PROXY="localhost,127.0.0.1,::1,0.0.0.0,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,169.254.0.0/16,fc00::/7,fe80::/10"
```

### `/etc/profile.d/proxy.sh`
```
export http_proxy="http://10.75.0.6:6789"
export https_proxy="http://10.75.0.6:6789"
export HTTP_PROXY="http://10.75.0.6:6789"
export HTTPS_PROXY="http://10.75.0.6:6789"
export ALL_PROXY="http://10.75.0.6:6789"
export all_proxy="http://10.75.0.6:6789"
export no_proxy="localhost,127.0.0.1,::1,0.0.0.0,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,169.254.0.0/16,fc00::/7,fe80::/10"
export NO_PROXY="localhost,127.0.0.1,::1,0.0.0.0,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,169.254.0.0/16,fc00::/7,fe80::/10"
```

### `/etc/apt/apt.conf.d/80proxy`
```
Acquire::http::Proxy "http://10.75.0.6:6789";
Acquire::https::Proxy "http://10.75.0.6:6789";
```

### `/etc/apt/apt.conf.d/81proxy-direct`
```
// 以下主机绕过全局代理，直连（由 apply-proxy.sh 生成）
Acquire::http::Proxy::mirrors.ustc.edu.cn "DIRECT";
Acquire::https::Proxy::mirrors.ustc.edu.cn "DIRECT";
```

---

## 5. no_proxy 规则说明

| 条目 | 含义 |
|---|---|
| `localhost`, `127.0.0.1`, `::1`, `0.0.0.0` | 环回 |
| `10.0.0.0/8` | 私有网段 A 类（本机 10.x 地址也在此范围内） |
| `172.16.0.0/12` | 私有网段 B 类 |
| `192.168.0.0/16` | 私有网段 C 类 |
| `169.254.0.0/16` | 链路本地 |
| `fc00::/7`, `fe80::/10` | IPv6 私有 / 链路本地 |

> 用网段而非具体 IP，DHCP 换地址（同段）时无需修改。
> CIDR 支持：`curl`、`go`、`python-requests`、`node` 等新版本都认 `x.x.x.x/nn`；
> 老版本 `wget` 只认域名后缀，对 CIDR 可能无效。

---

## 6. 验证方法

```bash
# (1) 新登录会话是否带上变量（走 PAM）
su -l $USER -c 'env | grep -iE "no_proxy|http_proxy"'

# (2) 不经 PAM 的 login shell 是否也带上（读 profile.d）
env -i bash -lc 'env | grep -iE "no_proxy|http_proxy"'

# (3) 公网 -> 应走代理（remote 应显示代理 IP:端口）
curl -sS -o /dev/null -w 'HTTP=%{http_code} 连接=%{remote_ip}:%{remote_port}\n' \
  https://www.gstatic.com/generate_204

# (4) 本机地址 -> 应直连（remote 应是本机地址，而不是代理）
curl -sS -o /dev/null -w 'HTTP=%{http_code} 连接=%{remote_ip}:%{remote_port}\n' \
  http://127.0.0.1:<任意本地端口>/

# (5) apt 是否对指定源直连（看请求行：相对路径=直连，绝对 URL=走代理）
apt-get update -o Debug::Acquire::http=true 2>&1 | grep -E '^(GET|Host:)'
```

判定要点：
- **走代理**：apt 请求行是 `GET http://主机/... HTTP/1.1`（绝对 URL）。
- **直连**：apt 请求行是 `GET /路径 HTTP/1.1`（相对路径）。
- **代理生效**：curl 的 `remote_ip:remote_port` 等于代理地址端口。

---

## 7. 生效条件与注意事项

1. **文件持久**：以上都写在磁盘上，重启会话 / 重启服务器后依旧生效。
2. **已打开的进程不会更新**：环境变量在进程启动时快照。
   - 当前已开的终端 / 服务需**重新登录**才带上新配置；
   - 想在当前 shell 立刻生效：`source /etc/profile.d/proxy.sh`。
3. **不自动继承的场景**：systemd 服务、cron、Docker 容器默认**不读** `/etc/environment` 和 `/etc/profile.d`，需单独配置：
   - systemd：在 unit 里用 `Environment=` / `EnvironmentFile=`；
   - Docker：`~/.docker/config.json` 的 `proxies` 字段，或容器内单独配置。
4. **apt 不读 `no_proxy`**：apt 用的是 `apt.conf` 里的 `Acquire::*::Proxy`，绕过必须靠 `81proxy-direct` 这种 per-host `DIRECT`。
5. `security.debian.org` 等未列入 `APT_DIRECT_HOSTS` 的源仍走代理，如需直连追加到该变量即可。

---

## 8. 回滚

```bash
# 恢复备份（时间戳按实际替换）
cp -a /etc/environment.bak.<STAMP>            /etc/environment
cp -a /etc/profile.d/proxy.sh.bak.<STAMP>     /etc/profile.d/proxy.sh
rm -f /etc/apt/apt.conf.d/81proxy-direct       # 删除直连规则
# apt 全局代理如也想去掉：rm -f /etc/apt/apt.conf.d/80proxy
su -l $USER -c 'env | grep -i proxy'           # 重新登录确认
```

---

## 9. 备份位置

被修改的文件都会在同目录生成带时间戳的备份：

| 文件 | 备份 |
|---|---|
| `/etc/environment` | `/etc/environment.bak.<STAMP>` |
| `/etc/profile.d/proxy.sh` | `/etc/profile.d/proxy.sh.bak.<STAMP>` |
| `/etc/apt/apt.conf.d/80proxy` | `/etc/apt/apt.conf.d/80proxy.bak.<STAMP>` |

---

*最后更新：2026-09-29*
