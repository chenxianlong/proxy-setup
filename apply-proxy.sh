#!/usr/bin/env bash
#
# apply-proxy.sh —— 配置全局 HTTP 代理 + no_proxy 绕过 + apt 指定源直连
#
# 幂等：可重复执行。必须以 root 运行。
#
# 用法：
#   sudo PROXY=http://10.75.0.6:6789 APT_DIRECT_HOSTS="mirrors.ustc.edu.cn" ./apply-proxy.sh
#   # 或直接 sudo ./apply-proxy.sh   （使用下面的默认值 / 自动探测）
#
# 可用环境变量覆盖：
#   PROXY            代理地址（默认 http://10.75.0.6:6789）
#   HOSTNAME_LOCAL   本机主机名（默认自动探测 hostname）
#   IP_LOCAL         本机 IP（默认自动探测）
#   APT_DIRECT_HOSTS 需要直连的 apt 主机，空格分隔（默认 mirrors.ustc.edu.cn）
#
set -euo pipefail
export PATH=/sbin:/usr/sbin:/bin:/usr/bin

########## 按环境修改 / 覆盖 ##########
PROXY="${PROXY:-http://10.75.0.6:6789}"
HOSTNAME_LOCAL="${HOSTNAME_LOCAL:-$(hostname 2>/dev/null || echo localhost)}"
IP_LOCAL="${IP_LOCAL:-$(hostname -I 2>/dev/null | awk '{print $1}')}"
APT_DIRECT_HOSTS="${APT_DIRECT_HOSTS:-mirrors.ustc.edu.cn}"
#####################################

if [ "$(id -u)" -ne 0 ]; then
  echo "错误：请以 root 运行（sudo $0 或 su -c 'bash $0'）" >&2
  exit 1
fi

# 私有网段 / 环回 / 本机 绕过清单
NO_PROXY_VAL="localhost,127.0.0.1,::1,0.0.0.0,${HOSTNAME_LOCAL}"
[ -n "${IP_LOCAL:-}" ] && NO_PROXY_VAL="${NO_PROXY_VAL},${IP_LOCAL}"
NO_PROXY_VAL="${NO_PROXY_VAL},10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
NO_PROXY_VAL="${NO_PROXY_VAL},169.254.0.0/16,fc00::/7,fe80::/10"

STAMP="$(date +%F-%H%M%S)"
PROXY_VARS="http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy"

echo ">>> PROXY            = $PROXY"
echo ">>> HOSTNAME_LOCAL   = $HOSTNAME_LOCAL"
echo ">>> IP_LOCAL         = ${IP_LOCAL:-<未探测到>}"
echo ">>> APT_DIRECT_HOSTS = $APT_DIRECT_HOSTS"
echo ">>> no_proxy         = $NO_PROXY_VAL"
echo

# ---------- 1) /etc/environment（PAM 全局，ssh/su -/图形登录） ----------
echo "[1/4] 配置 /etc/environment"
cp -a /etc/environment "/etc/environment.bak.${STAMP}"
sed -i '/^[Nn][Oo]_[Pp][Rr][Oo][Xx][Yy]=/d' /etc/environment
for v in $PROXY_VARS; do
  grep -q "^${v}=" /etc/environment || printf '%s="%s"\n' "$v" "$PROXY" >> /etc/environment
done
printf 'no_proxy="%s"\n' "$NO_PROXY_VAL" >> /etc/environment
printf 'NO_PROXY="%s"\n' "$NO_PROXY_VAL" >> /etc/environment

# ---------- 2) /etc/profile.d/proxy.sh（login shell） ----------
echo "[2/4] 配置 /etc/profile.d/proxy.sh"
touch /etc/profile.d/proxy.sh
cp -a /etc/profile.d/proxy.sh "/etc/profile.d/proxy.sh.bak.${STAMP}"
sed -i '/^export [Nn][Oo]_[Pp][Rr][Oo][Xx][Yy]=/d' /etc/profile.d/proxy.sh
for v in $PROXY_VARS; do
  grep -q "^export ${v}=" /etc/profile.d/proxy.sh || \
    printf 'export %s="%s"\n' "$v" "$PROXY" >> /etc/profile.d/proxy.sh
done
printf 'export no_proxy="%s"\n' "$NO_PROXY_VAL" >> /etc/profile.d/proxy.sh
printf 'export NO_PROXY="%s"\n' "$NO_PROXY_VAL" >> /etc/profile.d/proxy.sh
chmod 0644 /etc/profile.d/proxy.sh

# ---------- 3) apt 全局代理（80proxy） ----------
echo "[3/4] 配置 /etc/apt/apt.conf.d/80proxy"
if [ ! -f /etc/apt/apt.conf.d/80proxy ]; then
  cat > /etc/apt/apt.conf.d/80proxy <<EOF
Acquire::http::Proxy "${PROXY}";
Acquire::https::Proxy "${PROXY}";
EOF
else
  cp -a /etc/apt/apt.conf.d/80proxy "/etc/apt/apt.conf.d/80proxy.bak.${STAMP}"
fi

# ---------- 4) apt 指定主机直连（81proxy-direct，编号大=优先） ----------
echo "[4/4] 配置 /etc/apt/apt.conf.d/81proxy-direct"
{
  echo "// 以下主机绕过全局代理，直连（由 apply-proxy.sh 生成）"
  for h in $APT_DIRECT_HOSTS; do
    echo "Acquire::http::Proxy::${h} \"DIRECT\";"
    echo "Acquire::https::Proxy::${h} \"DIRECT\";"
  done
} > /etc/apt/apt.conf.d/81proxy-direct
chmod 0644 /etc/apt/apt.conf.d/81proxy-direct

echo
echo "配置完成。当前内容："
echo "----- /etc/environment -----";                    cat /etc/environment
echo "----- /etc/profile.d/proxy.sh -----";              cat /etc/profile.d/proxy.sh
echo "----- /etc/apt/apt.conf.d/80proxy -----";          cat /etc/apt/apt.conf.d/80proxy
echo "----- /etc/apt/apt.conf.d/81proxy-direct -----";   cat /etc/apt/apt.conf.d/81proxy-direct
echo
echo "提示：新登录会话自动生效；当前已开的 shell 需重新登录，或执行  source /etc/profile.d/proxy.sh"
