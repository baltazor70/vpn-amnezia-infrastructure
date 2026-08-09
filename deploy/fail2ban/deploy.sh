#!/bin/bash
# deploy/fail2ban/deploy.sh
# Скрипт раскатки Fail2Ban конфигов с Telegram-алертами
# Использует секреты из /root/.vpn-env

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

echo "🔧 Deploying Fail2Ban configuration..."

# 1. Загружаем переменные из /root/.vpn-env
if [ -f "/root/.vpn-env" ]; then
    export $(grep -v '^#' "/root/.vpn-env" | xargs)
    echo "✅ Loaded variables from /root/.vpn-env"
else
    echo "❌ /root/.vpn-env file not found"
    exit 1
fi

# 2. Копируем action-файл с подстановкой переменных
echo "📦 Deploying telegram-ban.conf..."
envsubst '${BOT_TOKEN} ${CHAT_ID}' \
    < "$SCRIPT_DIR/templates/telegram-ban.conf.tpl" \
    > /tmp/telegram-ban.conf

sudo cp /tmp/telegram-ban.conf /etc/fail2ban/action.d/telegram-ban.conf
sudo chmod 644 /etc/fail2ban/action.d/telegram-ban.conf

# 3. Копируем filter-файл
echo "📦 Deploying vpn-monitoring.conf..."
sudo cp "$SCRIPT_DIR/templates/vpn-monitoring.conf.tpl" /etc/fail2ban/filter.d/vpn-monitoring.conf
sudo chmod 644 /etc/fail2ban/filter.d/vpn-monitoring.conf

# 4. Обновляем jail.local (добавляем блок, если его нет)
echo "📦 Updating jail.local..."
if ! grep -q "\[vpn-monitoring\]" /etc/fail2ban/jail.local 2>/dev/null; then
    cat >> /etc/fail2ban/jail.local << EOF

[vpn-monitoring]
enabled = true
port = 45678
filter = vpn-monitoring
logpath = /var/log/nginx/vpn-status-access.log
maxretry = 3
findtime = 600
bantime = 3600
action = telegram-ban
EOF
    echo "✅ Added [vpn-monitoring] block to jail.local"
else
    echo "ℹ️ [vpn-monitoring] block already exists in jail.local"
fi

# 5. Перезапускаем fail2ban
echo "🔄 Reloading Fail2Ban..."
sudo fail2ban-client reload

# 6. Проверяем статус
echo "📊 Checking jail status..."
sudo fail2ban-client status vpn-monitoring || echo "⚠️ Jail 'vpn-monitoring' not active yet"

echo "✅ Fail2Ban deployment complete!"
echo "📱 Telegram alerts are now active for brute-force attempts on /login"
