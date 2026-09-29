# proxy-setup

Linux 服务器代理配置工具：**全局 HTTP 代理 + 局域网/本机绕过（no_proxy）+ apt 指定源直连**。

适用 Debian / Ubuntu（使用 `apt` 与 `/etc/profile.d`）。

## 文件

| 文件 | 说明 |
|---|---|
| [`apply-proxy.sh`](apply-proxy.sh) | 幂等的一键配置脚本（必须以 root 运行） |
| [`proxy-setup.md`](proxy-setup.md) | 完整操作手册：原理、验证方法、注意事项、回滚 |

## 快速开始

```bash
# 1. 克隆
git clone https://github.com/chenxianlong/proxy-setup.git
cd proxy-setup

# 2. 运行（默认值见脚本顶部，可用环境变量覆盖）
sudo PROXY=http://10.75.0.6:6789 \
     APT_DIRECT_HOSTS="mirrors.ustc.edu.cn" \
     ./apply-proxy.sh
```

脚本做的事：

1. `/etc/environment` —— 写入代理变量 + `no_proxy`（PAM 登录生效）
2. `/etc/profile.d/proxy.sh` —— 写入代理变量 + `no_proxy`（login shell 生效）
3. `/etc/apt/apt.conf.d/80proxy` —— apt 全局代理
4. `/etc/apt/apt.conf.d/81proxy-direct` —— apt 对指定主机 `DIRECT`（绕过代理）

所有被修改的文件都会在同目录留下带时间戳的 `.bak.<时间戳>` 备份。

## 可配置项（环境变量）

| 变量 | 默认值 | 说明 |
|---|---|---|
| `PROXY` | `http://10.75.0.6:6789` | 代理地址 |
| `HOSTNAME_LOCAL` | 自动探测 `hostname` | 本机主机名（加入 no_proxy） |
| `IP_LOCAL` | 自动探测 | 本机 IP（加入 no_proxy） |
| `APT_DIRECT_HOSTS` | `mirrors.ustc.edu.cn` | 需直连的 apt 主机，空格分隔 |

## no_proxy 覆盖范围

```
localhost,127.0.0.1,::1,0.0.0.0,<主机名>,<本机IP>,
10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,169.254.0.0/16,fc00::/7,fe80::/10
```

## 验证

```bash
# 公网 -> 应走代理（连接目标 = 代理地址）
curl -sS -o /dev/null -w '%{remote_ip}:%{remote_port}\n' https://www.gstatic.com/generate_204

# 本机/内网 -> 应直连
curl -sS -o /dev/null -w '%{remote_ip}:%{remote_port}\n' http://127.0.0.1:<端口>/

# apt 是否对指定源直连（相对路径=直连，绝对URL=走代理）
sudo apt-get update -o Debug::Acquire::http=true 2>&1 | grep -E '^(GET|Host:)'
```

## 注意

- 新登录会话自动生效；**已打开的 shell 需重新登录**或 `source /etc/profile.d/proxy.sh`。
- systemd 服务、cron、Docker 容器默认**不继承**这些变量，需单独配置。
- apt **不读** `no_proxy`，绕过必须用 per-host `DIRECT`。
- 详细原理与回滚见 [`proxy-setup.md`](proxy-setup.md)。

## License

MIT
