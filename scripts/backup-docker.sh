[ -f /root/.vpn-env ] && source /root/.vpn-env
#!/bin/bash
# backup-docker.sh — бэкап VPN инфраструктуры с уведомлениями об ошибках

# ===========================
# Настройки Telegram
# ===========================
BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"

# Функция отправки в Telegram
send_telegram() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "text=${message}" \
        -d "parse_mode=HTML" > /dev/null
}

# Функция отправки ошибки
send_error() {
    local error_message="$1"
    send_telegram "❌ <b>ОШИБКА БЭКАПА VPN!</b>

🖥️ <b>Сервер:</b> $(hostname)
📅 <b>Дата:</b> $(date '+%Y-%m-%d %H:%M:%S')

🚨 <b>Ошибка:</b>
${error_message}

⚠️ <b>Требуется внимание!</b>"
}

# ===========================
# Настройки бэкапа
# ===========================
BACKUP_DIR="/root/backups/vpn"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="$BACKUP_DIR/backup_$DATE"
HOSTNAME=$(hostname)
ERRORS=()

mkdir -p "$BACKUP_PATH"

# ===========================
# Начало бэкапа
# ===========================
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  🔄 НАЧАЛО БЭКАПА VPN                                         ║"
echo "╠════════════════════════════════════════════════════════════════╣"
echo "📅 Дата: $DATE"
echo "📁 Путь: $BACKUP_PATH"
echo ""

send_telegram "🔄 <b>Начало бэкапа VPN</b>

📅 Дата: $DATE
🖥️ Сервер: $HOSTNAME

⏳ Выполняется..."

# ===========================
# 1. Бэкап скриптов
# ===========================
echo "📦 [1/6] Копирую скрипты..."
if cp -r /root/scripts "$BACKUP_PATH/" 2>/dev/null; then
    SCRIPT_COUNT=$(ls "$BACKUP_PATH/scripts/" | wc -l)
    echo "   ✅ Скрипты: $SCRIPT_COUNT файлов"
else
    echo "   ❌ ОШИБКА: Не удалось скопировать скрипты!"
    ERRORS+=("❌ Скрипты: не скопированы")
fi

# ===========================
# 2. Бэкап логов
# ===========================
echo "📦 [2/6] Копирую логи..."
cp /var/log/vpn-bot.log "$BACKUP_PATH/" 2>/dev/null
cp /var/log/vpn-alert.log "$BACKUP_PATH/" 2>/dev/null
cp /var/log/cleanup-server.log "$BACKUP_PATH/" 2>/dev/null
echo "   ✅ Логи скопированы"

# ===========================
# 3. Бэкап конфигов Amnezia WireGuard (КРИТИЧНО!)
# ===========================
echo "📦 [3/6] Копирую конфиги WireGuard..."
docker exec amnezia-awg2 tar czf - -C /opt/amnezia/awg . 2>/dev/null > "$BACKUP_PATH/amnezia_awg_config.tar.gz"
if [ $? -eq 0 ] && [ -s "$BACKUP_PATH/amnezia_awg_config.tar.gz" ]; then
    CONFIG_SIZE=$(du -h "$BACKUP_PATH/amnezia_awg_config.tar.gz" | cut -f1)
    echo "   ✅ Конфиги WireGuard: $CONFIG_SIZE"
    CONFIG_STATUS="✅ Конфиги: $CONFIG_SIZE"
    CONFIG_OK=true
else
    echo "   ❌ ОШИБКА: Не удалось скопировать конфиги WireGuard!"
    ERRORS+=("❌ Конфиги WireGuard: не скопированы")
    CONFIG_STATUS="❌ Конфиги: ОШИБКА"
    CONFIG_OK=false
fi

# ===========================
# 4. Сохраняем wg show
# ===========================
echo "📦 [4/6] Сохраняем состояние WireGuard..."
if docker exec amnezia-awg2 wg show > "$BACKUP_PATH/wg-show.txt" 2>/dev/null; then
    PEER_COUNT=$(grep -c "peer:" "$BACKUP_PATH/wg-show.txt" 2>/dev/null || echo "0")
    echo "   ✅ Пиров: $PEER_COUNT"
else
    echo "   ⚠️ ПРЕДУПРЕЖДЕНИЕ: Не удалось получить wg show"
    PEER_COUNT="N/A"
    ERRORS+=("⚠️ wg show: не получен")
fi

# ===========================
# 5. Информация о контейнере
# ===========================
echo "📦 [5/6] Сохраняем инфо о контейнере..."
if docker inspect amnezia-awg2 > "$BACKUP_PATH/container-inspect.json" 2>/dev/null; then
    IMAGE_NAME=$(docker inspect amnezia-awg2 --format='{{.Config.Image}}')
    echo "   ✅ Образ: $IMAGE_NAME"
else
    echo "   ⚠️ ПРЕДУПРЕЖДЕНИЕ: Не удалось получить inspect"
    IMAGE_NAME="N/A"
    ERRORS+=("⚠️ Container inspect: не получен")
fi

# ===========================
# 6. README
# ===========================
cat > "$BACKUP_PATH/README.txt" << README
VPN BACKUP - $DATE
==================
Сервер: $HOSTNAME
Создано: $(date)

Состав:
- scripts/ ($SCRIPT_COUNT файлов)
- amnezia_awg_config.tar.gz (ключи WireGuard)
- wg-show.txt ($PEER_COUNT пиров)
- *.log (логи)
- container-inspect.json

Восстановление:
cat amnezia_awg_config.tar.gz | docker exec -i amnezia-awg2 tar xzf - -C /opt/amnezia/awg
README

# ===========================
# 7. Проверка критических ошибок
# ===========================
echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "ПРОВЕРКА КРИТИЧЕСКИХ ОШИБОК..."
echo "═══════════════════════════════════════════════════════════════════"

# КРИТИЧНО: Если конфиги WireGuard не скопированы — это провал
if [ "$CONFIG_OK" = false ]; then
    echo "❌ КРИТИЧЕСКАЯ ОШИБКА: Конфиги WireGuard не скопированы!"
    send_error "КРИТИЧЕСКАЯ ОШИБКА: Конфиги WireGuard не скопированы!

📁 Путь: $BACKUP_PATH
🔑 Это означает, что ключи клиентов не сохранены!

Возможные причины:
• Контейнер amnezia-awg2 не работает
• Путь /opt/amnezia/awg/ не существует
• Нет прав на чтение

Проверь:
docker exec amnezia-awg2 ls -la /opt/amnezia/awg/"
    
    # Очищаем неполный бэкап
    rm -rf "$BACKUP_PATH"
    echo "🗑️ Неполный бэкап удалён"
    exit 1
fi

# ===========================
# 8. Размер бэкапа
# ===========================
SIZE=$(du -sh "$BACKUP_PATH" | cut -f1)
TOTAL_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)
BACKUP_COUNT=$(ls -d "$BACKUP_DIR"/backup_* 2>/dev/null | wc -l)

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
if [ ${#ERRORS[@]} -gt 0 ]; then
    echo "║  ⚠️  БЭКАП ЗАВЕРШЁН С ПРЕДУПРЕЖДЕНИЯМИ                        ║"
else
    echo "║  ✅ БЭКАП ЗАВЕРШЁН!                                            ║"
fi
echo "╠════════════════════════════════════════════════════════════════╣"
echo "📊 Размер: $SIZE"
echo "📁 Путь: $BACKUP_PATH"
echo "📦 Всего бэкапов: $BACKUP_COUNT"
echo "🗄️ Общий размер: $TOTAL_SIZE"
echo "╚════════════════════════════════════════════════════════════════╝"

# ===========================
# 9. Чистка старых бэкапов
# ===========================
echo ""
echo "🧹 Удаляю бэкапы старше 30 дней..."
OLD_COUNT=$(find "$BACKUP_DIR" -type d -mtime +30 2>/dev/null | wc -l)
find "$BACKUP_DIR" -type d -mtime +30 -exec rm -rf {} \; 2>/dev/null
echo "   Удалено: $OLD_COUNT старых бэкапов"

# ===========================
# 10. Отправляем отчёт в Telegram
# ===========================
if [ ${#ERRORS[@]} -gt 0 ]; then
    # Есть ошибки — отправляем предупреждение
    ERROR_LIST=$(printf "├ %s\n" "${ERRORS[@]}")
    send_telegram "⚠️ <b>Бэкап VPN завершён с предупреждениями!</b>

🖥️ <b>Сервер:</b> $HOSTNAME
📅 <b>Дата:</b> $DATE

📊 <b>Результаты:</b>
├ $CONFIG_STATUS
├ Пиров: $PEER_COUNT
├ Скриптов: ${SCRIPT_COUNT:-0}
├ Размер: $SIZE
└ Всего бэкапов: $BACKUP_COUNT

🚨 <b>Предупреждения:</b>
${ERROR_LIST}

⚠️ <b>Рекомендуется проверить!</b>"
else
    # Всё хорошо — отправляем успех
    send_telegram "✅ <b>Бэкап VPN завершён!</b>

🖥️ <b>Сервер:</b> $HOSTNAME
📅 <b>Дата:</b> $DATE

📊 <b>Результаты:</b>
├ $CONFIG_STATUS
├ Пиров: $PEER_COUNT
├ Скриптов: ${SCRIPT_COUNT:-0}
├ Размер: $SIZE
└ Всего бэкапов: $BACKUP_COUNT

🗄️ <b>Общий размер:</b> $TOTAL_SIZE
🧹 <b>Удалено старых:</b> $OLD_COUNT

⏰ <b>Следующий:</b> $(TZ=Europe/Moscow date '+%d.%m.%Y %H:%M' -d '+7 days')"
fi

# ===========================
# 11. Логирование
# ===========================
if [ ${#ERRORS[@]} -gt 0 ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Backup completed with warnings: ${#ERRORS[@]} errors" >> /var/log/backup-docker.log
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Backup completed successfully: $SIZE" >> /var/log/backup-docker.log
fi

echo "✅ Готово!"

# ===========================
# 12. Выход с кодом ошибки (для cron)
# ===========================
if [ ${#ERRORS[@]} -gt 0 ]; then
    exit 1
else
    exit 0
fi
