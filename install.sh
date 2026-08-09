#!/bin/bash
# ======================================================================
# 🛡️ VPN Amnezia Infrastructure — Установочный скрипт (Ubuntu 24.04)
# ======================================================================
set -e

if [ "$1" = "--check" ]; then
    echo "🔍 VPN Infrastructure Check"
    # Fail2Ban checks
    systemctl is-active --quiet fail2ban && echo "✅ fail2ban.service (active)" || echo "❌ fail2ban.service (inactive)"
    sudo fail2ban-client status vpn-monitoring &>/dev/null && echo "✅ [vpn-monitoring] jail" || echo "❌ [vpn-monitoring] jail missing"
    [ -f "/etc/fail2ban/action.d/telegram-ban.conf" ] && echo "✅ telegram-ban.conf" || echo "❌ telegram-ban.conf missing"
    echo "============================"
    for script in vpn-bot-listener.sh vpn-alert.sh audit-peers.sh cleanup-orphans.sh resource-monitor.sh vpn-monitor.sh metrics-logger.sh; do
        [ -f "/root/scripts/$script" ] && echo "✅ $script" || echo "❌ $script отсутствует"
    done
    [ -f "/root/.vpn-env" ] && echo "✅ /root/.vpn-env" || echo "❌ /root/.vpn-env отсутствует"
    for svc in vpn-bot status; do
        systemctl is-active --quiet "$svc.service" && echo "✅ $svc.service (active)" || echo "❌ $svc.service (inactive)"
    done
    docker ps --filter "name=amnezia-awg2" --format "{{.Names}}" | grep -q "amnezia-awg2" && echo "✅ amnezia-awg2 (running)" || echo "❌ amnezia-awg2 (not running)"
    systemctl is-active --quiet nginx && echo "✅ nginx (active)" || echo "❌ nginx (inactive)"
    crontab -l 2>/dev/null | grep -q "vpn-alert\|metrics-logger\|cleanup-orphans\|resource-monitor\|vpn-monitor" && echo "✅ cron-задачи" || echo "❌ cron-задачи отсутствуют"
    docker exec amnezia-awg2 wg show > /dev/null 2>&1 && echo "✅ WireGuard (отвечает)" || echo "❌ WireGuard (не отвечает)"
    ping -c 1 -W 2 1.1.1.1 > /dev/null 2>&1 && echo "✅ Ping 1.1.1.1" || echo "❌ Ping 1.1.1.1"
    # Fail2Ban checks
    systemctl is-active --quiet fail2ban && echo "✅ fail2ban.service (active)" || echo "❌ fail2ban.service (inactive)"
    sudo fail2ban-client status vpn-monitoring &>/dev/null && echo "✅ [vpn-monitoring] jail" || echo "❌ [vpn-monitoring] jail missing"
    [ -f "/etc/fail2ban/action.d/telegram-ban.conf" ] && echo "✅ telegram-ban.conf" || echo "❌ telegram-ban.conf missing"
    echo "============================"
    exit 0
fi

if [ "$EUID" -ne 0 ]; then
    echo "❌ Запустите от root"
    exit 1
fi

if ! grep -q 'Ubuntu 24\.04' /etc/os-release 2>/dev/null; then
    echo "❌ Только Ubuntu 24.04 LTS"
    exit 1
fi

echo "🚀 Установка VPN Amnezia Infrastructure"
read -p "Токен Telegram-бота: " BOT_TOKEN
read -p "Chat ID: " CHAT_ID
read -p "Пароль Flask: " FLASK_PASSWORD

apt update && apt upgrade -y
apt install -y docker.io python3 python3-pip nginx fail2ban ufw netfilter-persistent iptables-persistent curl git
systemctl enable --now docker

if ! docker ps | grep -q "amnezia-awg2"; then
    curl -s https://raw.githubusercontent.com/amnezia-vpn/amneziawg-docker/master/install.sh | bash
fi

REPO_DIR="/opt/vpn-amnezia-infrastructure"
if [ ! -d "$REPO_DIR" ]; then
    git clone https://github.com/baltazor70/vpn-amnezia-infrastructure.git "$REPO_DIR"
else
    cd "$REPO_DIR" && git pull

# 🔧 Deploy Fail2Ban configuration
if [ -f "$REPO_DIR/deploy/fail2ban/deploy.sh" ]; then
    echo "🛡 Deploying Fail2Ban Telegram alerts..."
    bash "$REPO_DIR/deploy/fail2ban/deploy.sh"
fi
fi

mkdir -p /root/scripts
cp -f "$REPO_DIR/scripts/"*.sh /root/scripts/
chmod +x /root/scripts/*.sh

cat > /root/.vpn-env << EOF
BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"
FLASK_ADMIN_PASSWORD="${FLASK_PASSWORD}"
EOF
chmod 600 /root/.vpn-env

pip3 install flask psutil
mkdir -p /opt/vpn-status/templates
cp -f "$REPO_DIR/flask/app.py" /opt/vpn-status/
cp -f "$REPO_DIR/flask/templates/index.html" /opt/vpn-status/templates/

mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout /etc/nginx/ssl/vpn-status.key -out /etc/nginx/ssl/vpn-status.crt -subj "/C=RU/ST=Moscow/L=Moscow/O=VPN/CN=vpn.local"

cat > /etc/nginx/sites-available/vpn-status << 'NGINX'
server {
    listen 45678 ssl;
    server_name _;
    ssl_certificate /etc/nginx/ssl/vpn-status.crt;
    ssl_certificate_key /etc/nginx/ssl/vpn-status.key;
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
NGINX
ln -sf /etc/nginx/sites-available/vpn-status /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
systemctl restart nginx

cat > /etc/systemd/system/status.service << 'UNIT'
[Unit]
Description=VPN Status Web Page
After=network.target
[Service]
Type=simple
User=root
WorkingDirectory=/opt/vpn-status
ExecStart=/usr/bin/python3 /opt/vpn-status/app.py
Restart=always
[Install]
WantedBy=multi-user.target
UNIT

cat > /etc/systemd/system/vpn-bot.service << 'UNIT'
[Unit]
Description=VPN Telegram Bot Listener
After=network.target
[Service]
ExecStart=/root/scripts/vpn-bot-listener.sh
Restart=always
RestartSec=10
[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now status.service vpn-bot.service

(crontab -l 2>/dev/null | grep -v "vpn-alert\|metrics-logger\|cleanup-orphans\|resource-monitor\|vpn-monitor"; cat << 'CRON') | crontab -
*/2 * * * * /root/scripts/vpn-alert.sh
*/15 * * * * /root/scripts/metrics-logger.sh
0 * * * * /root/scripts/cleanup-orphans.sh
*/5 * * * * /root/scripts/resource-monitor.sh
0 9,21 * * * /root/scripts/vpn-monitor.sh
CRON

echo "✅ Установка завершена!"
echo "🌐 Веб-панель: https://$(hostname -I | awk '{print $1}'):45678"
echo "🔑 Пароль: ${FLASK_PASSWORD}"
