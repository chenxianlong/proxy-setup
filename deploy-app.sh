#!/usr/bin/env bash
#
# deploy-app.sh —— 一键为 Node 应用生成完整部署配置
#
#   传入：应用名 / 端口 / 域名 / 运行用户
#   生成：PM2(ecosystem) + nginx 反代 + logrotate + fail2ban
#   可选：脚手架一个最小可跑的 app.js
#
# 用法（需要 root）：
#   sudo ./deploy-app.sh --name myapp --port 3000 --domain app.example.com --user zilong
#   sudo ./deploy-app.sh --name myapp --remove          # 卸载配置（保留代码/日志）
#   sudo ./deploy-app.sh --name myapp --remove --purge  # 连代码/日志一起删
#
# 参数：
#   --name   <name>     应用名（必填），用作 PM2 名 / 目录名 / jail 名
#   --port   <port>     Node 监听端口（默认 3000，只监听 127.0.0.1）
#   --domain <domain>   nginx server_name（默认 <name>.local）
#   --user   <user>     运行用户（默认 $SUDO_USER 或第一个 uid>=1000 的用户）
#   --dir    <path>     应用目录（默认 /srv/<name>）
#   --entry  <file>     入口文件（默认 app.js）
#   --no-scaffold       不生成示例 app.js
#   --remove            卸载
#   --purge             卸载时连应用目录和日志一起删
#   -h, --help          帮助
#
set -euo pipefail
export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# ----------------------------- 默认值 -----------------------------
APP_NAME=""
APP_PORT="3000"
APP_DOMAIN=""
APP_USER="${SUDO_USER:-}"
APP_DIR=""
APP_ENTRY="app.js"
SCAFFOLD=1
REMOVE=0
PURGE=0

c_info() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
c_ok()   { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
c_warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
die()    { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

usage() { awk 'NR>2 { if ($0 !~ /^#/) exit; sub(/^# ?/,""); print }' "$0"; }

# ----------------------------- 解析参数 -----------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --name)        APP_NAME="${2:-}";   shift 2;;
    --port)        APP_PORT="${2:-}";   shift 2;;
    --domain)      APP_DOMAIN="${2:-}"; shift 2;;
    --user)        APP_USER="${2:-}";   shift 2;;
    --dir)         APP_DIR="${2:-}";    shift 2;;
    --entry)       APP_ENTRY="${2:-}";  shift 2;;
    --no-scaffold) SCAFFOLD=0; shift;;
    --remove)      REMOVE=1; shift;;
    --purge)       PURGE=1; shift;;
    -h|--help)     usage; exit 0;;
    *)             die "未知参数：$1（用 --help 查看用法）";;
  esac
done

# ----------------------------- 校验 -----------------------------
[ "$(id -u)" -eq 0 ] || die "请以 root 运行：sudo $0 ..."
[ -n "$APP_NAME" ]   || die "必须指定 --name（用 --help 查看用法）"
[[ "$APP_NAME" =~ ^[A-Za-z0-9._-]+$ ]] || die "应用名只能含字母数字 . _ -"
[[ "$APP_PORT" =~ ^[0-9]+$ ]] || die "端口必须是数字"

if [ -z "$APP_USER" ]; then
  APP_USER="$(awk -F: '$3>=1000 && $3<60000 {print $1; exit}' /etc/passwd || true)"
fi
[ -n "$APP_USER" ] || APP_USER="root"
id "$APP_USER" >/dev/null 2>&1 || die "用户不存在：$APP_USER"
APP_HOME="$(getent passwd "$APP_USER" | cut -d: -f6)"

[ -n "$APP_DIR" ]    || APP_DIR="/srv/$APP_NAME"
[ -n "$APP_DOMAIN" ] || APP_DOMAIN="$APP_NAME.local"

NGINX_SITE="/etc/nginx/sites-available/$APP_NAME"
LOGROTATE="/etc/logrotate.d/$APP_NAME"
F2B_FILTER="/etc/fail2ban/filter.d/$APP_NAME.conf"
F2B_JAIL="/etc/fail2ban/jail.local"
LOG_DIR="/var/log/$APP_NAME"
PM2_BIN="$(command -v pm2 || true)"

# 渲染占位符的小工具
render() {
  sed -e "s|__APP_NAME__|$APP_NAME|g" \
      -e "s|__PORT__|$APP_PORT|g" \
      -e "s|__DOMAIN__|$APP_DOMAIN|g" \
      -e "s|__USER__|$APP_USER|g" \
      -e "s|__DIR__|$APP_DIR|g" \
      -e "s|__ENTRY__|$APP_ENTRY|g"
}

run_as_user() {
  local u="$1"; shift
  local h; h="$(getent passwd "$u" | cut -d: -f6)"
  runuser -u "$u" -- env HOME="$h" \
    PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" "$@"
}

# =====================================================================
# 卸载
# =====================================================================
if [ "$REMOVE" -eq 1 ]; then
  c_info "卸载 $APP_NAME ..."

  if [ -n "$PM2_BIN" ] && run_as_user "$APP_USER" "$PM2_BIN" describe "$APP_NAME" >/dev/null 2>&1; then
    run_as_user "$APP_USER" "$PM2_BIN" delete "$APP_NAME"
    run_as_user "$APP_USER" "$PM2_BIN" save >/dev/null 2>&1 || true
    c_ok "PM2 应用已删除"
  fi

  if [ -L "/etc/nginx/sites-enabled/$APP_NAME" ]; then
    rm -f "/etc/nginx/sites-enabled/$APP_NAME"
    c_ok "nginx 站点已禁用"
  fi
  [ -f "$NGINX_SITE" ] && { rm -f "$NGINX_SITE"; c_ok "nginx 配置已删除"; }
  nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true

  [ -f "$LOGROTATE" ] && { rm -f "$LOGROTATE"; c_ok "logrotate 已删除"; }

  if [ -f "$F2B_FILTER" ]; then rm -f "$F2B_FILTER"; c_ok "fail2ban filter 已删除"; fi
  if [ -f "$F2B_JAIL" ] && grep -q "^\[$APP_NAME\]" "$F2B_JAIL"; then
    awk -v sec="[$APP_NAME]" '
      $0==sec {skip=1; next}
      skip && /^\[/ {skip=0}
      !skip {print}
    ' "$F2B_JAIL" > "$F2B_JAIL.tmp" && mv "$F2B_JAIL.tmp" "$F2B_JAIL"
    systemctl restart fail2ban >/dev/null 2>&1 || true
    c_ok "fail2ban jail 已删除"
  fi

  if [ "$PURGE" -eq 1 ]; then
    rm -rf "$APP_DIR" "$LOG_DIR"
    c_ok "应用目录与日志已删除（--purge）"
  fi
  c_ok "卸载完成"
  exit 0
fi

# =====================================================================
# 安装
# =====================================================================
[ -n "$PM2_BIN" ] || die "找不到 pm2，请先安装：sudo npm install -g pm2"
command -v nginx >/dev/null || die "找不到 nginx，请先安装：sudo apt install -y nginx"
command -v fail2ban-client >/dev/null || c_warn "未检测到 fail2ban，将跳过 jail 配置"

c_info "部署 $APP_NAME （port=$APP_PORT domain=$APP_DOMAIN user=$APP_USER dir=$APP_DIR）"

# ---------- 1) 目录 ----------
mkdir -p "$APP_DIR" "$LOG_DIR"
chown "$APP_USER:$APP_USER" "$APP_DIR" "$LOG_DIR"
chmod 750 "$APP_DIR" "$LOG_DIR"
c_ok "目录：$APP_DIR , $LOG_DIR（属主 $APP_USER）"

# ---------- 2) 脚手架 app.js ----------
if [ "$SCAFFOLD" -eq 1 ] && [ ! -f "$APP_DIR/$APP_ENTRY" ]; then
  render > "$APP_DIR/$APP_ENTRY" <<'EOF'
'use strict';
// 由 deploy-app.sh 生成的示例服务（零依赖）
const http = require('http');
const os = require('os');
const PORT = Number(process.env.PORT) || __PORT__;
const HOST = process.env.HOST || '127.0.0.1';

const server = http.createServer((req, res) => {
  if (req.url === '/healthz') { res.writeHead(200, {'Content-Type':'text/plain'}); return res.end('ok\n'); }
  if (req.url.startsWith('/private')) {
    res.writeHead(401, {'Content-Type':'application/json'}); return res.end('{"error":"unauthorized"}\n');
  }
  res.writeHead(200, {'Content-Type':'application/json; charset=utf-8'});
  res.end(JSON.stringify({
    app: '__APP_NAME__', pid: process.pid, hostname: os.hostname(),
    clientIp: req.headers['x-real-ip'] || req.socket.remoteAddress,
    forwardedFor: req.headers['x-forwarded-for'] || null,
    url: req.url, time: new Date().toISOString(), uptimeSec: Math.round(process.uptime()),
  }, null, 2) + '\n');
});
server.listen(PORT, HOST, () => console.log(`[__APP_NAME__] listening on http://${HOST}:${PORT}`));

const shutdown = s => { console.log(`[__APP_NAME__] ${s}`); server.close(()=>process.exit(0)); setTimeout(()=>process.exit(1),5000).unref(); };
process.on('SIGINT',  () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
EOF
  chown "$APP_USER:$APP_USER" "$APP_DIR/$APP_ENTRY"
  c_ok "已生成示例入口 $APP_DIR/$APP_ENTRY"
fi

# ---------- 3) PM2 ecosystem ----------
render > "$APP_DIR/ecosystem.config.js" <<'EOF'
// 由 deploy-app.sh 生成
module.exports = {
  apps: [{
    name: '__APP_NAME__',
    script: '__DIR__/__ENTRY__',
    cwd: '__DIR__',
    instances: 1,
    exec_mode: 'fork',
    env: { NODE_ENV: 'production', PORT: __PORT__, HOST: '127.0.0.1' },
    out_file: '/var/log/__APP_NAME__/out.log',
    error_file: '/var/log/__APP_NAME__/err.log',
    merge_logs: true,
    time: true,
    autorestart: true,
    max_memory_restart: '300M',
    kill_timeout: 5000,
    watch: false,
  }],
};
EOF
chown "$APP_USER:$APP_USER" "$APP_DIR/ecosystem.config.js"
c_ok "已生成 $APP_DIR/ecosystem.config.js"

# ---------- 4) nginx ----------
render > "$NGINX_SITE" <<'EOF'
# 由 deploy-app.sh 生成
upstream __APP_NAME___upstream {
    server 127.0.0.1:__PORT__;
    keepalive 32;
}

server {
    listen 80;
    listen [::]:80;
    server_name __DOMAIN__;

    access_log /var/log/nginx/__APP_NAME__.access.log;
    error_log  /var/log/nginx/__APP_NAME__.error.log warn;

    client_max_body_size 10m;
    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options SAMEORIGIN always;
    add_header Referrer-Policy no-referrer-when-downgrade always;

    location = /healthz { access_log off; proxy_pass http://__APP_NAME___upstream; }

    location / {
        proxy_pass http://__APP_NAME___upstream;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout    60s;
        proxy_connect_timeout  5s;
    }

    location /ws/ {
        proxy_pass http://__APP_NAME___upstream;
        proxy_http_version 1.1;
        proxy_set_header Upgrade    $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host       $host;
        proxy_set_header X-Real-IP  $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 3600s;
    }
}
EOF
ln -sf "$NGINX_SITE" "/etc/nginx/sites-enabled/$APP_NAME"
nginx -t >/dev/null 2>&1 || die "nginx 配置校验失败，请检查 $NGINX_SITE"
systemctl reload nginx 2>/dev/null || systemctl restart nginx
c_ok "nginx 站点已启用并重载（server_name=$APP_DOMAIN）"

# ---------- 5) logrotate ----------
cat > "$LOGROTATE" <<EOF
# 由 deploy-app.sh 生成
/var/log/$APP_NAME/*.log {
    daily
    rotate 14
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
    create 0640 $APP_USER $APP_USER
}
EOF
c_ok "logrotate 已配置：$LOGROTATE"

# ---------- 6) fail2ban ----------
if command -v fail2ban-client >/dev/null; then
  cat > "$F2B_FILTER" <<'EOF'
[Definition]
failregex = ^<HOST> -.*"(GET|POST|HEAD|PUT|DELETE) [^"]*" (401|403|429) 
ignoreregex =
EOF
  touch "$F2B_JAIL"
  if ! grep -q "^\[$APP_NAME\]" "$F2B_JAIL"; then
    cat >> "$F2B_JAIL" <<EOF

[$APP_NAME]
enabled  = true
port     = http,https
filter   = $APP_NAME
logpath  = /var/log/nginx/$APP_NAME.access.log
maxretry = 10
findtime = 5m
bantime  = 1h
EOF
  fi
  systemctl restart fail2ban
  c_ok "fail2ban jail 已配置：[$APP_NAME]"
fi

# ---------- 7) PM2 启动 + 开机自启 ----------
if [ ! -f "/etc/systemd/system/pm2-$APP_USER.service" ]; then
  "$PM2_BIN" startup systemd -u "$APP_USER" --hp "$APP_HOME" >/dev/null 2>&1 && \
    c_ok "已为 $APP_USER 配置 PM2 开机自启"
fi
run_as_user "$APP_USER" bash -c "cd '$APP_DIR' && '$PM2_BIN' startOrReload ecosystem.config.js" >/dev/null
run_as_user "$APP_USER" "$PM2_BIN" save >/dev/null 2>&1 || true
c_ok "PM2 已启动并保存"

# ---------- 8) 汇总 ----------
echo
c_ok "部署完成！"
cat <<EOF

  应用        : $APP_NAME
  运行用户    : $APP_USER
  应用目录    : $APP_DIR
  监听        : 127.0.0.1:$APP_PORT  （只对本机）
  对外域名    : http://$APP_DOMAIN/  （nginx :80）
  日志        : $LOG_DIR/*.log
  PM2         : sudo -u $APP_USER pm2 logs $APP_NAME
  健康检查    : curl -H 'Host: $APP_DOMAIN' http://127.0.0.1/healthz

  本地测试（未配 DNS 时）：
    curl -H 'Host: $APP_DOMAIN' http://127.0.0.1/

  上 HTTPS（有域名后）：
    sudo certbot --nginx -d $APP_DOMAIN

  卸载：
    sudo $0 --name $APP_NAME --remove [--purge]
EOF
