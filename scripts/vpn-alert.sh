#!/bin/bash
source /root/.vpn-env

CONTAINER_NAME="amnezia-awg2"
STATE_FILE="/tmp/vpn-peers-state"
LOG_FILE="/var/log/vpn-alert.log"

send_telegram() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "text=${message}" \
        -d "parse_mode=HTML" > /dev/null
}

log() {
    echo "[$(TZ=Europe/Moscow date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

get_name_by_ip() {
    local search_ip="$1"
    docker exec ${CONTAINER_NAME} cat /opt/amnezia/awg/clientsTable 2>/dev/null | \
        awk -v ip="$search_ip" '
        BEGIN { found=0 }
        /"allowedIps": "/ { if ($0 ~ "\"" ip "/32\"") { found=1 } }
        /"allowed_ips": "/ { if (!found && $0 ~ "\"" ip "/32\"") { found=1 } }
        found && /"clientName":/ { print $0; found=0 }
        ' | head -1 | awk -F'"' '{print $4}'
}

# Получаем только внутренние IP активных пиров (без ключей)
get_current_ips() {
    docker exec ${CONTAINER_NAME} wg show | \
    awk '/allowed ips:/ {ip=$3; sub(/\/32/,"",ip); print ip}' | \
    sort
}

# Инициализация
if [ ! -f "$STATE_FILE" ]; then
    get_current_ips > "$STATE_FILE"
    log "Первый запуск, состояние сохранено."
    exit 0
fi

OLD_IPS=$(cat "$STATE_FILE")
NEW_IPS=$(get_current_ips)
echo "$NEW_IPS" > "$STATE_FILE"

# Находим новые и отключившиеся IP
CONNECTED=$(comm -13 <(echo "$OLD_IPS") <(echo "$NEW_IPS"))
DISCONNECTED=$(comm -23 <(echo "$OLD_IPS") <(echo "$NEW_IPS"))

# --- Отключения ---
for ip in $DISCONNECTED; do
    name=$(get_name_by_ip "$ip")
    [ -z "$name" ] && name="Unknown"

    MESSAGE="🔴 <b>Клиент отключился от VPN</b>

👤 Пользователь: <b>${name}</b>
🏠 Внутренний IP: ${ip}
⏰ Время: $(TZ=Europe/Moscow date '+%d.%m.%Y %H:%M')"
    send_telegram "$MESSAGE"
    log "DISCONNECTED: $name (int:${ip})"
done

# --- Подключения ---
for ip in $CONNECTED; do
    name=$(get_name_by_ip "$ip")
    [ -z "$name" ] && name="Unknown"

    MESSAGE="🟢 <b>Новое подключение к VPN</b>

👤 Пользователь: <b>${name}</b>
🏠 Внутренний IP: ${ip}
⏰ Время: $(TZ=Europe/Moscow date '+%d.%m.%Y %H:%M')"
    send_telegram "$MESSAGE"
    log "CONNECTED: $name (int:${ip})"
done
