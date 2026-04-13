[ -f /root/.vpn-env ] && source /root/.vpn-env
#!/bin/bash

# ===========================
# Настройки
# ===========================
BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"
CONTAINER_NAME="amnezia-awg2"
LOG_FILE="/var/log/vpn-bot.log"
OFFSET=0
REBOOT_TIMEOUT=60
RESTART_TIMEOUT=60

# ===========================
# Функция: Отправка сообщения
# ===========================
send_telegram() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "text=${message}" \
        -d "parse_mode=HTML"
}

# ===========================
# Функция: Читаемое логирование
# ===========================
log_event() {
    local chat_id="$1"
    local message="$2"
    local timestamp=$(TZ=Europe/Moscow date '+%Y-%m-%d %H:%M:%S')
    local cmd_display="$message"
    if [ ${#message} -gt 50 ]; then cmd_display="${message:0:47}..."; fi
    local event_type="CMD"
    case "$message" in
        "/stat"|"/clients"|"/traffic") event_type="MON" ;;
        "/restart_container"|"/reboot_server") event_type="ADM" ;;
        "/speedtest") event_type="TST" ;;
        "да"|"yes"|"confirm"|"нет"|"no"|"cancel") event_type="CFM" ;;
    esac
    echo "[$timestamp] [$event_type] Chat:${chat_id:-?} Cmd:${cmd_display}" >> "$LOG_FILE"
}

# ===========================
# Функция: Получить имя клиента по ключу
# ===========================
get_peer_name() {
    local peer_key="$1"
    local conf_path=$(find /var/lib/docker -name "awg0.conf" -type f 2>/dev/null | head -1)
    if [ -n "$conf_path" ] && [ -f "$conf_path" ]; then
        local ip_num=$(awk -v key="$peer_key" '
            /^\[Peer\]/ { in_peer=1; next }
            /^\[/ { in_peer=0 }
            in_peer && /PublicKey/ { if ($2 == key) found=1 }
            found && /AllowedIPs/ { split($2, a, "/"); print a[1]; exit }
        ' "$conf_path" | awk -F. '{print $NF}')
        [ -n "$ip_num" ] && echo "Client_${ip_num}" && return
    fi
    echo "WG_${peer_key: -6}"
}

# ===========================
# Функция: Проверка подтверждения ребута
# ===========================
check_reboot_confirmation() {
    local chat_id="$1"
    local message="$2"
    local flag_file="/tmp/reboot_pending_${chat_id}"
    
    [ ! -f "$flag_file" ] && return 1
    
    local flag_time=$(cat "$flag_file" | head -1)
    local now=$(date +%s)
    local diff=$((now - flag_time))
    
    if [ "$diff" -gt "$REBOOT_TIMEOUT" ]; then
        rm -f "$flag_file"
        send_telegram "⏰ <b>Время подтверждения истекло!</b>"
        return 1
    fi
    
    local msg_lower=$(echo "$message" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
    
    case "$msg_lower" in
        "да"|"yes"|"confirm"|"подтверждаю"|"🔄"|"✅")
            rm -f "$flag_file"
            send_telegram "✅ <b>Подтверждено! Перезагрузка через 10 секунд...</b>"
            sleep 10
            reboot &
            return 0
            ;;
        "нет"|"no"|"cancel"|"отмена"|"❌"|"🛑")
            rm -f "$flag_file"
            send_telegram "❌ <b>Перезагрузка отменена!</b>"
            return 0
            ;;
        *)
            return 2
            ;;
    esac
}

# ===========================
# Функция: Проверка подтверждения рестарта
# ===========================
check_restart_confirmation() {
    local chat_id="$1"
    local message="$2"
    local flag_file="/tmp/restart_pending_${chat_id}"
    
    [ ! -f "$flag_file" ] && return 1
    
    local flag_time=$(cat "$flag_file" | head -1)
    local now=$(date +%s)
    local diff=$((now - flag_time))
    
    if [ "$diff" -gt "$RESTART_TIMEOUT" ]; then
        rm -f "$flag_file"
        send_telegram "⏰ <b>Время подтверждения истекло!</b>"
        return 1
    fi
    
    local msg_lower=$(echo "$message" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
    
    case "$msg_lower" in
        "да"|"yes"|"confirm"|"подтверждаю"|"🔄"|"✅")
            rm -f "$flag_file"
            send_telegram "🔄 <b>Перезапуск контейнера...</b>"
            docker restart ${CONTAINER_NAME} >/dev/null 2>&1
            sleep 5
            if docker ps | grep -q "${CONTAINER_NAME}"; then
                send_telegram "✅ <b>Контейнер перезапущен!</b>"
            else
                send_telegram "⚠️ <b>Контейнер не запустился!</b>"
            fi
            return 0
            ;;
        "нет"|"no"|"cancel"|"отмена"|"❌")
            rm -f "$flag_file"
            send_telegram "❌ <b>Перезапуск отменен!</b>"
            return 0
            ;;
        *)
            return 2
            ;;
    esac
}

# ===========================
# Команда: /stat
# ===========================
cmd_stat() {
    if ! docker ps | grep -q "${CONTAINER_NAME}"; then
        send_telegram "❌ <b>VPN Контейнер не запущен!</b>"
        return
    fi
    WG_DATA=$(docker exec ${CONTAINER_NAME} wg show)
    CLIENT_COUNT=$(echo "$WG_DATA" | grep -c "peer:")
    ACTIVE_COUNT=0
    while IFS= read -r line; do
        if echo "$line" | grep -qE "[0-2] minute|second"; then
            ACTIVE_COUNT=$((ACTIVE_COUNT + 1))
        fi
    done <<< "$(echo "$WG_DATA" | grep -A1 "latest handshake")"
    parse_traffic() {
        local value="$1"
        local unit=$(echo "$value" | grep -oE "[A-Za-z]+")
        local num=$(echo "$value" | grep -oE "[0-9.]+")
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
    TOTAL_RX=$(parse_traffic "$RAW_RX")
    TOTAL_TX=$(parse_traffic "$RAW_TX")
    CONTAINER_STATS=$(docker stats ${CONTAINER_NAME} --no-stream --format "{{.CPUPerc}} | {{.MemUsage}}")
    CPU_USAGE=$(echo "$CONTAINER_STATS" | cut -d'|' -f1 | tr -d ' ')
    MEM_USAGE=$(echo "$CONTAINER_STATS" | cut -d'|' -f2 | tr -d ' ')
    send_telegram "🛡️ <b>VPN Статус</b>

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
}

# ===========================
# Команда: /clients
# ===========================
cmd_clients() {
    if ! docker ps | grep -q "${CONTAINER_NAME}"; then
        send_telegram "❌ <b>VPN Контейнер не запущен!</b>"
        return
    fi
    WG_DATA=$(docker exec ${CONTAINER_NAME} wg show)
    local message="👥 <b>Клиенты VPN</b>

"
    declare -a peers_data
    local current_peer="" current_ip="" current_endpoint="" current_handshake=""
    while IFS= read -r line; do
        if echo "$line" | grep -q "^peer:"; then
            if [ -n "$current_peer" ] && [ -n "$current_ip" ]; then
                peers_data+=("${current_ip}|${current_endpoint}|${current_handshake}")
            fi
            current_peer=$(echo "$line" | awk '{print $2}')
            current_ip="" current_endpoint="" current_handshake=""
        fi
        if echo "$line" | grep -q "endpoint:"; then current_endpoint=$(echo "$line" | awk '{print $2}'); fi
        if echo "$line" | grep -q "allowed ips:"; then current_ip=$(echo "$line" | awk '{print $3}' | cut -d'/' -f1); fi
        if echo "$line" | grep -q "latest handshake:"; then current_handshake="$line"; fi
    done <<< "$WG_DATA"
    if [ -n "$current_peer" ] && [ -n "$current_ip" ]; then
        peers_data+=("${current_ip}|${current_endpoint}|${current_handshake}")
    fi
    for entry in "${peers_data[@]}"; do
        IFS='|' read -r ip endpoint handshake <<< "$entry"
        local status="🔴 Офлайн"
        if echo "$handshake" | grep -qE "([0-9]+ second|[0-1] minute)"; then status="🟢 Онлайн"; fi
        message+="<b>🔹 ${ip}</b>
├ Статус: ${status}
└ Внешний: <code>${endpoint}</code>

"
    done
    message+="⏰ <b>Время:</b> $(TZ=Europe/Moscow date '+%d.%m.%Y %H:%M')"
    send_telegram "$message"
}

# ===========================
# Команда: /traffic
# ===========================
cmd_traffic() {
    if ! docker ps | grep -q "${CONTAINER_NAME}"; then
        send_telegram "❌ <b>VPN Контейнер не запущен!</b>"
        return
    fi
    WG_DATA=$(docker exec ${CONTAINER_NAME} wg show)
    local message="📊 <b>Трафик по клиентам</b>

"
    local peer_key="" internal_ip=""
    while IFS= read -r line; do
        if echo "$line" | grep -q "peer:"; then
            peer_key=$(echo "$line" | awk '{print $2}')
            internal_ip=""
        fi
        if echo "$line" | grep -q "allowed ips:"; then
            internal_ip=$(echo "$line" | awk '{print $3}' | cut -d'/' -f1)
        fi
        if echo "$line" | grep -q "transfer:"; then
            transfer=$(echo "$line" | sed 's/.*transfer: //')
            if [ -n "$internal_ip" ]; then
                message+="<b>🔹 ${internal_ip}</b>
└ ${transfer}

"
            fi
        fi
    done <<< "$WG_DATA"
    message+="⏰ <b>Время:</b> $(TZ=Europe/Moscow date '+%d.%m.%Y %H:%M')"
    send_telegram "$message"
}

# ===========================
# Команда: /server_status
# ===========================
cmd_server_status() {
    local cpu=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    local mem=$(free -m | awk 'NR==2{printf "%.2f/%.2f MB (%.2f%%)", $3,$2,$3*100/$2}')
    local disk=$(df -h / | awk 'NR==2{print $5}')
    local uptime=$(uptime -p)
    local ping=$(ping -c 3 -W 2 1.1.1.1 2>&1 | grep "rtt" | awk -F'/' '{print $5}' | head -1)
    local container_status="❌ Не работает"
    if docker ps | grep -q "${CONTAINER_NAME}"; then container_status="✅ Работает"; fi
    send_telegram "🖥️ <b>Статус сервера</b>

📊 <b>Ресурсы:</b>
├ CPU: ${cpu}%
├ RAM: ${mem}
├ Диск: ${disk} занято
└ Аптайм: ${uptime}

🌐 <b>Сеть:</b>
└ Ping до 1.1.1.1: ${ping:-N/A} ms

🐳 <b>Контейнер:</b>
└ ${CONTAINER_NAME}: ${container_status}

⏰ <b>Время:</b> $(TZ=Europe/Moscow date '+%d.%m.%Y %H:%M')"
}

# ===========================
# Команда: /restart_container
# ===========================
cmd_restart_container() {
    if [ "$FROM_CHAT_ID" != "${CHAT_ID}" ]; then send_telegram "❌ <b>Доступ запрещён!</b>"; return; fi
    echo "$(date +%s)" > "/tmp/restart_pending_${CHAT_ID}"
    send_telegram "⚠️ <b>Подтвердите перезапуск контейнера!</b>

✅ <b>Для подтверждения:</b> <code>да</code> | <code>yes</code> | <code>🔄</code>
❌ <b>Для отмены:</b> <code>нет</code> | <code>no</code> | <code>❌</code>

⏱️ <b>Время:</b> ${RESTART_TIMEOUT} сек"
}

# ===========================
# Команда: /reboot_server
# ===========================
cmd_reboot_server() {
    if [ "$FROM_CHAT_ID" != "${CHAT_ID}" ]; then send_telegram "❌ <b>Доступ запрещён!</b>"; return; fi
    echo "$(date +%s)" > "/tmp/reboot_pending_${CHAT_ID}"
    send_telegram "⚠️ <b>Подтвердите перезагрузку сервера!</b>

✅ <b>Для подтверждения:</b> <code>да</code> | <code>yes</code> | <code>🔄</code>
❌ <b>Для отмены:</b> <code>нет</code> | <code>no</code> | <code>❌</code>

⏱️ <b>Время:</b> ${REBOOT_TIMEOUT} сек"
}

# ===========================
# Команда: /logs
# ===========================
cmd_logs() {
    if [ "$FROM_CHAT_ID" != "${CHAT_ID}" ]; then send_telegram "❌ <b>Доступ запрещён!</b>"; return; fi
    local logs=$(tail -30 /var/log/vpn-bot.log 2>/dev/null || echo "Логов нет")
    send_telegram "📋 <b>Последние логи бота</b>

<code>${logs}</code>"
}

# ===========================
# Команда: /cleanup
# ===========================
cmd_cleanup() {
    if [ "$FROM_CHAT_ID" != "${CHAT_ID}" ]; then send_telegram "❌ <b>Доступ запрещён!</b>"; return; fi
    send_telegram "🧹 <b>Запуск очистки...</b>"
    local before=$(df -h / | awk 'NR==2{print $5}')
    /root/scripts/cleanup-server.sh >> /var/log/cleanup-server.log 2>&1
    local after=$(df -h / | awk 'NR==2{print $5}')
    send_telegram "✅ <b>Очистка завершена!</b>
├ <b>До:</b> ${before}
└ <b>После:</b> ${after}"
}

# ===========================
# Команда: /health
# ===========================
cmd_health() {
    send_telegram "🟢 <b>Бот онлайн!</b>
⏰ <b>Время:</b> $(TZ=Europe/Moscow date '+%d.%m.%Y %H:%M:%S')"
}

# ===========================
# Команда: /speedtest
# ===========================
cmd_speedtest() {
    send_telegram "🚀 <b>Тест канала до РФ...</b>"
    local PING_RESULT=$(ping -c 10 ya.ru 2>&1)
    if echo "$PING_RESULT" | grep -q "rtt"; then
        local PING_AVG=$(echo "$PING_RESULT" | grep "rtt" | awk -F'/' '{print $5}')
        send_telegram "✅ <b>Пинг до ya.ru:</b> ${PING_AVG} ms"
    else
        send_telegram "❌ <b>Тест не удался</b>"
    fi
}

# ===========================
# Команда: /help
# ===========================
cmd_help() {
    send_telegram "📚 <b>Справка по командам</b>

📊 <b>Мониторинг:</b>
/stat - Общая статистика VPN
/clients - Список клиентов со статусом (по IP)
/traffic - Трафик по клиентам (по IP)
/server_status - Статус сервера

🛠️ <b>Управление:</b>
/restart_container - Перезапуск VPN (с подтверждением)
/reboot_server - Перезагрузка сервера (с подтверждением)
/cleanup - Очистка места на диске
/logs - Логи бота

🧪 <b>Тесты:</b>
/speedtest - Тест канала до РФ
/health - Проверка, жив ли бот

ℹ️ <b>Другое:</b>
/help - Эта справка
/start - Запустить бота

🔔 <b>Алерты приходят автоматически.</b>"
}

# ===========================
# Команда: /start
# ===========================
cmd_start() {
    send_telegram "👋 <b>Привет! Я VPN Monitor Bot</b>
⏰ <b>Время:</b> $(TZ=Europe/Moscow date '+%d.%m.%Y %H:%M')"
}

# ===========================
# Основной цикл
# ===========================
echo "🤖 Бот запущен..."

while true; do
    UPDATES=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getUpdates?offset=${OFFSET}&timeout=3")
    LAST_UPDATE=$(echo "$UPDATES" | grep -o '"update_id":[0-9]*' | tail -1 | cut -d':' -f2)
    if [ -n "$LAST_UPDATE" ]; then
        OFFSET=$((LAST_UPDATE + 1))
        FROM_CHAT_ID=$(echo "$UPDATES" | grep -oE '"chat":\{"id":[0-9]+' | grep -oE '[0-9]+' | tail -1)
        if [ -z "$FROM_CHAT_ID" ]; then
            FROM_CHAT_ID=$(echo "$UPDATES" | sed -n 's/.*"chat":{"id":\([0-9]*\).*/\1/p' | tail -1)
        fi
        FROM_CHAT_ID=$(echo "$FROM_CHAT_ID" | tr -d ' "')
        MESSAGE_TEXT=$(echo "$UPDATES" | grep -oE '"text":"[^"]*"' | tail -1 | cut -d'"' -f4)
        log_event "$FROM_CHAT_ID" "$MESSAGE_TEXT"
        if check_reboot_confirmation "$FROM_CHAT_ID" "$MESSAGE_TEXT"; then continue; fi
        if check_restart_confirmation "$FROM_CHAT_ID" "$MESSAGE_TEXT"; then continue; fi
        case "$MESSAGE_TEXT" in
            "/stat") cmd_stat ;;
            "/clients") cmd_clients ;;
            "/traffic") cmd_traffic ;;
            "/speedtest") cmd_speedtest ;;
            "/health") cmd_health ;;
            "/help") cmd_help ;;
            "/start") cmd_start ;;
            "/server_status") cmd_server_status ;;
            "/restart_container") cmd_restart_container ;;
            "/reboot_server") cmd_reboot_server ;;
            "/logs") cmd_logs ;;
            "/cleanup") cmd_cleanup ;;
        esac
    fi
    sleep 3
done
