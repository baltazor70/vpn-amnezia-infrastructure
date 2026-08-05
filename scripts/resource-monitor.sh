#!/bin/bash
source /root/.vpn-env

LOG_FILE="/var/log/resource-monitor.log"
CPU_THRESHOLD=90
RAM_THRESHOLD=90
DISK_THRESHOLD=80

send_telegram() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "text=${message}" \
        -d "parse_mode=HTML" > /dev/null
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log "=== Проверка ресурсов ==="

CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 | cut -d'.' -f1)
[ -z "$CPU_USAGE" ] && CPU_USAGE=$(vmstat 1 2 | tail -1 | awk '{print 100 - $15}')

RAM_TOTAL=$(free -m | awk '/Mem:/{print $2}')
RAM_USED=$(free -m | awk '/Mem:/{print $3}')
RAM_PERCENT=$((RAM_USED * 100 / RAM_TOTAL))

DISK_PERCENT=$(df / | awk '/\//{print $5}' | tr -d '%')

log "CPU: ${CPU_USAGE}%, RAM: ${RAM_PERCENT}%, Disk: ${DISK_PERCENT}%"

ALERT_MESSAGE="⚠️ <b>ВНИМАНИЕ! Превышены пороги ресурсов</b>

🖥️ <b>Сервер:</b> $(hostname) (45.112.192.22)
"

ALERT_SENT=false

if [ -n "$CPU_USAGE" ] && [ "$CPU_USAGE" -gt "$CPU_THRESHOLD" ]; then
    ALERT_SENT=true
    ALERT_MESSAGE+="🔴 <b>CPU критически загружена!</b>
├ Загрузка: ${CPU_USAGE}%
├ Порог: ${CPU_THRESHOLD}%
└ Рекомендация: Проверить процессы (top)

"
fi

if [ "$RAM_PERCENT" -gt "$RAM_THRESHOLD" ]; then
    ALERT_SENT=true
    ALERT_MESSAGE+="🔴 <b>RAM критически заполнена!</b>
├ Использовано: ${RAM_USED} MB / ${RAM_TOTAL} MB
├ Загрузка: ${RAM_PERCENT}%
├ Порог: ${RAM_THRESHOLD}%
└ Рекомендация: Проверить процессы (htop)

"
fi

if [ "$DISK_PERCENT" -gt "$DISK_THRESHOLD" ]; then
    ALERT_SENT=true
    ALERT_MESSAGE+="🔴 <b>Диск критически заполнен!</b>
├ Загрузка: ${DISK_PERCENT}%
├ Порог: ${DISK_THRESHOLD}%
└ Рекомендация: Запустить очистку

"
fi

if [ "$ALERT_SENT" = true ]; then
    ALERT_MESSAGE+="⏰ <b>Время:</b> $(TZ=Europe/Moscow date '+%d.%m.%Y %H:%M:%S')
⏱️ <b>Uptime:</b> $(uptime -p)"
    send_telegram "$ALERT_MESSAGE"
    log "ALERT отправлен в Telegram"
else
    log "Все ресурсы в норме ✅"
fi

log "=== Проверка завершена ==="
