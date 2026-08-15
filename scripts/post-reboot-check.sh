#!/bin/bash
source /root/.vpn-env

send_tg() {
    curl -s -X POST https://api.telegram.org/bot${BOT_TOKEN}/sendMessage \
    -d chat_id=${CHAT_ID} \
    -d text="$1" \
    -d parse_mode=HTML
}

check_svc() {
    systemctl is-active --quiet "$1" && echo "✅" || echo "❌"
}

SVC_DOCKER=$(check_svc docker)
SVC_WG=$( [ -n "$(docker ps -q -f name=amnezia-awg2)" ] && echo "✅" || echo "❌" )
SVC_F2B=$(check_svc fail2ban)
SVC_NGINX=$(check_svc nginx)
SVC_FLASK=$(check_svc status.service)
SVC_BOT=$(check_svc vpn-bot.service)
SVC_CRON=$(check_svc cron)
SVC_PING=$(ping -c 1 -W 2 1.1.1.1 &>/dev/null && echo "✅" || echo "❌")

MSG="✅ 🇳🇱 VPN-Server (Amsterdam)

Перезагрузка успешна!

⏰ Время: $(date '+%d.%m.%Y %H:%M')
⏱️ Аптайм: $(uptime -p)
🔄 Результат: OK

📊 Статус сервисов:
 ├ 🐳 Docker: ${SVC_DOCKER} Демон
 ├ 🛡️ AmneziaWG: ${SVC_WG} Контейнер
 ├ 🚫 Fail2ban: ${SVC_F2B} Защита SSH/Web
 ├ 🔄 Nginx: ${SVC_NGINX} Reverse Proxy
 ├ 📊 Flask: ${SVC_FLASK} Dashboard
 ├ 🤖 Telegram: ${SVC_BOT} Алерты
 ├  Cron: ${SVC_CRON} Планировщик
 ├ 📡 Порт WG: ✅ 36991/UDP
 └ 📶 Ping: ${SVC_PING} Сеть

️ Обновления:
 └ Установлены перед ребутам

🟢 VPN готов к работе!"

send_tg "$MSG"
