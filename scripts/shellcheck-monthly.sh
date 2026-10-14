#!/usr/bin/env bash
# Monthly shellcheck run for all scripts (Telegram alert on issues)
# Алерт в Telegram только при наличии предупреждений.

set -uo pipefail

# Загружаем секреты
source /root/.vpn-env

LOG="/var/log/vpn-infra/shellcheck-monthly.log"
REPORT="/tmp/shellcheck-report-$(date +%F).txt"
mkdir -p "$(dirname "$LOG")"

# Куда смотреть
TARGETS=(
    /root/scripts/*.sh
    /opt/vpn-amnezia-infrastructure/install.sh
)

# Прогон shellcheck (собираем все warning и error, игнорируем info/style)
{
    echo "=== shellcheck report $(date '+%Y-%m-%d %H:%M:%S') ==="
    for f in "${TARGETS[@]}"; do
        [[ -f "$f" ]] || continue
        echo
        echo "--- $f ---"
        shellcheck -S warning -f gcc "$f" 2>&1 || true
    done
} > "$REPORT" 2>&1

# Сколько реальных предупреждений?
ISSUE_COUNT=$(grep -cE ':\s*(error|warning):' "$REPORT" || true)

# Логируем всегда
{
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] shellcheck run, issues=$ISSUE_COUNT"
} >> "$LOG"

# Отправляем в Telegram только если есть проблемы
if (( ISSUE_COUNT > 0 )); then
    # Telegram ограничивает сообщения ~4096 символов, режем до 3500
    HEAD=$(head -c 3500 "$REPORT")
    TEXT="🛡️ <b>ShellCheck monthly report</b>
⚠️ Найдено проблем: <b>${ISSUE_COUNT}</b>

<pre>${HEAD}</pre>

Полный отчёт: <code>${REPORT}</code>"

    curl -fsS -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "parse_mode=HTML" \
        --data-urlencode "text=${TEXT}" \
        >/dev/null 2>&1 || echo "WARN: telegram send failed" >> "$LOG"
else
    echo "OK: no issues" >> "$LOG"
fi

# Ротация отчётов — старше 90 дней удаляем
find /tmp -maxdepth 1 -name 'shellcheck-report-*.txt' -mtime +90 -delete 2>/dev/null || true
