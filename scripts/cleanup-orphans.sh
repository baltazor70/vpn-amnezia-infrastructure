#!/bin/bash
source /root/.vpn-env

CONTAINER="amnezia-awg2"
LOG="/var/log/cleanup-orphans.log"

send_telegram() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "text=${message}" \
        -d "parse_mode=HTML" > /dev/null
}

echo "[$(date)] Запуск проверки сирот" >> "$LOG"

# Получаем список всех IP из awg0.conf
all_ips=$(docker exec $CONTAINER cat /opt/amnezia/awg/awg0.conf | awk '/AllowedIPs/{print $3}' | sed 's/\/32//')

# Получаем список IP из clientsTable (те, у кого есть clientName)
valid_ips=$(docker exec $CONTAINER cat /opt/amnezia/awg/clientsTable | grep -B4 '"clientName"' | grep '"allowedIps"' | awk -F'"' '{print $4}' | sed 's/\/32//')

# Находим сирот
for ip in $all_ips; do
    if ! echo "$valid_ips" | grep -q "^$ip$"; then
        # Это сирота — удаляем его ключ
        peer_key=$(docker exec $CONTAINER wg show | grep -B1 "allowed ips: ${ip}/32" | grep "peer:" | awk '{print $2}')
        if [ -n "$peer_key" ]; then
            # Пытаемся узнать имя, если оно было
            name=$(docker exec $CONTAINER cat /opt/amnezia/awg/clientsTable 2>/dev/null | grep -A4 "\"allowedIps\": \"${ip}/32\"" | grep "clientName" | head -1 | awk -F'"' '{print $4}')
            [ -z "$name" ] && name="Unknown"
            
            docker exec $CONTAINER wg set awg0 peer $peer_key remove
            echo "[$(date)] Удалён сирота: IP=$ip, KEY=$peer_key" >> "$LOG"
            
            # Отправляем уведомление в Telegram
            MESSAGE="🗑️ <b>Удалён потерянный профиль</b>

👤 Пользователь: <b>${name}</b>
🔑 Ключ: <code>${peer_key:0:16}...</code>
🏠 Внутренний IP: ${ip}
⏰ Время: $(TZ=Europe/Moscow date '+%d.%m.%Y %H:%M')"
            send_telegram "$MESSAGE"
        fi
    fi
done

echo "[$(date)] Проверка завершена" >> "$LOG"
