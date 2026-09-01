#!/usr/bin/env bash
set -euo pipefail

SOCKS_USER="${1:-edgeuser}"
SOCKS_PORT="${2:-1080}"
SOCKS_PASS="${3:-}"

if [ "$(id -u)" -ne 0 ]; then
  echo "请用 root 运行：sudo bash setup-socks5.sh"
  exit 1
fi

if [ -z "$SOCKS_PASS" ]; then
  SOCKS_PASS="$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-20)"
fi

IFACE="$(ip route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}')"
if [ -z "$IFACE" ]; then
  echo "无法自动识别默认网卡"
  exit 1
fi

apt update
apt install -y dante-server ufw curl openssl

if id "$SOCKS_USER" >/dev/null 2>&1; then
  echo "用户 $SOCKS_USER 已存在，更新密码"
else
  useradd -r -s /usr/sbin/nologin "$SOCKS_USER"
fi

echo "${SOCKS_USER}:${SOCKS_PASS}" | chpasswd

cp /etc/danted.conf "/etc/danted.conf.bak.$(date +%s)" 2>/dev/null || true

cat > /etc/danted.conf <<EOF
logoutput: /var/log/danted.log

internal: 0.0.0.0 port = ${SOCKS_PORT}
external: ${IFACE}

clientmethod: none
socksmethod: username

user.privileged: root
user.unprivileged: nobody

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: connect
    protocol: tcp
    log: connect disconnect error
}
EOF

ufw allow OpenSSH
ufw allow "${SOCKS_PORT}/tcp"
ufw --force enable

systemctl enable danted
systemctl restart danted

PUBLIC_IP="$(curl -4 -s https://ifconfig.me || true)"

echo
echo "SOCKS5 已部署完成"
echo "服务器公网 IP: ${PUBLIC_IP:-请自行查看 Linode IP}"
echo "网卡: ${IFACE}"
echo "端口: ${SOCKS_PORT}"
echo "用户名: ${SOCKS_USER}"
echo "密码: ${SOCKS_PASS}"
echo
echo "本机测试命令："
echo "curl -4 --socks5-hostname '${SOCKS_USER}:${SOCKS_PASS}@127.0.0.1:${SOCKS_PORT}' https://cloudflare.com/cdn-cgi/trace"
echo
echo "edgetunnel PATH："
echo "/gs5=${SOCKS_USER}:${SOCKS_PASS}@${PUBLIC_IP:-你的Linode公网IP}:${SOCKS_PORT}"
echo
echo "服务状态："
systemctl --no-pager --full status danted || true