#!/bin/bash
# ======================================================================
# ️ VPN Amnezia Infrastructure — Установочный скрипт (Ubuntu 24.04)
# Версия: 1.2 (Fixed Check Output & Security)
# ======================================================================
set -euo pipefail

SCRIPTS_DIR="/root/scripts"
FLASK_DIR="/opt/vpn-status"
REPO_DIR="/opt/vpn-amnezia-infrastructure"
ENV_FILE="/root/.vpn-env"
LOG_FILE="/var/log/vpn-install.log"

# ======================================================================
# 🔍 РЕЖИМ ПРОВЕРКИ (Check Mode) — ДО логирования, чтобы видеть на экране
# ======================================================================
if [ "${1:-}" = "--check" ]; then
    echo "🔍 VPN Infrastructure Health Check"
    echo "=================================="
    
    systemctl is-active --quiet fail2ban && echo "✅ fail2ban.service (active)" || echo "❌ fail2ban.service (inactive)"
    fail2ban-client status vpn-monitoring &>/dev/null && echo "✅ [vpn-monitoring] jail" || echo "❌ [vpn-monitoring] jail missing"
    [ -f "/etc/fail2ban/action.d/telegram-ban.conf" ] && echo "✅ telegram-ban.conf" || echo "❌ telegram-ban.conf missing"
    
    echo "----------------------------------"
    for script in vpn-bot-listener.sh vpn-alert.sh audit-peers.sh cleanup-orphans.sh resource-monitor.sh vpn-monitor.sh metrics-logger.sh; do
        [ -f "$SCRIPTS_DIR/$script" ] && echo "✅ $script" || echo "❌ $script отсутствует"
    done
    echo "----------------------------------"
    [ -f "$ENV_FILE" ] && echo "✅ $ENV_FILE" || echo "❌ $ENV_FILE отсутствует"
    for svc in vpn-bot status nginx docker; do
        systemctl is-active --quiet "$svc" 2>/dev/null && echo "✅ $svc.service (active)" || echo "❌ $svc.service (inactive)"
    done
    echo "----------------------------------"
    docker ps --filter "name=amnezia-awg2" --format "{{.Names}}" | grep -q "amnezia-awg2" && echo "✅ amnezia-awg2 (running)" || echo "❌ amnezia-awg2 (not running)"
    docker exec amnezia-awg2 wg show &>/dev/null && echo "✅ WireGuard (отвечает)" || echo "❌ WireGuard (не отвечает)"
    echo "----------------------------------"
    ping -c 1 -W 2 1.1.1.1 &>/dev/null && echo "✅ Ping 1.1.1.1" || echo "❌ Ping 1.1.1.1"
    ss -tlnp | grep -q ":45678 " && echo "✅ Nginx слушает 45678" || echo "❌ Nginx не слушает 45678"
    echo "----------------------------------"
    crontab -l 2>/dev/null | grep -qE "vpn-alert|metrics-logger|cleanup-orphans|resource-monitor|vpn-monitor" && echo "✅ cron-задачи" || echo "❌ cron-задачи отсутствуют"
    
    echo "=================================="
    echo "📋 Логи установки: $LOG_FILE"
    exit 0
fi

# 🪵 Логирование (включается только при установке)
exec > >(tee -a "$LOG_FILE") 2>&1

# ======================================================================
# 🚀 РЕЖИМ УСТАНОВКИ
# ======================================================================

if [ "$EUID" -ne 0 ]; then echo "❌ Запустите от root"; exit 1; fi
if ! grep -q 'Ubuntu 24\.04' /etc/os-release 2>/dev/null; then echo "❌ Только Ubuntu 24.04"; exit 1; fi

echo "🚀 Установка VPN Amnezia Infrastructure v1.2"
read -s -p "🔑 Токен Telegram-бота: " BOT_TOKEN && echo
read -s -p "💬 Chat ID: " CHAT_ID && echo
read -s -p "🔐 Пароль Flask: " FLASK_PASSWORD && echo
echo ""

apt update -qq && apt upgrade -y -qq
apt install -y -qq docker.io python3 python3-pip python3-venv nginx fail2ban ufw curl git jq tcpdump netfilter-persistent iptables-persistent

echo "🛡️ Настройка UFW..."
ufw --force enable
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 443/tcp
ufw allow 443/udp
ufw allow 45678/tcp

systemctl enable --now docker
if ! docker info &>/dev/null; then echo "❌ Docker error"; exit 1; fi

if ! docker ps --format '{{.Names}}' | grep -q "^amnezia-awg2$"; then
    echo "🐳 Установка Amnezia..."
    curl -s https://raw.githubusercontent.com/amnezia-vpn/amneziawg-docker/master/install.sh | bash
    sleep 5
fi

if [ ! -d "$REPO_DIR" ]; then
    git clone https://github.com/baltazor70/vpn-amnezia-infrastructure.git "$REPO_DIR"
else
    cd "$REPO_DIR" && git pull --quiet
fi

if [ -d "$SCRIPTS_DIR" ]; then
    mkdir -p "/root/scripts.bak_$(date +%F)"
    cp -r "$SCRIPTS_DIR"/* "/root/scripts.bak_$(date +%F)/" 2>/dev/null || true
fi

mkdir -p "$SCRIPTS_DIR"
cp -f "$REPO_DIR/scripts/"*.sh "$SCRIPTS_DIR/"
chmod +x "$SCRIPTS_DIR"/*.sh

cat > "$ENV_FILE" << EOF
BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"
FLASK_ADMIN_PASSWORD="${FLASK_PASSWORD}"
EOF
chmod 600 "$ENV_FILE"

if [ -f "$REPO_DIR/flask/requirements.txt" ]; then
    pip3 install -q -r "$REPO_DIR/flask/requirements.txt" 2>/dev/null || pip3 install -q flask psutil requests
else
    pip3 install -q flask psutil requests
fi

mkdir -p "$FLASK_DIR/templates"
cp -f "$REPO_DIR/flask/app.py" "$FLASK_DIR/"
cp -f "$REPO_DIR/flask/templates/index.html" "$FLASK_DIR/templates/"

mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout /etc/nginx/ssl/vpn-status.key -out /etc/nginx/ssl/vpn-status.crt -subj "/C=RU/ST=Moscow/L=Moscow/O=VPN/CN=vpn.local" 2>/dev/null

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
EnvironmentFile=/root/.vpn-env
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
After=network.target docker.service
Requires=docker.service
[Service]
Type=simple
User=root
ExecStart=/root/scripts/vpn-bot-listener.sh
Restart=always
RestartSec=10
[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now status.service vpn-bot.service

if [ -f "$REPO_DIR/deploy/fail2ban/deploy.sh" ]; then
    bash "$REPO_DIR/deploy/fail2ban/deploy.sh" || echo "⚠️ Fail2ban deploy failed"
else
    systemctl restart fail2ban
fi

(crontab -l 2>/dev/null | grep -vE "vpn-alert|metrics-logger|cleanup-orphans|resource-monitor|vpn-monitor|vpn-container-watchdog|backup-docker|auto-reboot|post-reboot-check"; cat << 'CRON') | crontab -
*/2 * * * * /root/scripts/vpn-alert.sh
*/5 * * * * /root/scripts/vpn-container-watchdog.sh
*/5 * * * * /root/scripts/resource-monitor.sh
*/15 * * * * /root/scripts/metrics-logger.sh
0 * * * * /root/scripts/cleanup-orphans.sh
0 9,21 * * * /root/scripts/vpn-monitor.sh
45 2 * * 3 /root/scripts/backup-docker.sh
45 2 * * 0 /root/scripts/backup-docker.sh
0 3 * * 1 /root/scripts/auto-reboot.sh
0 3 * * 3 /root/scripts/auto-reboot.sh
@reboot sleep 45 && /root/scripts/post-reboot-check.sh
CRON

echo ""
echo "=============================================="
echo "✅ Установка завершена!"
echo "🌐 Панель: https://$(hostname -I | awk '{print $1}'):45678"
echo " Пароль в $ENV_FILE"
echo " Логи: $LOG_FILE"
echo "=============================================="
