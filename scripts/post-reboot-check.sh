[ -f /root/.vpn-env ] && source /root/.vpn-env
#!/bin/bash
# post-reboot-check.sh — проверка статуса после перезагрузки (МСК время)

# ==================== НАСТРОЙКИ ====================
BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"
CONTAINER_NAME="amnezia-awg2"
SERVER_NAME="🇳🇱 VPN-Server (Amsterdam)"
LOG_FILE="/var/log/auto-reboot.log"
TZ="Europe/Moscow"
MAX_WAIT=180
# ===================================================

send_tg() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "text=${message}" \
        -d "parse_mode=HTML" >> "${LOG_FILE}" 2>&1
}

log() {
    echo "[$(TZ=${TZ} date '+%Y-%m-%d %H:%M:%S')] $1" >> "${LOG_FILE}"
}

get_time_msk() {
    TZ=${TZ} date '+%d.%m.%Y %H:%M'
}

log "=== Пост-ребут проверка ==="
sleep 15

# ==================== ПРОВЕРКА СЕРВИСОВ ====================
docker_status="❌ Не запущен"
docker_ok=false
for i in $(seq 1 $MAX_WAIT); do
    if docker info > /dev/null 2>&1; then
        docker_status="✅ Запущен"
        docker_ok=true
        log "Docker поднялся через ${i} сек"
        break
    fi
    sleep 1
done

amnezia_status="❌ Не найден"
amnezia_ok=false
if [ "$docker_ok" = true ]; then
    for i in $(seq 1 $MAX_WAIT); do
        if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
            amnezia_status="✅ Работает"
            amnezia_ok=true
            log "Контейнер ${CONTAINER_NAME} поднялся через ${i} сек"
            break
        fi
        sleep 1
    done
fi

port_status="❌ Не слушается"
port_found=""
if [ "$amnezia_ok" = true ]; then
    if ss -tulpn | grep -q ":36991 "; then
        port_status="✅ 36991/UDP"
        port_found="36991"
    elif ss -tulpn | grep -q ":443 "; then
        port_status="✅ 443/UDP"
        port_found="443"
    fi
fi

active_peers=0
if [ "$amnezia_ok" = true ]; then
    active_peers=$(docker exec ${CONTAINER_NAME} wg show 2>/dev/null | grep -c "latest handshake:.*second\|minute\|hour")
fi

ping_status="✅ OK"
if ! ping -c 1 -W 2 1.1.1.1 > /dev/null 2>&1; then
    ping_status="⚠️ Проблемы"
fi

# ==================== ОТЧЁТ (в твоём стиле) ====================
if [ "$docker_ok" = true ] && [ "$amnezia_ok" = true ] && [ -n "$port_found" ]; then
    emoji="✅"
    title="Перезагрузка успешна!"
    color="🟢"
    result="OK"
else
    emoji="❌"
    title="Перезагрузка с ошибками!"
    color="🔴"
    result="ERROR"
fi

message="${emoji} <b>${SERVER_NAME}</b>

${title}

⏰ Время: $(TZ=Europe/Moscow date '+%d.%m.%Y %H:%M')
⏱️ Аптайм: $(uptime -p)
🔄 Результат: ${result}

<b>📊 Статус сервисов:</b>
├ Docker: ${docker_status}
├ ${CONTAINER_NAME}: ${amnezia_status}
├ Порт WG: ${port_status}
├ Активные пиры: ${active_peers}
└ Ping: ${ping_status}

<b>🛡️ Обновления:</b>
└ Установлены перед ребутам

${color} VPN готов к работе!"

send_tg "$message"
log "Отправлен пост-отчёт: $title"

# Детали при ошибке
if [ "$result" = "ERROR" ]; then
    error_details="🔴 <b>Детали ошибки:</b>
    
<b>Docker:</b> $(docker info 2>&1 | head -3)
<b>Контейнеры:</b> $(docker ps -a --format '{{.Names}}: {{.Status}}' 2>&1 | head -5)
<b>Порты:</b> $(ss -tulpn 2>&1 | grep -E '36991|443' || echo 'Не найдены')
    
🔧 <i>Требуется ручная проверка!</i>"
    send_tg "$error_details"
fi
