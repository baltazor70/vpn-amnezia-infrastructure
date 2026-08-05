#!/bin/bash
source /root/.vpn-env

CONTAINER_NAME="amnezia-awg2"

send_telegram() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "text=${message}" \
        -d "parse_mode=HTML"
}

if ! docker ps | grep -q "${CONTAINER_NAME}"; then
    send_telegram "❌ <b>VPN Контейнер не запущен!</b>
⏰ Время: $(TZ=Europe/Moscow date '+%d.%m.%Y %H:%M')"
    exit 1
fi

WG_DATA=$(docker exec ${CONTAINER_NAME} wg show)
CLIENT_COUNT=$(echo "$WG_DATA" | grep -c "peer:")
ACTIVE_COUNT=0

while IFS= read -r line; do
    handshake_line=$(echo "$line" | grep -o "latest handshake: .*")
    if [ -n "$handshake_line" ]; then
        hs_val=$(echo "$handshake_line" | sed "s/.*latest handshake: //")
        hs_seconds=$(echo "$hs_val" | awk '{
            if (NF==0) { print 99999 }
            else if ($2=="day" || $2=="days") { print $1*86400 }
            else if ($2=="hour" || $2=="hours") { print $1*3600 }
            else if ($2=="minute" || $2=="minutes") { print $1*60 }
            else if ($2=="second" || $2=="seconds") { print $1 }
            else { print 99999 }
        }')
        if [ "$hs_seconds" -le 120 ]; then
            ((ACTIVE_COUNT++))
        fi
    fi
done <<< "$(echo "$WG_DATA" | grep -A1 "latest handshake")"

parse_traffic() {
    local value="$1" unit num
    unit=$(echo "$value" | grep -oE "[A-Za-z]+")
    num=$(echo "$value" | grep -oE "[0-9.]+")
    [ -z "$num" ] && echo "0" && return
    case "$unit" in
        KiB) awk "BEGIN {printf \"%.2f\", $num/1024}" ;;
        MiB) echo "$num" ;;
        GiB) awk "BEGIN {printf \"%.0f\", $num*1024}" ;;
        *) echo "0" ;;
    esac
}

TRANSFER_LINE=$(echo "$WG_DATA" | grep "transfer:" | head -1)
RAW_RX=$(echo "$TRANSFER_LINE" | grep -oE "[0-9.]+ [A-Za-z]+" | head -1)
RAW_TX=$(echo "$TRANSFER_LINE" | grep -oE "[0-9.]+ [A-Za-z]+" | tail -1)
TOTAL_RX=$(parse_traffic "$RAW_RX"); TOTAL_TX=$(parse_traffic "$RAW_TX")

CONTAINER_STATS=$(docker stats ${CONTAINER_NAME} --no-stream --format "{{.CPUPerc}} | {{.MemUsage}}")
CONT_CPU=$(echo "$CONTAINER_STATS" | cut -d'|' -f1 | tr -d ' ')
CONT_RAM=$(echo "$CONTAINER_STATS" | cut -d'|' -f2 | tr -d ' ')

host_cpu=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
host_ram=$(free -m | awk 'NR==2{printf "%.2f/%.2f MB (%.2f%%)", $3,$2,$3*100/$2}')
disk=$(df -h / | awk 'NR==2{print $5}')
uptime=$(uptime -p)
ping1=$(ping -c 1 -W 2 1.1.1.1 2>&1 | grep "rtt" | awk -F'/' '{print $5}' | head -1)
ping2=$(ping -c 1 -W 2 ya.ru 2>&1 | grep "rtt" | awk -F'/' '{print $5}' | head -1)
container_status="❌ Не работает"
docker ps | grep -q "${CONTAINER_NAME}" && container_status="✅ Работает"

MESSAGE="📊 <b>VPN СТАТУС</b>

👥 <b>Клиенты:</b>
├ Всего: ${CLIENT_COUNT}
└ Активных (Меньше 2 минут): ${ACTIVE_COUNT}

📈 <b>Трафик:</b>
├ Получено: ${TOTAL_RX} MB
└ Отправлено: ${TOTAL_TX} MB

🐳 <b>Контейнер:</b>
├ Статус: ${container_status}
├ CPU: ${CONT_CPU}
└ RAM: ${CONT_RAM}

🖥️ <b>Сервер:</b>
├ CPU: ${host_cpu}%
├ RAM: ${host_ram}
├ Диск: ${disk} занято
└ Аптайм: ${uptime}

🌐 <b>Сеть:</b>
├ 1.1.1.1: ${ping1:-N/A} ms
└ ya.ru: ${ping2:-N/A} ms

⏰ <b>Время:</b> $(TZ=Europe/Moscow date '+%d.%m.%Y %H:%M')"

send_telegram "$MESSAGE"
