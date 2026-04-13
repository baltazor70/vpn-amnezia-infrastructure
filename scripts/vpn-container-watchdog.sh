[ -f /root/.vpn-env ] && source /root/.vpn-env
#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# 🛡️ VPN Container Watchdog — Авто-восстановление контейнера
# Версия: 1.0
# ═══════════════════════════════════════════════════════════════

set -e

# ===========================
# 🔐 Настройки (загружаются из .env)
# ===========================
if [ -f /root/.vpn-env ]; then
    source /root/.vpn-env
elif [ -f /root/.env ]; then
    source /root/.env
fi

# Проверка обязательных переменных
if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
    echo "❌ Error: BOT_TOKEN and CHAT_ID must be set in /root/.vpn-env"
    exit 1
fi

# Настройки по умолчанию
CONTAINER_NAME="${CONTAINER_NAME:-amnezia-awg2}"
BACKUP_DIR="${BACKUP_DIR:-/root/backups/vpn}"
LOG_FILE="/var/log/vpn-watchdog.log"
TZ="Europe/Moscow"
MAX_RESTART_ATTEMPTS=3
RESTART_DELAY=10

# ===========================
# 📝 Функции логирования и отправки
# ===========================
log() {
    echo "[$(TZ=${TZ} date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

send_telegram() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "text=${message}" \
        -d "parse_mode=HTML" \
        -d "disable_web_page_preview=true" >> "${LOG_FILE}" 2>&1
}

# ===========================
# 🔍 Проверка состояния контейнера
# ===========================
check_container_status() {
    if docker ps | grep -q "${CONTAINER_NAME}"; then
        return 0  # Контейнер работает
    else
        return 1  # Контейнер не работает
    fi
}

# ===========================
# 🔄 Попытка перезапуска контейнера
# ===========================
try_restart_container() {
    local attempt=$1
    
    log "🔄 Попытка перезапуска #${attempt}..."
    
    send_telegram "🔄 <b>Попытка восстановления VPN (#{attempt})</b>

🖥️ <b>Сервер:</b> $(hostname)
 <b>Контейнер:</b> ${CONTAINER_NAME}
⏱️ <b>Задержка:</b> ${RESTART_DELAY} сек

⏳ Выполняется..."

    # Попытка запуска
    if docker start ${CONTAINER_NAME} >> "${LOG_FILE}" 2>&1; then
        sleep ${RESTART_DELAY}
        
        # Проверяем, что контейнер действительно поднялся
        if docker ps | grep -q "${CONTAINER_NAME}"; then
            # Проверяем, что WireGuard работает
            if docker exec ${CONTAINER_NAME} wg show >> "${LOG_FILE}" 2>&1; then
                log "✅ Контейнер успешно перезапущен!"
                send_telegram "✅ <b>VPN восстановлен!</b>

🖥️ <b>Сервер:</b> $(hostname)
🐳 <b>Контейнер:</b> ${CONTAINER_NAME}
🔄 <b>Попытка:</b> #${attempt}
⏰ <b>Время:</b> $(TZ=${TZ} date '+%d.%m.%Y %H:%M')

✅ Все сервисы работают нормально."
                return 0
            else
                log "⚠️ Контейнер запущен, но WireGuard не отвечает"
            fi
        else
            log "❌ Контейнер не запустился"
        fi
    else
        log "❌ Ошибка при запуске контейнера"
    fi
    
    return 1
}

# ===========================
# 💾 Восстановление из бэкапа
# ===========================
restore_from_backup() {
    log "💾 Начинаю восстановление из бэкапа..."
    
    send_telegram "⚠️ <b>Восстановление VPN из бэкапа</b>

🖥️ <b>Сервер:</b> $(hostname)
🐳 <b>Контейнер:</b> ${CONTAINER_NAME}
📁 <b>Бэкап:</b> ${BACKUP_DIR}

⏳ Выполняется..."

    # Находим последний бэкап
    LATEST_BACKUP=$(ls -td ${BACKUP_DIR}/backup_* 2>/dev/null | head -1)
    
    if [ -z "$LATEST_BACKUP" ] || [ ! -d "$LATEST_BACKUP" ]; then
        log "❌ Бэкапы не найдены!"
        send_telegram "❌ <b>ОШИБКА: Бэкапы не найдены!</b>

️ <b>Сервер:</b> $(hostname)
📁 <b>Путь:</b> ${BACKUP_DIR}

🚨 Требуется ручное вмешательство!"
        return 1
    fi
    
    log "📁 Найден бэкап: ${LATEST_BACKUP}"
    
    # Останавливаем контейнер (если работает)
    docker stop ${CONTAINER_NAME} >> "${LOG_FILE}" 2>&1 || true
    
    # Восстанавливаем конфиги Amnezia
    if [ -f "${LATEST_BACKUP}/amnezia_awg_config.tar.gz" ]; then
        log "📦 Восстанавливаю конфиги WireGuard..."
        
        # Создаём временную папку для распаковки
        TEMP_RESTORE="/tmp/wg-restore-$(date +%s)"
        mkdir -p "$TEMP_RESTORE"
        
        # Распаковываем бэкап
        tar xzf "${LATEST_BACKUP}/amnezia_awg_config.tar.gz" -C "$TEMP_RESTORE"
        
        # Копируем конфиги в контейнер
        docker exec ${CONTAINER_NAME} mkdir -p /opt/amnezia/awg
        docker cp "${TEMP_RESTORE}/." ${CONTAINER_NAME}:/opt/amnezia/awg/
        
        # Очищаем временную папку
        rm -rf "$TEMP_RESTORE"
        
        log "✅ Конфиги восстановлены"
    else
        log "❌ Файл amnezia_awg_config.tar.gz не найден в бэкапе"
    fi
    
    # Запускаем контейнер
    log "🚀 Запускаю контейнер..."
    docker start ${CONTAINER_NAME} >> "${LOG_FILE}" 2>&1
    
    sleep 10
    
    # Проверяем, что всё работает
    if docker ps | grep -q "${CONTAINER_NAME}"; then
        if docker exec ${CONTAINER_NAME} wg show >> "${LOG_FILE}" 2>&1; then
            log "✅ Восстановление из бэкапа успешно!"
            send_telegram "✅ <b>VPN восстановлен из бэкапа!</b>

🖥️ <b>Сервер:</b> $(hostname)
📁 <b>Бэкап:</b> $(basename $LATEST_BACKUP)
⏰ <b>Время:</b> $(TZ=${TZ} date '+%d.%m.%Y %H:%M')

✅ Все сервисы работают нормально.

⚠️ <b>Рекомендация:</b>
Проверьте подключение клиентов и при необходимости переимпортируйте конфиги."
            return 0
        fi
    fi
    
    log "❌ Восстановление не удалось"
    send_telegram "❌ <b>Восстановление из бэкапа НЕ УДАЛОСЬ!</b>

🖥️ <b>Сервер:</b> $(hostname)
📁 <b>Бэкап:</b> $(basename $LATEST_BACKUP)

🚨 Требуется ручное вмешательство!"
    return 1
}

# ===========================
# 🏁 Основная функция восстановления
# ===========================
main() {
    log "╔════════════════════════════════════════════════════════════════╗"
    log "║  🛡️ VPN Container Watchdog — Проверка                        ║"
    log "╚════════════════════════════════════════════════════════════════╝"
    
    # Проверяем статус контейнера
    if check_container_status; then
        log "✅ Контейнер работает. Выход."
        exit 0
    fi
    
    log "❌ Контейнер НЕ работает! Начинаю восстановление..."
    
    send_telegram "🚨 <b>VPN Контейнер упал!</b>

🖥️ <b>Сервер:</b> $(hostname)
🐳 <b>Контейнер:</b> ${CONTAINER_NAME}
⏰ <b>Время:</b> $(TZ=${TZ} date '+%d.%m.%Y %H:%M')

🔄 Начинаю попытки восстановления..."
    
    # Попытка 1-3: Перезапуск контейнера
    for attempt in $(seq 1 $MAX_RESTART_ATTEMPTS); do
        if try_restart_container $attempt; then
            log "✅ Восстановление завершено успешно!"
            exit 0
        fi
        sleep 5
    done
    
    # Попытка 4: Восстановление из бэкапа
    log "💾 Перезапуск не удался. Пробую восстановление из бэкапа..."
    
    if restore_from_backup; then
        log "✅ Восстановление из бэкапа успешно!"
        exit 0
    fi
    
    # Всё провалилось
    log "❌ Все попытки восстановления провалились!"
    send_telegram "❌ <b>КРИТИЧЕСКАЯ ОШИБКА!</b>

🖥️ <b>Сервер:</b> $(hostname)
🐳 <b>Контейнер:</b> ${CONTAINER_NAME}

🚨 Все попытки автоматического восстановления провалились!

🔧 <b>Требуется ручное вмешательство:</b>
1. Проверьте логи: journalctl -u docker
2. Проверьте место на диске: df -h
3. Проверьте бэкапы: ls -la ${BACKUP_DIR}
4. При необходимости — поднимите контейнер вручную

⏰ <b>Время:</b> $(TZ=${TZ} date '+%d.%m.%Y %H:%M')"
    
    exit 1
}

# Запуск
main "$@"
