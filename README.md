# VPN Amnezia Infrastructure

Персональный VPN-сервер на базе AmneziaWG. Лёгкий, безопасный, с мониторингом.

**Статус:** ✅ Аудит завершён (v1.2) | Все компоненты проверены

## 🚀 Быстрый старт

```bash
curl -s https://raw.githubusercontent.com/baltazor70/vpn-amnezia-infrastructure/main/install.sh | bash
bash install.sh --check
🔐 Безопасность (v1.2)
SSH: только ключи (PasswordAuthentication no)
Fail2ban: SSH + веб-интерфейс (лог: /var/log/nginx/access.log)
UFW: default deny, порты 22/tcp, 443/tcp+udp, 45678/tcp
Секреты: /root/.vpn-env (права 600), скрытый ввод в install.sh
SSL: self-signed для веб-панели
Скрипты (16 файлов)
Сервисы:
vpn-bot-listener.sh — Telegram-бот (systemd)
status.service — Flask-дашборд (systemd)
Мониторинг (cron):
vpn-alert.sh (*/2 min) — алерты подключений
resource-monitor.sh (*/5 min) — CPU/RAM/Disk
metrics-logger.sh (*/15 min) — сбор метрик
vpn-monitor.sh (09:00, 21:00) — ежедневный отчёт
Обслуживание:
vpn-container-watchdog.sh (*/5 min) — авто-восстановление контейнера
cleanup-orphans.sh (hourly) — удаление "сирот" WireGuard
backup-docker.sh (Wed/Sun 02:45) — бэкап конфигов
auto-reboot.sh (Mon/Wed 03:00) — плановый ребут + обновления
post-reboot-check.sh (@reboot) — проверка после перезагрузки
cleanup-server.sh (Sun 03:00) — очистка диска
Инструменты (ручные):
audit-peers.sh — полный аудит пиров
vpn-traffic.sh — просмотр трафика
check-client.sh — диагностика клиента
peer-sniff.sh — захват трафика tcpdump
️ Архитектура

1234567
Сеть:
Клиенты → UDP 36991 → Docker NAT → Интернет
SMTP 25/465/587 → через провайдера (разблокировано)
Админ → SSH 22 (ключи), HTTPS 45678 (пароль)
📊 Аудит v1.2
Проверено:
✅ 16 bash-скриптов (назначение, зависимости, риски)
✅ Docker-контейнер amnezia-awg2 (конфиг, порты, volumes)
✅ Системные пакеты (Ubuntu 24.04, Docker 29.7, Python 3.12, Flask 3.0.2)
✅ Nginx reverse proxy (SSL, проксирование)
✅ Fail2ban (sshd + vpn-monitoring)
✅ Сетевая конфигурация (UFW, iptables NAT, SMTP-транзит)
✅ Systemd-юниты (vpn-bot.service, status.service)
✅ install.sh (hardened: UFW, скрытый ввод, health-check)
Исправлено:
Fail2ban logpath: vpn-status-access.log → access.log
install.sh: добавлены UFW rules, read -s для секретов, валидация
Добавлен health-check в конце установки
🧪 Disaster Recovery
Проверка: ./install.sh --check
Аудит пиров: ./audit-peers.sh (должно быть 0 Unknown)
Тест watchdog: docker stop amnezia-awg2 (восстановит за ≤60 сек)
Экстренное восстановление:
Потеря SSH: консоль провайдера → ufw status, fail2ban-client unbanall
Потеря сервера: развернуть Ubuntu 24.04 → скопировать /root/backups/vpn/ → install.sh
📋 Telegram-бот
Команды: /status /users /clients /top /ping /restart_container /reboot_server /cleanup /logs /help
🌐 Веб-панель
Доступ: https://<IP>:45678
Аутентификация: пароль из .vpn-env
Показывает: статус VPN, сервера, пинг, графики (24ч), Fail2ban
🤝 Contributing
Перед PR:
./install.sh --check — все проверки должны пройти
Убедитесь, что изменения не ломают скрипты
Обновите документацию
Контакты:
Issues: https://github.com/baltazor70/vpn-amnezia-infrastructure/issues
Discussions: https://github.com/baltazor70/vpn-amnezia-infrastructure/discussions
MIT License | Не коммитьте .env и секреты в публичные репозитории
