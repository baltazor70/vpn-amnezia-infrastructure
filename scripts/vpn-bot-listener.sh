#!/bin/bash
source /root/.vpn-env

CONTAINER_NAME="amnezia-awg2"
LOG_FILE="/var/log/vpn-bot.log"
OFFSET=0
REBOOT_TIMEOUT=60
RESTART_TIMEOUT=60

send_telegram() {
    local msg="$1"
    ( curl -s --max-time 10 -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" -d "text=${msg}" -d "parse_mode=HTML" >/dev/null 2>&1 ) &
}

log_event() {
    local chat_id="$1" message="$2"
    local ts=$(TZ=Europe/Moscow date '+%Y-%m-%d %H:%M:%S')
    local cmd_display="$message"
    [ ${#message} -gt 50 ] && cmd_display="${message:0:47}..."
    local event_type="CMD"
    case "$message" in
        "/stat"|"/status"|"/clients"|"/top"|"/users"|"/userstatus"*) event_type="MON" ;;
        "/restart_container"|"/reboot_server") event_type="ADM" ;;
        "/ping") event_type="TST" ;;
        "да"|"yes"|"confirm"|"нет"|"no"|"cancel") event_type="CFM" ;;
    esac
    echo "[$ts] [$event_type] Chat:${chat_id:-?} Cmd:${cmd_display}" >> "$LOG_FILE"
}

get_name_by_ip() {
    local search_ip="$1"
    docker exec ${CONTAINER_NAME} cat /opt/amnezia/awg/clientsTable 2>/dev/null | \
        awk -v ip="$search_ip" '
        /"allowedIps": "/ { if ($0 ~ "\"" ip "/32\"") { found=1 } }
        found && /"clientName":/ { print $0; found=0 }
        ' | head -1 | awk -F'"' '{print $4}'
}

check_reboot_confirmation() {
    local chat_id="$1" message="$2"
    local flag_file="/tmp/reboot_pending_${chat_id}"
    [ ! -f "$flag_file" ] && return 1
    local flag_time=$(head -1 "$flag_file")
    local now=$(date +%s)
    local diff=$((now - flag_time))
    if [ "$diff" -gt "$REBOOT_TIMEOUT" ]; then
        rm -f "$flag_file"
        send_telegram "⏰ <b>Время подтверждения истекло!</b>"
        return 1
    fi
    local msg_lower=$(echo "$message" | tr '[:upper:]' '[:lower:]' | tr -d ' \r')
    case "$msg_lower" in
        "да"|"yes"|"confirm"|"подтверждаю"|"🔄"|"✅")
            rm -f "$flag_file"
            send_telegram "✅ <b>Подтверждено! Перезагрузка через 10 секунд...</b>"
            echo "$(date '+%F %T') REBOOT by $chat_id" >> /var/log/vpn-bot.log
            setsid bash -c 'sleep 10; sync; /sbin/reboot' </dev/null >/dev/null 2>&1 &
            return 0
            ;;
        "нет"|"no"|"cancel"|"отмена"|"❌"|"🛑")
            rm -f "$flag_file"
            send_telegram "❌ <b>Перезагрузка отменена!</b>"
            return 0
            ;;
        *) return 2 ;;
    esac
}

check_restart_confirmation() {
    local chat_id="$1" message="$2"
    local flag_file="/tmp/restart_pending_${chat_id}"
    [ ! -f "$flag_file" ] && return 1
    local flag_time=$(head -1 "$flag_file")
    local now=$(date +%s)
    local diff=$((now - flag_time))
    if [ "$diff" -gt "$RESTART_TIMEOUT" ]; then
        rm -f "$flag_file"
        send_telegram "⏰ <b>Время подтверждения истекло!</b>"
        return 1
    fi
    local msg_lower=$(echo "$message" | tr '[:upper:]' '[:lower:]' | tr -d ' \r')
    case "$msg_lower" in
        "да"|"yes"|"confirm"|"подтверждаю"|"🔄"|"✅")
            rm -f "$flag_file"
            send_telegram "🔄 <b>Перезапуск контейнера...</b>"
            echo "$(date '+%F %T') RESTART by $chat_id" >> /var/log/vpn-bot.log
            setsid bash -c "sleep 2; docker restart ${CONTAINER_NAME} >/dev/null 2>&1; sleep 5; if docker ps | grep -q ${CONTAINER_NAME}; then curl -s --max-time 10 -X POST https://api.telegram.org/bot${BOT_TOKEN}/sendMessage -d chat_id=${CHAT_ID} -d 'text=✅ Контейнер перезапущен!' -d parse_mode=HTML >/dev/null 2>&1; else curl -s --max-time 10 -X POST https://api.telegram.org/bot${BOT_TOKEN}/sendMessage -d chat_id=${CHAT_ID} -d 'text=⚠️ Контейнер не запустился!' -d parse_mode=HTML >/dev/null 2>&1; fi" </dev/null >/dev/null 2>&1 &
            return 0
            ;;
        "нет"|"no"|"cancel"|"отмена"|"❌")
            rm -f "$flag_file"
            send_telegram "❌ <b>Перезапуск отменен!</b>"
            return 0
            ;;
        *) return 2 ;;
    esac
}

cmd_status() {
    if ! docker ps | grep -q "${CONTAINER_NAME}"; then
        send_telegram "❌ <b>VPN Контейнер не запущен!</b>"; return
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
            [ "$hs_seconds" -le 120 ] && ((ACTIVE_COUNT++))
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
    local host_cpu=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    local host_ram=$(free -m | awk 'NR==2{printf "%.2f/%.2f MB (%.2f%%)", $3,$2,$3*100/$2}')
    local disk=$(df -h / | awk 'NR==2{print $5}')
    local uptime=$(uptime -p)
    local ping1=$(ping -c 1 -W 2 1.1.1.1 2>&1 | grep "rtt" | awk -F'/' '{print $5}' | head -1)
    local ping2=$(ping -c 1 -W 2 ya.ru 2>&1 | grep "rtt" | awk -F'/' '{print $5}' | head -1)
    local container_status="❌ Не работает"
    docker ps | grep -q "${CONTAINER_NAME}" && container_status="✅ Работает"
    send_telegram "📊 <b>VPN СТАТУС</b>

👥 <b>Клиенты:</b>
├ Всего: ${CLIENT_COUNT}
└ Активных (≤2 мин): ${ACTIVE_COUNT}

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
}

cmd_users() {
    local data=$(docker exec ${CONTAINER_NAME} wg show | awk '
    /peer:/ { peer=$2 }
    /allowed ips:/ { ip=$3; sub(/\/32/, "", ip) }
    /latest handshake:/ { hs=$0; sub(/.*latest handshake: /, "", hs) }
    /transfer:/ { transfer=$0; sub(/.*transfer: /, "", transfer) }
    /^$/ { if (peer && ip) { printf "%s|%s|%s|%s\n", ip, peer, hs, transfer } peer=""; ip=""; hs=""; transfer="" }
    END { if (peer && ip) printf "%s|%s|%s|%s\n", ip, peer, hs, transfer }
    ' | sort -t. -k4 -n)
    local count=0
    local message="👥 <b>Список пользователей</b>
"
    while IFS='|' read -r ip key hs transfer; do
        ((count++))
        local name=$(get_name_by_ip "$ip")
        [ -z "$name" ] && name="Unknown"
        message+="${count}. <b>${name}</b> (${ip})
"
    done <<< "$data"
    message+="
📝 Используйте /userstatus N (последний октет IP) для подробной статистики."
    send_telegram "$message"
}

cmd_userstatus() {
    local search_octet="$1"
    if [ -z "$search_octet" ] || ! [[ "$search_octet" =~ ^[0-9]+$ ]]; then
        send_telegram "❌ Использование: /userstatus N (где N – последний октет IP, например 45 для myTV)"
        return
    fi
    local search_ip="10.8.1.${search_octet}"
    local name=$(get_name_by_ip "$search_ip")
    [ -z "$name" ] && name="Unknown"
    local hs="N/A" transfer="N/A" status="🔴 Офлайн"
    local peer_data=$(docker exec ${CONTAINER_NAME} wg show | awk -v ip="${search_ip}/32" '
    /peer:/ { peer=$2 }
    /allowed ips:/ { if ($3==ip) { found=1 } }
    found { print; if (/^$/ || /transfer:/) exit }
    ')
    if [ -n "$peer_data" ]; then
        hs=$(echo "$peer_data" | grep "latest handshake:" | sed "s/.*latest handshake: //")
        transfer=$(echo "$peer_data" | grep "transfer:" | sed "s/.*transfer: //")
        if [ -n "$hs" ] && [ "$hs" != "N/A" ]; then
            local hs_seconds=$(echo "$hs" | awk '{
                if (NF==0) print 99999;
                else if ($2=="day"||$2=="days") print $1*86400;
                else if ($2=="hour"||$2=="hours") print $1*3600;
                else if ($2=="minute"||$2=="minutes") print $1*60;
                else if ($2=="second"||$2=="seconds") print $1;
                else print 99999
            }')
            [ "$hs_seconds" -lt 3600 ] && status="🟢 Онлайн" || status="🟡 Был сегодня"
        fi
    fi
    send_telegram "👤 <b>${name}</b>
├ IP: ${search_ip}
├ Статус: ${status}
├ Последний Handshake: ${hs:-N/A}
└ Трафик: ${transfer:-N/A}

⏰ <b>Время:</b> $(TZ=Europe/Moscow date '+%d.%m.%Y %H:%M')"
}

cmd_clients() {
    if ! docker ps | grep -q "${CONTAINER_NAME}"; then
        send_telegram "❌ <b>VPN Контейнер не запущен!</b>"; return
    fi
    local data=$(docker exec ${CONTAINER_NAME} wg show | awk '
    /peer:/ { peer=$2 }
    /allowed ips:/ { ip=$3; sub(/\/32/, "", ip) }
    /latest handshake:/ { handshake=$0; sub(/.*latest handshake: /, "", handshake) }
    /transfer:/ { transfer=$0; sub(/.*transfer: /, "", transfer) }
    /^$/ { if (peer && ip) { printf "%s|%s|%s|%s\n", ip, peer, handshake, transfer } peer=""; ip=""; handshake=""; transfer="" }
    END { if (peer && ip) printf "%s|%s|%s|%s\n", ip, peer, handshake, transfer }
    ')
    local total=0 active=0
    local message="👥 <b>Клиенты VPN</b>
"
    while IFS='|' read -r ip peer handshake transfer; do
        ((total++))
        local name=$(get_name_by_ip "$ip")
        [ -z "$name" ] && name="Unknown"
        if [ -n "$handshake" ] && [ "$handshake" != "N/A" ]; then
            local hs_seconds=$(echo "$handshake" | awk '{
                if (NF==0) { print 99999 }
                else if ($2=="day" || $2=="days") { print $1*86400 }
                else if ($2=="hour" || $2=="hours") { print $1*3600 }
                else if ($2=="minute" || $2=="minutes") { print $1*60 }
                else if ($2=="second" || $2=="seconds") { print $1 }
                else { print 99999 }
            }')
            if [ "$hs_seconds" -lt 120 ]; then status="🟢"; ((active++))
            elif [ "$hs_seconds" -lt 86400 ]; then status="🟡"
            else status="⚪"; fi
        else
            status="⚪"; handshake="N/A"
        fi
        message+="${status} <b>${name}</b> (${ip})
   Rx/Tx: ${transfer:-N/A}
   Last: ${handshake}

"
    done <<< "$data"
    message+="📊 <b>Всего:</b> ${total}
🟢 <b>Активных:</b> ${active}

<b>Легенда:</b> 🟢 онлайн | 🟡 сегодня | ⚪ оффлайн
⏰ <b>Время:</b> $(TZ=Europe/Moscow date '+%d.%m.%Y %H:%M')"
    send_telegram "$message"
}

cmd_top() {
    if ! docker ps | grep -q "${CONTAINER_NAME}"; then
        send_telegram "❌ <b>VPN Контейнер не запущен!</b>"; return
    fi
    local top_data=$(docker exec ${CONTAINER_NAME} cat /opt/amnezia/awg/clientsTable 2>/dev/null | \
        grep -E "clientName|dataReceived|dataSent" | \
        paste - - - | awk -F'"' '{
            name=$4; rx=$8; tx=$12;
            gsub(/,/,"",rx); gsub(/,/,"",tx);
            rx_bytes=0; tx_bytes=0;
            if (rx ~ /KiB/) { gsub(/ KiB/,"",rx); rx_bytes=rx*1024 }
            else if (rx ~ /MiB/) { gsub(/ MiB/,"",rx); rx_bytes=rx*1024*1024 }
            else if (rx ~ /GiB/) { gsub(/ GiB/,"",rx); rx_bytes=rx*1024*1024*1024 }
            if (tx ~ /KiB/) { gsub(/ KiB/,"",tx); tx_bytes=tx*1024 }
            else if (tx ~ /MiB/) { gsub(/ MiB/,"",tx); tx_bytes=tx*1024*1024 }
            else if (tx ~ /GiB/) { gsub(/ GiB/,"",tx); tx_bytes=tx*1024*1024*1024 }
            total_bytes = rx_bytes + tx_bytes;
            printf "%s|%s|%s|%d\n", name, rx, tx, total_bytes
        }' | sort -t'|' -k4 -nr | head -5)
    local message="🏆 <b>Топ-5 клиентов по трафику</b>
"
    while IFS='|' read -r name rx tx total; do
        if [ $total -ge 1073741824 ]; then
            total_hr=$(awk "BEGIN {printf \"%.2f GiB\", $total/1073741824}")
        elif [ $total -ge 1048576 ]; then
            total_hr=$(awk "BEGIN {printf \"%.2f MiB\", $total/1048576}")
        else
            total_hr=$(awk "BEGIN {printf \"%.2f KiB\", $total/1024}")
        fi
        message+="<b>🔹 ${name}</b>
├ Всего: ${total_hr}
├ Получено: ${rx}
└ Отправлено: ${tx}

"
    done <<< "$top_data"
    message+="⏰ <b>Время:</b> $(TZ=Europe/Moscow date '+%d.%m.%Y %H:%M')"
    send_telegram "$message"
}

cmd_server_status() {
    local cpu=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    local mem=$(free -m | awk 'NR==2{printf "%.2f/%.2f MB (%.2f%%)", $3,$2,$3*100/$2}')
    local disk=$(df -h / | awk 'NR==2{print $5}')
    local uptime=$(uptime -p)
    local ping=$(ping -c 3 -W 2 1.1.1.1 2>&1 | grep "rtt" | awk -F'/' '{print $5}' | head -1)
    local container_status="❌ Не работает"
    docker ps | grep -q "${CONTAINER_NAME}" && container_status="✅ Работает"
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

cmd_restart_container() {
    if [ "$FROM_CHAT_ID" != "${CHAT_ID}" ]; then send_telegram "❌ <b>Доступ запрещён!</b>"; return; fi
    echo "$(date +%s)" > "/tmp/restart_pending_${CHAT_ID}"
    send_telegram "⚠️ <b>Подтвердите перезапуск контейнера!</b>

✅ <b>Для подтверждения:</b> <code>да</code> | <code>yes</code> | <code>🔄</code>
❌ <b>Для отмены:</b> <code>нет</code> | <code>no</code> | <code>❌</code>
⏱️ <b>Время:</b> ${RESTART_TIMEOUT} сек"
}

cmd_reboot_server() {
    if [ "$FROM_CHAT_ID" != "${CHAT_ID}" ]; then send_telegram "❌ <b>Доступ запрещён!</b>"; return; fi
    echo "$(date +%s)" > "/tmp/reboot_pending_${CHAT_ID}"
    send_telegram "⚠️ <b>Подтвердите перезагрузку сервера!</b>

✅ <b>Для подтверждения:</b> <code>да</code> | <code>yes</code> | <code>🔄</code>
❌ <b>Для отмены:</b> <code>нет</code> | <code>no</code> | <code>❌</code>
⏱️ <b>Время:</b> ${REBOOT_TIMEOUT} сек"
}

cmd_logs() {
    if [ "$FROM_CHAT_ID" != "${CHAT_ID}" ]; then send_telegram "❌ <b>Доступ запрещён!</b>"; return; fi
    local logs=$(tail -30 /var/log/vpn-bot.log 2>/dev/null || echo "Логов нет")
    send_telegram "📋 <b>Последние логи бота</b>
<code>${logs}</code>"
}

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

cmd_health() {
    send_telegram "🟢 <b>Бот онлайн!</b>
⏰ <b>Время:</b> $(TZ=Europe/Moscow date '+%d.%m.%Y %H:%M:%S')"
}

cmd_ping() {
    send_telegram "🔍 <b>Тест пинга...</b>"
    local result1=$(ping -c 4 -W 2 1.1.1.1 2>&1)
    local result2=$(ping -c 4 -W 2 ya.ru 2>&1)
    local avg1 avg2
    if echo "$result1" | grep -q "rtt"; then
        avg1=$(echo "$result1" | grep "rtt" | awk -F'/' '{print $5}')
    else
        avg1="N/A"
    fi
    if echo "$result2" | grep -q "rtt"; then
        avg2=$(echo "$result2" | grep "rtt" | awk -F'/' '{print $5}')
    else
        avg2="N/A"
    fi
    send_telegram "📶 <b>Результаты пинга</b>

🌍 <b>1.1.1.1:</b> ${avg1} ms
🇷🇺 <b>ya.ru:</b> ${avg2} ms

⏰ <b>Время:</b> $(TZ=Europe/Moscow date '+%d.%m.%Y %H:%M')"
}

cmd_help() {
    send_telegram "📚 <b>Справка по командам</b>

📊 <b>Мониторинг:</b>
/status - Полный статус сервера и VPN
/users - Список пользователей
/userstatus N - Статистика пользователя (N – последний октет IP)
/clients - Полный список клиентов
/top - Топ-5 клиентов по трафику

🛠️ <b>Управление:</b>
/restart_container - Перезапуск VPN (с подтверждением)
/reboot_server - Перезагрузка сервера (с подтверждением)
/cleanup - Очистка места на диске
/logs - Логи бота

🧪 <b>Тесты:</b>
/ping - Пинг до 1.1.1.1 и ya.ru
/health - Проверка, жив ли бот

ℹ️ <b>Другое:</b>
/help - Эта справка
/start - Запустить бота"
}

cmd_start() {
    send_telegram "👋 <b>Привет! Я VPN Monitor Bot</b>
⏰ <b>Время:</b> $(TZ=Europe/Moscow date '+%d.%m.%Y %H:%M')"
}

echo "🤖 Бот запущен..."
while true; do
    UPDATES=$(curl -s --max-time 15 "https://api.telegram.org/bot${BOT_TOKEN}/getUpdates?offset=${OFFSET}&timeout=3")
    LAST_UPDATE=$(echo "$UPDATES" | grep -o '"update_id":[0-9]*' | tail -1 | cut -d':' -f2)
    if [ -n "$LAST_UPDATE" ]; then
        OFFSET=$((LAST_UPDATE + 1))
        FROM_CHAT_ID=$(echo "$UPDATES" | grep -oE '"chat":\{"id":[0-9]+' | grep -oE '[0-9]+' | tail -1)
        [ -z "$FROM_CHAT_ID" ] && FROM_CHAT_ID=$(echo "$UPDATES" | sed -n 's/.*"chat":{"id":\([0-9]*\).*/\1/p' | tail -1)
        FROM_CHAT_ID=$(echo "$FROM_CHAT_ID" | tr -d ' "')
        MESSAGE_TEXT=$(echo "$UPDATES" | grep -oE '"text":"[^"]*"' | tail -1 | cut -d'"' -f4)
        log_event "$FROM_CHAT_ID" "$MESSAGE_TEXT"
        if check_reboot_confirmation "$FROM_CHAT_ID" "$MESSAGE_TEXT"; then continue; fi
        if check_restart_confirmation "$FROM_CHAT_ID" "$MESSAGE_TEXT"; then continue; fi
        case "$MESSAGE_TEXT" in
            "/status") cmd_status ;;
            "/users") cmd_users ;;
            "/userstatus "*) cmd_userstatus ${MESSAGE_TEXT#* } ;;
            "/clients") cmd_clients ;;
            "/top") cmd_top ;;
            "/ping") cmd_ping ;;
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
