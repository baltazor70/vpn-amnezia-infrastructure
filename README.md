# 🛡️ AmneziaWG Secure Infrastructure & Management Bot

# 🛡️ AmneziaWG Secure Infrastructure & Management Bot

![Ubuntu](https://img.shields.io/badge/OS-Ubuntu%2024.04%20LTS-E95420?logo=ubuntu&logoColor=white)
![Docker](https://img.shields.io/badge/Container-Docker-2496ED?logo=docker&logoColor=white)
![Bash](https://img.shields.io/badge/Scripting-Bash-4EAA25?logo=gnubash&logoColor=white)
![Python](https://img.shields.io/badge/Backend-Python%203.12-3776AB?logo=python&logoColor=white)
![Nginx](https://img.shields.io/badge/Proxy-Nginx-009639?logo=nginx&logoColor=white)
![Security](https://img.shields.io/badge/Security-UFW%20%2B%20Fail2ban-red)

Профессиональная инфраструктура для развёртывания, автоматического мониторинга и администрирования защищённого VPN-сервера AmneziaWG на базе ОС **Ubuntu 24.04 LTS**. Проект включает в себя Telegram-бота для интерактивного контроля и веб-панель статуса с аутентификацией.

# 🛡️ AmneziaWG Secure Infrastructure & Management Bot

## 🌟 Основные возможности

- **VPN AmneziaWG в Docker**: Контейнеризированный сервер с автоматической установкой и сетевым тюнингом (BBR) для стабильного пинга под нагрузкой.
- **Интерактивный Telegram-бот**: Полный мониторинг, вывод топа потребителей, перезапуск с системой двухэтапного подтверждения. Использует надежный Python-парсинг JSON.
- **Безопасная панель Flask**: Доступна на порту `45678` с SSL-сертификатом и паролем администратора.
- **Эшелонированная оборона**: UFW (запрет по умолчанию), Fail2ban с алертами в Telegram, изоляция процессов через systemd (`ProtectSystem=full`).
- **Автоматизация Cron**: Мониторинг ресурсов, резервное копирование, очистка мусора и автоматические ночные перезагрузки.

## 🛠️ Развёртывание

Запустите установщик на чистой ОС Ubuntu 24.04 LTS от пользователя `root`:

```bash
chmod +x install.sh
./install.sh
```

В процессе установки скрипт запросит в защищённом режиме (без вывода на экран):

- Токен вашего Telegram-бота (`BOT_TOKEN`).
- ID чата администратора (`CHAT_ID`).
- Пароль для входа в панель Flask (`FLASK_ADMIN_PASSWORD`).

Режим проверки здоровья (Health Check):

```bash
./install.sh --check
```

## 🛡️ Безопасность и Харденинг

- **Защита переменных**: Конфигурационный файл `/root/.vpn-env` закрыт маской `600`.
- **Systemd Isolation**: Сервисы бота работают с флагами `NoNewPrivileges=true` и `ProtectSystem=full`.
- **Сетевая безопасность**: UFW открывает только порты `22`, `443` и `45678`. Fail2ban мониторит логи и банит подозрительную активность.

## 🏗️ Архитектурные схемы

### 1. Операционная архитектура

```mermaid
graph TD
    subgraph Telegram_Cloud [Telegram Cloud Platform]
        TG_API[Telegram Bot API]
    end

    subgraph Host_Server [Ubuntu 24.04 LTS Server]
        subgraph Systemd_Services [Systemd Services]
            BOT_SVC[vpn-bot.service] -->|Запуск| BOT_SCRIPT[vpn-bot-listener.sh]
            FLASK_SVC[status.service] -->|Запуск| FLASK_APP[app.py]
        end

        subgraph Docker_Engine [Docker Engine]
            AWG_CONT[Container: amnezia-awg2] -->|WG Engine| WG_CORE[WireGuard Kernel Module]
        end

        subgraph Automation [Cron Jobs]
            CRON[System Crontab] -->|Периодический вызов| ALERTS[vpn-alert.sh]
            CRON -->|Раз в час| CLEAN[cleanup-orphans.sh]
            CRON -->|Сбор данных| METRICS[metrics-logger.sh]
        end

        BOT_SCRIPT -->|Команды CLI| AWG_CONT
        FLASK_APP -->|Чтение метрик| AWG_CONT
    end

    BOT_SCRIPT <==>|getUpdates / sendMessage| TG_API
```

### 2. Архитектура безопасности

```mermaid
graph LR
    subgraph Internet [Внешний мир]
        ATTACKER[Злоумышленник]
        ADMIN_TG[Администратор]
    end

    subgraph Security_Perimeter [Контур безопасности]
        UFW{UFW Firewall}
        F2B[Fail2ban Jail]
        NGINX[Nginx Reverse Proxy]
        ENV_SEC[(/root/.vpn-env 600)]

        subgraph Trusted_Zone [Доверенная зона]
            FLASK[Flask Web UI: 8080]
            BOT[vpn-bot-listener.sh]
        end
    end

    ATTACKER -->|Скан портов| UFW
    UFW -->|Порты 22, 443, 45678| F2B
    F2B -->|Обнаружение аномалий| NGINX
    NGINX -->|SSL-терминация| FLASK
    ADMIN_TG <-->|HTTPS API| BOT
    BOT -->|Чтение секретов| ENV_SEC
```

## 🛠️ Шпаргалка админа

```bash
# Проверка здоровья системы
./install.sh --check

# Статус сервисов
systemctl status vpn-bot.service
docker ps --filter name=amnezia-awg2

# Безопасность: просмотр забаненных IP
sudo fail2ban-client status vpn-monitoring
sudo fail2ban-client set vpn-monitoring unbanip <IP>

# Обслуживание
/root/scripts/backup-docker.sh      # Ручной бэкап
/root/scripts/cleanup-orphans.sh    # Очистка дискового пространства
```
