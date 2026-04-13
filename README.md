# # 🛡️ VPN AmneziaWG Infrastructure

> Лёгкая, надёжная и полностью автоматизированная инфраструктура для личного WireGuard-VPN на базе **AmneziaWG** с управлением через **Telegram-бота**.

![Status](https://img.shields.io/badge/status-stable-green)
![License](https://img.shields.io/badge/license-MIT-blue)
![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04-orange)
![Docker](https://img.shields.io/badge/Docker-ready-blue)

---

## 📖 Описание

Этот проект — готовое решение для развёртывания личного VPN-сервера с полной автоматизацией. Все компоненты написаны на Bash, используют Docker и управляются через Telegram-бота.

**Идеально подходит для:**
- 👨‍👩‍👧‍👦 Личного использования (се
- 🏢 Малых команд (до 40 устройств)
- 🎓 Обучения и экспериментов с VPN-инфраструктурой

---

## 🖥️ Технические характеристики сервера

### Текущая конфигурация (пример)

| Параметр | Значение | Примечание |
|----------|----------|-----------|
| **ОС** | Ubuntu 24.04.4 LTS | Долгосрочная поддержка до 2029 |
| **Ядро** | Linux 6.8.0-106-generic | Актуальное, с поддержкой WireGuard |
| **Архитектура** | x86-64 | Стандартная для большинства VPS |
| **Виртуализация** | KVM | Полная виртуализация |
| **CPU** | 1 vCore | Достаточно для 25-30 клиентов |
| **RAM** | 961 MB | Используется ~32% в простое |
| **Диск** | 14.68 GB SSD | Используется ~35% |
| **Сеть** | 100 Mbps+ | IPv4 + IPv6 |
| **Локация** | Амстердам, Нидерланды | Низкий пинг до РФ (~44ms) |

### Минимальные требования

| Компонент | Минимум | Рекомендуется |
|-----------|---------|---------------|
| **ОС** | Ubuntu 22.04 / Debian 11 | Ubuntu 24.04 LTS |
| **RAM** | 512 MB | 1 GB+ |
| **Диск** | 10 GB | 15 GB+ |
| **CPU** | 1 vCore | 2 vCore |
| **Сеть** | IPv4 | IPv4 + IPv6 |

---

## 🏗️ Архитектура проекта

---

## 🎯 Возможности

### 🤖 Управление через Telegram

| Команда | Описание | Доступ |
|---------|----------|--------|
| `/start` | Запустить бота | Все |
| `/stat` | Общая статистика: клиенты, трафик, ресурсы | Все |
| `/clients` | Список клиентов со статусом (онлайн/оффлайн) | Все |
| `/traffic` | Трафик по каждому клиенту (Rx / Tx) | Все |
| `/server_status` | Статус сервера: CPU, RAM, диск, пинг | Все |
| `/restart_container` | Перезапуск VPN-контейнера (с подтверждением) | Админ |
| `/reboot_server` | Перезагрузка сервера (с подтверждением) | Админ |
| `/cleanup` | Очистка места на диске | Админ |
| `/backup` | Ручной запуск полного бэкапа | Админ |
| `/logs` | Последние логи бота | Админ |
| `/speedtest` | Тест канала до ya.ru | Все |
| `/health` | Проверка, жив ли бот | Все |
| `/help` | Справка по командам | Все |

### 🔔 Автоматические уведомления

- 🟢 **Новое подключение** — Имя, ключ, внешний IP, время
- 🔴 **Отключение клиента** — Имя, ключ, время
- ⚠️ **Превышение порогов** — Тип ресурса, значение, рекомендация
- 🔄 **Перезагрузка** — Предупреждение за 5 минут + отчёт
- 💾 **Бэкап** — Успех или ошибка с деталями

### 🛡️ Безопасность

- ✅ **Fail2ban** — защита SSH от брутфорса (600+ атак отбито)
- ✅ **Автообновления** — `unattended-upgrades` для security-патчей
- ✅ **Шифрованные бэкапы** — резервное копирование конфигов WireGuard
- ✅ **Секреты через .env** — токены не хранятся в коде репозитория
- ✅ **Подтверждение действий** — перезагрузка/рестарт только с подтверждением

---

## 📁 Описание скриптов

### 📁 `scripts/` — Основные скрипты

| Файл | Размер | Назначение |
|------|--------|-----------|
| **🤖 vpn-bot-listener.sh** | 16.7 KB | Основной Telegram-бот: 13 команд, логирование, подтверждение действий |
| **🔔 vpn-alert.sh** | 3.9 KB | Уведомления о подключениях/отключениях клиентов |
| **🧹 cleanup-server.sh** | 3.3 KB | Очистка диска: Docker prune, journalctl, обрезка логов |
| **💾 backup-docker.sh** | 10.4 KB | Полный бэкап: конфиги, скрипты, логи; ротация 30 дней |
| **🐕 vpn-container-watchdog.sh** | 9.9 KB | Авто-восстановление: мониторинг, 3 попытки рестарта, бэкап |
| **🔄 auto-reboot.sh** | 2.9 KB | Плановая перезагрузка: предупреждение, обновления, ребут |
| **✅ post-reboot-check.sh** | 3.8 KB | Проверка после рестарта: Docker, контейнер, порт, отчёт |
| **📊 resource-monitor.sh** | 3.2 KB | Мониторинг ресурсов: CPU/RAM/Disk, алерты при превышении |
| **🛡️ vpn-monitor.sh** | 3.3 KB | Статус VPN: клиенты, трафик, ресурсы контейнера |
| **📈 vpn-traffic.sh** | 2.2 KB | CLI: вывод трафика по клиентам с форматированием |
| **📋 safe-ports.txt** | 408 B | Список безопасных портов для обхода блокировок |

### 📁 `systemd/` — Сервисы автозапуска

| Файл | Назначение |
|------|-----------|
| **⚙️ vpn-bot.service** | Автозапуск Telegram-бота: `Restart=always`, после Docker |

### 📁 `examples/` — Примеры

| Файл | Назначение |
|------|-----------|
| **🔐 .vpn-env.example** | Шаблон переменных окружения (токены, пути) |

---

## 🚀 Установка

### Требования

- ✅ **ОС:** Ubuntu 22.04+ / Debian 11+
- ✅ **Docker Engine** установлен
- ✅ **Git** для клонирования репозитория
- ✅ **Telegram бот** (получить у @BotFather)
- ✅ **Chat ID** (узнать у @userinfobot)

### Пошаговая установка

```bash
# 1. Клонируй репозиторий
git clone https://github.com/baltazor70/vpn-amnezia-infrastructure.git
cd vpn-amnezia-infrastructure

# 2. Настрой переменные окружения
cp examples/.vpn-env.example /root/.vpn-env
nano /root/.vpn-env
# Заполни:
#   BOT_TOKEN="твой_токен_от_BotFather"
#   CHAT_ID="твой_chat_id"
#   CONTAINER_NAME="amnezia-awg2"
#   BACKUP_DIR="/root/backups/vpn"

# 3. Установи Docker (если не установлен)
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
usermod -aG docker $USER
# Перелогинься или выполни: newgrp docker

# 4. Настрой скрипты
chmod +x scripts/*.sh

# 5. Установи systemd сервис для бота
cp systemd/vpn-bot.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable vpn-bot.service
systemctl start vpn-bot.service

# 6. Проверь работу бота
# Отправь /start в Telegram# Автоматический бэкап (раз в неделю через cron):
# Добавь в crontab (crontab -e):
0 3 * * 0 /root/scripts/backup-docker.sh

# Ручной запуск:
/root/scripts/backup-docker.sh

# Восстановление конфигов WireGuard из бэкапа:
cat /root/backups/vpn/backup_*/amnezia_awg_config.tar.gz | \
    docker exec -i amnezia-awg2 tar xzf - -C /opt/amnezia/awg
🖥️ Сервер: Ubuntu 24.04.4 LTS
💾 RAM: 961 MB (используется ~32%)
🗄️ Диск: 14.68 GB (используется ~35%)
⚡ CPU: 1 vCore (load ~0.27)
👥 Клиентов: 19 (9 активных)
🛡️ Протокол: AmneziaWG (UDP 36991)
🌐 Пинг до РФ: ~44 ms
🌍 Пинг до глобальных: ~2 ms

# В scripts/resource-monitor.sh:
CPU_THRESHOLD=90    # Алерт при загрузке CPU >90%
RAM_THRESHOLD=90    # Алерт при использовании RAM >90%
DISK_THRESHOLD=80   # Алерт при заполнении диска >80%

# Бот:
tail -f /var/log/vpn-bot.log

# Watchdog:
tail -f /var/log/vpn-watchdog.log

# Бэкапы:
tail -f /var/log/backup-docker.log

# Systemd сервисы:
journalctl -u vpn-bot.service -f

git clone https://github.com/baltazor70/vpn-amnezia-infrastructure.git
cd vpn-amnezia-infrastructure
cp examples/.vpn-env.example /root/.vpn-env

# Edit /root/.vpn-env with your tokens
chmod +x scripts/*.sh
cp systemd/vpn-bot.service /etc/systemd/system/
systemctl enable --now vpn-bot.service
