[ -f /root/.vpn-env ] && source /root/.vpn-env
#!/bin/bash

# ===========================
# Настройки
# ===========================
BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"
CONTAINER_NAME="amnezia-awg2"
STATE_FILE="/tmp/vpn-peers-state"
CONF_DIR="/root/.amnezia"  # Папка с конфигами Amnezia

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
# Функция: получить имя клиента по ключу
# ===========================
get_peer_name() {
    local peer_key="$1"
    # Ищем файл конфига, содержащий этот публичный ключ
    local conf_file=$(grep -rl "PublicKey = ${peer_key}" ${CONF_DIR}/*.conf 2>/dev/null | head -1)
    
    if [ -n "$conf_file" ]; then
        # Возвращаем имя файла без пути и расширения
        basename "$conf_file" .conf
    else
        echo "Unknown"
    fi
}

# ===========================
# Получаем текущих клиентов
# ===========================
# Формат: одна строка на клиента: "peer_key endpoint"
get_current_peers() {
    docker exec ${CONTAINER_NAME} wg show | \
    awk '/peer:/{peer=$2} /endpoint:/{print peer, $2}' | \
    sort
}

# ===========================
# Основная логика
# ===========================

# Если файл состояния не существует — создаём и выходим (первый запуск)
if [ ! -f "$STATE_FILE" ]; then
    get_current_peers > "$STATE_FILE"
    echo "📋 Первый запуск. Сохранено текущее состояние."
    exit 0
fi

# Читаем предыдущее состояние
OLD_PEERS=$(cat "$STATE_FILE")

# Получаем текущее состояние
NEW_PEERS=$(get_current_peers)

# Если ничего не изменилось — выходим
if [ "$OLD_PEERS" = "$NEW_PEERS" ]; then
    exit 0
fi

# ===========================
# Находим изменения
# ===========================

# Новые подключения (есть в NEW, но нет в OLD)
CONNECTED=$(comm -13 <(echo "$OLD_PEERS" | cut -d' ' -f1 | sort) <(echo "$NEW_PEERS" | cut -d' ' -f1 | sort))

# Отключения (есть в OLD, но нет в NEW)
DISCONNECTED=$(comm -23 <(echo "$OLD_PEERS" | cut -d' ' -f1 | sort) <(echo "$NEW_PEERS" | cut -d' ' -f1 | sort))

# ===========================
# Формируем и отправляем уведомления
# ===========================

# Уведомления о подключениях
for peer_key in $CONNECTED; do
    peer_name=$(get_peer_name "$peer_key")
    endpoint=$(echo "$NEW_PEERS" | grep "^$peer_key" | awk '{print $2}')
    
    MESSAGE="🟢 <b>Новое подключение к VPN</b>

👤 Устройство: <b>${peer_name}</b>
🔑 Ключ: <code>${peer_key:0:16}...</code>
🌐 IP: ${endpoint}
⏰ Время: $(TZ=Europe/Moscow date '+%d.%m.%Y %H:%M')"
    
    send_telegram "$MESSAGE"
done

# Уведомления об отключениях
for peer_key in $DISCONNECTED; do
    peer_name=$(get_peer_name "$peer_key")
    
    MESSAGE="🔴 <b>Клиент отключился от VPN</b>

👤 Устройство: <b>${peer_name}</b>
🔑 Ключ: <code>${peer_key:0:16}...</code>
⏰ Время: $(TZ=Europe/Moscow date '+%d.%m.%Y %H:%M')"
    
    send_telegram "$MESSAGE"
done

# ===========================
# Обновляем файл состояния
# ===========================
echo "$NEW_PEERS" > "$STATE_FILE"
