[ -f /root/.vpn-env ] && source /root/.vpn-env
#!/bin/bash

# ===========================
# Настройки Telegram
# ===========================
BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"
CONTAINER_NAME="amnezia-awg2"

# ===========================
# Функция отправки в Telegram
# ===========================
send_telegram() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "text=${message}" \
        -d "parse_mode=HTML"
}

# ===========================
# Проверка контейнера
# ===========================
if ! docker ps | grep -q "${CONTAINER_NAME}"; then
    send_telegram "❌ <b>VPN Контейнер не запущен!</b>
⏰ Время: $(TZ=Europe/Moscow date '+%d.%m.%Y %H:%M')"
    exit 1
fi

# ===========================
# Сбор статистики WireGuard
# ===========================
WG_DATA=$(docker exec ${CONTAINER_NAME} wg show)

# Количество клиентов
CLIENT_COUNT=$(echo "$WG_DATA" | grep -c "peer:")

# Активные клиенты (handshake < 3 минут назад)
ACTIVE_COUNT=0
while IFS= read -r line; do
    if echo "$line" | grep -qE "[0-2] minute|second"; then
        ACTIVE_COUNT=$((ACTIVE_COUNT + 1))
    fi
done <<< "$(echo "$WG_DATA" | grep -A1 "latest handshake")"

# ===========================
# Парсинг трафика (функция)
# ===========================
parse_traffic() {
    local value="$1"
    local unit=$(echo "$value" | grep -oE "[A-Za-z]+")
    local num=$(echo "$value" | grep -oE "[0-9.]+")
    
    # Если пусто — возвращаем 0
    [ -z "$num" ] && echo "0" && return
    
    case "$unit" in
        KiB) awk "BEGIN {printf \"%.2f\", $num/1024}" ;;
        MiB) echo "$num" ;;
        GiB) awk "BEGIN {printf \"%.0f\", $num*1024}" ;;
        TiB) awk "BEGIN {printf \"%.0f\", $num*1024*1024}" ;;
        *) echo "0" ;;
    esac
}

# Извлекаем сырые значения трафика из первой строки transfer:
TRANSFER_LINE=$(echo "$WG_DATA" | grep "transfer:" | head -1)
RAW_RX=$(echo "$TRANSFER_LINE" | grep -oE "[0-9.]+ [A-Za-z]+" | head -1)
RAW_TX=$(echo "$TRANSFER_LINE" | grep -oE "[0-9.]+ [A-Za-z]+" | tail -1)

# Конвертируем в MB
TOTAL_RX=$(parse_traffic "$RAW_RX")
TOTAL_TX=$(parse_traffic "$RAW_TX")

# ===========================
# Ресурсы контейнера
# ===========================
CONTAINER_STATS=$(docker stats ${CONTAINER_NAME} --no-stream --format "{{.CPUPerc}} | {{.MemUsage}}")
CPU_USAGE=$(echo "$CONTAINER_STATS" | cut -d'|' -f1 | tr -d ' ')
MEM_USAGE=$(echo "$CONTAINER_STATS" | cut -d'|' -f2 | tr -d ' ')

# ===========================
# Формируем сообщение
# ===========================
MESSAGE="<b>🛡️ VPN Статус</b>

👥 <b>Клиенты:</b>
├ Всего: ${CLIENT_COUNT}
└ Активных: ${ACTIVE_COUNT}

📊 <b>Трафик:</b>
├ Получено: ${TOTAL_RX} MB
└ Отправлено: ${TOTAL_TX} MB

💻 <b>Ресурсы:</b>
├ CPU: ${CPU_USAGE}
└ RAM: ${MEM_USAGE}

⏰ <b>Время:</b> $(TZ=Europe/Moscow date '+%d.%m.%Y %H:%M')"

# ===========================
# Отправляем
# ===========================
send_telegram "$MESSAGE"
