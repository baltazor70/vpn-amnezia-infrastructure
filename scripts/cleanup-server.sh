[ -f /root/.vpn-env ] && source /root/.vpn-env
#!/bin/bash

# ===========================
# Настройки
# ===========================
LOG_FILE="/var/log/cleanup-server.log"
DRY_RUN=False  # true = тестовый запуск, false = реальная очистка

# ===========================
# Функция: Логирование
# ===========================
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# ===========================
# Начало
# ===========================
log "=== Начало очистки сервера ==="
log "Режим: $([ "$DRY_RUN" = true ] && echo 'DRY RUN (тест)' || echo 'LIVE (очистка)')"

# --- 1. Дисковое пространство ДО ---
DISK_BEFORE=$(df -h / | awk '/\//{print $5}')
log "Диск ДО: $DISK_BEFORE занято"

# --- 2. Docker cleanup ---
log "Очистка Docker..."
if [ "$DRY_RUN" = false ]; then
    docker system prune -af --volumes >> "$LOG_FILE" 2>&1
fi
log "Docker cleanup completed"

# --- 3. Журналы системы (оставляем 7 дней) ---
log "Очистка journalctl..."
if [ "$DRY_RUN" = false ]; then
    journalctl --vacuum-time=7d >> "$LOG_FILE" 2>&1
fi
log "Journal cleanup completed"

# --- 3.1 Обрезка наших логов (если >10MB) ---
log "Обрезка логов мониторинга..."
for monitor_log in /var/log/resource-monitor.log /var/log/vpn-bot.log /var/log/vpn-monitor.log; do
    if [ -f "$monitor_log" ]; then
        size=$(stat -c%s "$monitor_log" 2>/dev/null)
        if [ "$size" -gt 10485760 ]; then  # 10 MB
            if [ "$DRY_RUN" = false ]; then
                # Оставляем только последние 1000 строк
                tail -1000 "$monitor_log" > "${monitor_log}.tmp" && mv "${monitor_log}.tmp" "$monitor_log"
                log "Обрезан: $(basename $monitor_log)"
            fi
        fi
    fi
done

# --- 3.1 Обрезка логов (если >10MB) ---
log "Обрезка логов мониторинга..."
for monitor_log in /var/log/resource-monitor.log /var/log/vpn-bot.log /var/log/vpn-monitor.log /var/log/auto-reboot.log; do
    if [ -f "$monitor_log" ]; then
        size=$(stat -c%s "$monitor_log" 2>/dev/null)
        if [ "$size" -gt 10485760 ]; then  # 10 MB
            if [ "$DRY_RUN" = false ]; then
                # Оставляем только последние 1000 строк
                tail -1000 "$monitor_log" > "${monitor_log}.tmp" && mv "${monitor_log}.tmp" "$monitor_log"
                log "Обрезан: $(basename $monitor_log)"
            fi
        fi
    fi
done

# --- 5. Временные файлы ---
log "Очистка временных файлов..."
if [ "$DRY_RUN" = false ]; then
    rm -rf /tmp/*.log 2>/dev/null
    rm -rf /var/tmp/* 2>/dev/null
    rm -rf /root/.cache/pip/* 2>/dev/null
fi
log "Temp files cleanup completed"

# --- 6. Пакеты apt ---
log "Очистка пакетов apt..."
if [ "$DRY_RUN" = false ]; then
    apt autoremove -y >> "$LOG_FILE" 2>&1
    apt autoclean >> "$LOG_FILE" 2>&1
fi
log "APT cleanup completed"

# --- 7. Дисковое пространство ПОСЛЕ ---
DISK_AFTER=$(df -h / | awk '/\//{print $5}')
log "Диск ПОСЛЕ: $DISK_AFTER занято"
log "=== Очистка завершена ==="
log ""
