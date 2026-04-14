# 🛡️ VPN AmneziaWG Infrastructure

> Автоматизированная инфраструктура для развёртывания личного WireGuard-VPN на базе AmneziaWG с управлением через Telegram-бота.

![Status](https://img.shields.io/badge/status-stable-green)
![License](https://img.shields.io/badge/license-MIT-blue)
![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04-orange)
![Clients](https://img.shields.io/badge/clients-up%20to%2040-blue)

---

## 📋 О проекте

Готовое решение для развёртывания VPN-сервера с полной автоматизацией. Все компоненты написаны на Bash, используют Docker и управляются через Telegram-бота.

**Производительность:**
- ✅ До 40 одновременных профилей подключения
- ✅ Стабильная работа с веб-сёрфингом, мессенджерами, HD-видео
- ⚠️ Не рекомендуется для 4K-стриминга и торрентов

---

## 🖥️ Требования к серверу

| Параметр | Минимум | Рекомендуется |
|----------|---------|---------------|
| **ОС** | Ubuntu 22.04 / Debian 11 | Ubuntu 24.04 LTS |
| **RAM** | 512 MB | 1 GB+ |
| **Диск** | 10 GB | 15 GB+ |
| **CPU** | 1 vCore | 2 vCore |
| **Сеть** | IPv4 | 100 Mbps+ |

---

## 🏗️ Архитектура

**Клиенты (до 40)**  
↓ AmneziaWG (UDP)  
**Сервер VPS**  
├─ Docker: AmneziaWG  
├─ Telegram Bot (управление)  
├─ Fail2ban (защита SSH)  
└─ Авто-бэкапы (30 дней)

---

## 🤖 Управление через Telegram

| Команда | Описание |
|---------|----------|
| `/start` | Запустить бота |
| `/stat` | Статистика: клиенты, трафик, ресурсы |
| `/clients` | Список клиентов со статусом |
| `/traffic` | Трафик по каждому клиенту |
| `/server_status` | CPU, RAM, диск, пинг |
| `/restart_container` | Перезапуск VPN (с подтверждением) |
| `/reboot_server` | Перезагрузка сервера (с подтверждением) |
| `/cleanup` | Очистка места на диске |
| `/backup` | Ручной запуск бэкапа |
| `/health` | Проверка статуса бота |

---

## 🔔 Автоматические уведомления

- 🟢 Новые подключения клиентов
- 🔴 Отключения клиентов
- ⚠️ Превышение порогов ресурсов (CPU >90%, RAM >90%, Disk >80%)
- 🔄 Уведомления о перезагрузке (до и после)
- 💾 Отчёты о бэкапах

---

## 📁 Структура проекта

vpn-amnezia-infrastructure/
├── README.md # Документация
├── LICENSE # MIT License
├── .gitignore # Исключения Git
│
├── scripts/
│ ├── vpn-bot-listener.sh # Telegram-бот
│ ├── vpn-alert.sh # Уведомления
│ ├── cleanup-server.sh # Очистка диска
│ ├── backup-docker.sh # Бэкапы
│ ├── vpn-container-watchdog.sh # Авто-восстановление
│ ├── auto-reboot.sh # Перезагрузка
│ ├── post-reboot-check.sh # Проверка после рестарта
│ ├── resource-monitor.sh # Мониторинг ресурсов
│ ├── vpn-monitor.sh # Статус VPN
│ ├── vpn-traffic.sh # Трафик клиентов
│ └── safe-ports.txt # Безопасные порты
│
├── systemd/
│ └── vpn-bot.service # Автозапуск бота
│
└── examples/
└── .vpn-env.example # Шаблон переменных


---

## 🚀 Установка

```bash
# 1. Клонируй репозиторий
git clone https://github.com/baltazor70/vpn-amnezia-infrastructure.git
cd vpn-amnezia-infrastructure

# 2. Настрой переменные
cp examples/.vpn-env.example /root/.vpn-env
nano /root/.vpn-env
# Заполни: BOT_TOKEN, CHAT_ID, CONTAINER_NAME

# 3. Установи Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
usermod -aG docker $USER

# 4. Настрой скрипты
chmod +x scripts/*.sh

# 5. Установи сервис бота
cp systemd/vpn-bot.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now vpn-bot.service

# 6. Проверь: отправь /start в Telegram

ащита
✅ Fail2ban — защита SSH от брутфорса
✅ Автообновления — unattended-upgrades
✅ Шифрованные бэкапы конфигов WireGuard
✅ Подтверждение критических действий

Просмотр логов

tail -f /var/log/vpn-bot.log
tail -f /var/log/vpn-watchdog.log
journalctl -u vpn-bot.service -f

# Автоматически (раз в неделю):
0 3 * * 0 /root/scripts/backup-docker.sh

# Восстановление конфигов:
cat backup_*/amnezia_awg_config.tar.gz | \
    docker exec -i amnezia-awg2 tar xzf - -C /opt/amnezia/awg


