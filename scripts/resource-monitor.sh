[ -f /root/.vpn-env ] && source /root/.vpn-env
#!/bin/bash

# ===========================
# Настройки
# ===========================
BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"
LOG_FILE="/var/log/resource-monitor.log"

# Пороги (thresholds)
CPU_THRESHOLD=90
RAM_THRESHOLD=90
DISK_THRESHOLD=80

# ===========================
# Функция: Отправка в Telegram
# ===========================
send_telegram() {
    local message="$1"
    local parse_mode="${2:-HTML}"
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "text=${message}" \
        -d "parse_mode=${parse_mode}"
}

# ===========================
# Функция: Логирование
# ===========================
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# ===========================
# Сбор метрик
# ===========================
log "=== Проверка ресурсов ==="

# CPU загрузка (1-минутное среднее)
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 | cut -d'.' -f1)
if [ -z "$CPU_USAGE" ]; then
    # Альтернативный метод для некоторых систем
    CPU_USAGE=$(vmstat 1 2 | tail -1 | awk '{print 100 - $15}')
fi

# RAM загрузка
RAM_TOTAL=$(free -m | awk '/Mem:/{print $2}')
RAM_USED=$(free -m | awk '/Mem:/{print $3}')
RAM_PERCENT=$((RAM_USED * 100 / RAM_TOTAL))

# Disk загрузка
DISK_PERCENT=$(df / | awk '/\//{print $5}' | tr -d '%')

# Uptime
UPTIME=$(uptime -p 2>/dev/null || uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')

log "CPU: ${CPU_USAGE}%, RAM: ${RAM_PERCENT}%, Disk: ${DISK_PERCENT}%"

# ===========================
# Проверка порогов
# ===========================
ALERT_SENT=false
ALERT_MESSAGE="⚠️ <b>ВНИМАНИЕ! Превышены пороги ресурсов</b>

🖥️ <b>Сервер:</b> vm138111 (45.112.192.22)

🔴 <b>CPU критически загружена!</b>
├ Загрузка: ${CPU_USAGE}%
├ Порог: ${CPU_THRESHOLD}%
└ Рекомендация: Проверить процессы (top)

🔴 <b>RAM критически заполнена!</b>
├ Использовано: ${RAM_USED} MB / ${RAM_TOTAL} MB
├ Загрузка: ${RAM_PERCENT}%
├ Порог: ${RAM_THRESHOLD}%
└ Рекомендация: Проверить процессы (htop)

🔴 <b>Disk критически заполнен!</b>
├ Загрузка: ${DISK_PERCENT}%
├ Порог: ${DISK_THRESHOLD}%
└ Рекомендация: Запустить очистку

⏰ <b>Время:</b> $(TZ=Europe/Moscow date '+%d.%m.%Y %H:%M:%S')
⏱️ <b>Uptime:</b> ${UPTIME}"

# ===========================
# Если есть алерты — отправляем
# ===========================
if [ "$ALERT_SENT" = true ]; then
    ALERT_MESSAGE+="⏰ <b>Время:</b> $(TZ=Europe/Moscow date '+%d.%m.%Y %H:%M:%S')\n"
    ALERT_MESSAGE+="⏱️ <b>Uptime:</b> ${UPTIME}"
    
    send_telegram "$ALERT_MESSAGE"
    log "ALERT отправлен в Telegram"
else
    log "Все ресурсы в норме ✅"
fi

log "=== Проверка завершена ==="
log ""
