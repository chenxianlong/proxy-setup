# deploy-app.sh —— Node 应用一键部署

传入**应用名 / 端口 / 域名 / 运行用户**，自动生成：

- **PM2** 应用定义（`ecosystem.config.js`，含日志路径、内存重启、优雅退出）
- **nginx** 反向代理（upstream keepalive、真实 IP 透传、WebSocket、健康检查）
- **logrotate** 日志轮转
- **fail2ban** jail（识别 nginx 401/403/429 并封 IP）
- 可选：脚手架一个零依赖、最小可跑的 `app.js`

---

## 依赖

| 组件 | 说明 |
|---|---|
| root | 需要写 `/etc` 下的配置 |
| node + pm2 | `sudo npm install -g pm2`（脚本会检测） |
| nginx | `sudo apt install -y nginx` |
| fail2ban | 可选，`sudo apt install -y fail2ban` |

---

## 用法

```bash
sudo ./deploy-app.sh --name <应用名> --port <端口> --domain <域名> [--user <用户>]
```

### 参数

| 参数 | 默认值 | 说明 |
|---|---|---|
| `--name` | 必填 | 应用名，用作 PM2 名 / 目录名 / jail 名 |
| `--port` | `3000` | Node 监听端口（脚本固定只监听 `127.0.0.1`） |
| `--domain` | `<name>.local` | nginx `server_name` |
| `--user` | `$SUDO_USER` 或第一个 uid≥1000 的用户 | 运行用户 |
| `--dir` | `/srv/<name>` | 应用目录 |
| `--entry` | `app.js` | 入口文件 |
| `--no-scaffold` | — | 不生成示例 `app.js` |
| `--remove` | — | 卸载配置（保留代码/日志） |
| `--purge` | — | 配合 `--remove`，连代码/日志一起删 |
| `-h, --help` | — | 帮助 |

### 完整示例

```bash
# 部署（自动生成配置 + 脚手架 + 启动）
sudo ./deploy-app.sh --name myapp --port 3000 --domain app.example.com --user zilong

# 本地测试（没配 DNS 时用 Host 头）
curl -H 'Host: app.example.com' http://127.0.0.1/
curl -H 'Host: app.example.com' http://127.0.0.1/healthz

# 查看日志
sudo -u zilong pm2 logs myapp

# 卸载
sudo ./deploy-app.sh --name myapp --remove          # 删配置
sudo ./deploy-app.sh --name myapp --remove --purge  # 再删代码/日志
```

---

## 生成的文件

| 文件 | 位置 |
|---|---|
| 应用目录 | `/srv/<name>/`（属主运行用户） |
| PM2 定义 | `/srv/<name>/ecosystem.config.js` |
| 应用日志 | `/var/log/<name>/{out,err}.log` |
| nginx 站点 | `/etc/nginx/sites-available/<name>` → `sites-enabled/<name>` |
| nginx 日志 | `/var/log/nginx/<name>.{access,error}.log` |
| logrotate | `/etc/logrotate.d/<name>` |
| fail2ban filter | `/etc/fail2ban/filter.d/<name>.conf` |
| fail2ban jail | 追加到 `/etc/fail2ban/jail.local` |

---

## 架构

```
Internet ──> ufw（只放行 22/80/443）──> nginx :80 ──> 127.0.0.1:<port> (Node/PM2)
                                          │
                    /var/log/nginx/<name>.access.log ──> fail2ban ──> nftables 封 IP
```

要点：**Node 只监听 127.0.0.1，绝不直接对外**；对外统一走 nginx。

---

## 脚本做的事（install 顺序）

1. 建目录 `/srv/<name>`、`/var/log/<name>`，属主设为运行用户
2. 若入口文件不存在且未加 `--no-scaffold`，生成示例 `app.js`
3. 生成 `ecosystem.config.js`
4. 生成 nginx 站点、启用、`nginx -t` 校验、reload
5. 生成 logrotate 配置
6. 生成 fail2ban filter 并追加 jail，重启 fail2ban
7. 配置 PM2 开机自启（若尚未配置），`startOrReload` + `save`
8. 打印访问方式与后续步骤

脚本**幂等**：重复执行会覆盖配置并 `reload`，不会重复追加 jail。

---

## 后续：上 HTTPS（有域名后）

```bash
# 1. nginx server_name 改成真实域名（部署时用 --domain 传入即可）
# 2. 域名解析到本机 IP
# 3. 一条命令签证书 + 自动改 nginx 配置
sudo certbot --nginx -d app.example.com
# 之后由 certbot.timer 自动续期
```

---

## 注意事项

- **运行用户**：PM2 开机自启服务绑定到该用户（`pm2-<user>.service`）。换用户部署需重新生成。
- **端口**：应用端口不要写进 ufw 放行；它只在本机监听，由 nginx 转发。
- **Docker 场景**：若以后用 Docker，注意 Docker 会绕过 ufw，容器端口要绑 `127.0.0.1`。
- **代理**：nginx 反代到本地应用不涉及代理；只有 nginx/应用主动访问外网时才需另配（nginx 不读环境变量）。
- **日志**：应用日志用 `copytruncate` 轮转（PM2 一直持有文件句柄）。

---

*配套：代理配置见 [`apply-proxy.sh`](apply-proxy.sh) / [`proxy-setup.md`](proxy-setup.md)*
