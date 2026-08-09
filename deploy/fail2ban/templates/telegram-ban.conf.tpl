[Definition]
actionban = curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" -d chat_id="${CHAT_ID}" -d parse_mode="HTML" -d text="🚫 <b>IP Заблокирован!</b><br><br>🔹 IP: <code><ip></code><br>🔹 Jail: <code><name></code><br>🔹 Бан на: <b><bantime> сек</b>"
actionunban = curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" -d chat_id="${CHAT_ID}" -d parse_mode="HTML" -d text="✅ <b>IP Разблокирован</b><br><br>🔹 IP: <code><ip></code><br>🔹 Jail: <code><name></code>"
[Init]
name = default
