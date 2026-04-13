[ -f /root/.vpn-env ] && source /root/.vpn-env
#!/bin/bash
# auto-reboot.sh — перезагрузка + безопасность + уведомления (МСК время)

# ==================== НАСТРОЙКИ ====================
BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"
CONTAINER_NAME="amnezia-awg2"
SERVER_NAME="🇳🇱 VPN-Server (Amsterdam)"
LOG_FILE="/var/log/auto-reboot.log"
TZ="Europe/Moscow"  # ✅ Единое время МСК
# ===================================================

# Функция отправки в Telegram
send_tg() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "text=${message}" \
        -d "parse_mode=HTML" >> "${LOG_FILE}" 2>&1
}

# Логирование с МСК временем
log() {
    echo "[$(TZ=${TZ} date '+%Y-%m-%d %H:%M:%S')] $1" >> "${LOG_FILE}"
}

# Формат даты для сообщений (как в твоих скриптах)
get_time_msk() {
    TZ=${TZ} date '+%d.%m.%Y %H:%M'
}

# ==================== ПРЕ-УВЕДОМЛЕНИЕ ====================
log "=== Начало процедуры перезагрузки ==="

send_tg "🔔 <b>${SERVER_NAME}</b>

⚠️ <b>Плановая перезагрузка через 5 минут!</b>

⏰ Время: $(TZ=Europe/Moscow date '+%d.%m.%Y %H:%M')
📍 Причина: Обновления безопасности + профилактика

🔄 VPN отключится на ~2-3 минуты.
🛡️ Будут установлены системные обновления."

log "Отправлено пре-уведомление"

# Ждём 5 минут
sleep 300

# ==================== ОБНОВЛЕНИЯ БЕЗОПАСНОСТИ ====================
log "Запускаю обновления безопасности..."

send_tg "🔄 <b>${SERVER_NAME}</b>

🛠️ <b>Установка обновлений...</b>

⏳ Это может занять 2-5 минут."

# Обновляем пакеты безопасности (безопасный режим)
export DEBIAN_FRONTEND=noninteractive
apt-get update >> "${LOG_FILE}" 2>&1
apt-get upgrade -y --only-upgrade \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" >> "${LOG_FILE}" 2>&1

# Чистим кэш
apt-get autoremove -y >> "${LOG_FILE}" 2>&1
apt-get autoclean >> "${LOG_FILE}" 2>&1

log "Обновления завершены"

# ==================== ПЕРЕЗАГРУЗКА ====================
log "Выполняю reboot..."

send_tg "⏰ Время: $(TZ=Europe/Moscow date '+%d.%m.%Y %H:%M')

🔌 <b>Перезагрузка сервера...</b>

⏱️ Ожидаемое время: ~1-2 минуты"

# Перезагружаем (в фоне)
reboot &

# Скрипт завершится, пост-проверку выполнит post-reboot-check.sh
