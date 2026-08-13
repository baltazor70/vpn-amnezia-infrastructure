# 🛡️ VPN Amnezia Infrastructure

Персональный VPN-сервер на базе AmneziaWG для семьи и друзей.

---

## 🚀 Быстрый старт

### Установка (только Ubuntu 24.04 LTS)

    curl -s https://raw.githubusercontent.com/baltazor70/vpn-amnezia-infrastructure/main/install.sh | bash

### Проверка системы

    bash install.sh --check

---

## 🔐 Безопасность

- **SSH:** Только аутентификация по ключам
- **Fail2ban:** Защита SSH и веб-интерфейса
- **UFW:** Минимальный набор портов (22, 443, 45678)
- **Секреты:** Все токены в /root/.vpn-env (права 600)

---

## 📦 Что включает

### Системные компоненты
- Docker 29.7 + Amnezia WireGuard
- Nginx (reverse proxy на порт 45678)
- Flask (веб-панель мониторинга)
- Fail2ban + UFW
- Python 3.12

### Скрипты автоматизации (16 файлов)
- vpn-bot-listener.sh — Telegram-бот управления
- vpn-alert.sh — уведомления о подключениях
- resource-monitor.sh — мониторинг CPU/RAM/Disk
- metrics-logger.sh — сбор метрик для графиков
- vpn-monitor.sh — ежедневные отчёты
- backup-docker.sh — бэкап конфигов
- auto-reboot.sh — плановые обновления

---

## 🏗️ Архитектура

    Ubuntu 24.04 LTS
    ├── Docker: amnezia-awg2 (WireGuard UDP 36991)
    ├── Nginx:45678 → Flask:8080 (веб-панель)
    ├── Telegram Bot (vpn-bot-listener.sh)
    ├── Cron-скрипты мониторинга
    └── Fail2ban + UFW

---

##  Аудит v1.2

**Проверено:**
- ✅ 16 bash-скриптов
- ✅ Docker-контейнер amnezia-awg2
- ✅ Системные пакеты (Ubuntu 24.04, Docker, Python, Flask)
- ✅ Nginx reverse proxy
- ✅ Fail2ban (исправлен путь к логу)
- ✅ UFW правила
- ✅ install.sh (добавлены UFW, скрытый ввод, health-check)

**Исправлено:**
1. Fail2ban logpath: vpn-status-access.log → access.log
2. install.sh: добавлены правила UFW
3. install.sh: скрытый ввод секретов (read -s)
4. install.sh: финальный health-check

---

## 🧪 Disaster Recovery

### Проверка системы

    ./install.sh --check

### Аудит пиров

    ./audit-peers.sh

Ожидаемый результат: 0 Unknown

### Тест watchdog

    docker stop amnezia-awg2

Ожидаемый результат: контейнер восстановится за ≤60 сек

### Экстренное восстановление

**Потеря SSH:**
1. Использовать консоль провайдера
2. Проверить: ufw status, fail2ban-client unbanall
3. Восстановить authorized_keys

**Полная потеря сервера:**
1. Развернуть Ubuntu 24.04 + Docker
2. Скопировать /root/backups/vpn/
3. Запустить install.sh

---

## 📋 Telegram-бот

**Команды:**
- /status — полный статус сервера
- /users — список пользователей
- /clients — таблица клиентов
- /top — топ-5 по трафику
- /ping — проверка пинга
- /restart_container — перезапуск контейнера
- /reboot_server — перезагрузка сервера
- /help — справка

---

## 🌐 Веб-панель

**Доступ:** https://<IP>:45678

**Аутентификация:** Пароль из /root/.vpn-env

**Показывает:**
- Статус VPN и сервера
- Ping до Cloudflare и Яндекса
- Ресурсы (CPU, RAM, диск)
- Графики за 24 часа
- Статус Fail2ban

---


**Контакты:**
- Issues: https://github.com/baltazor70/vpn-amnezia-infrastructure/issues
- Discussions: https://github.com/baltazor70/vpn-amnezia-infrastructure/discussions

---

> 📄 **License:** MIT  

