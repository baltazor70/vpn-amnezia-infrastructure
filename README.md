# 🛡️ AmneziaWG Secure Infrastructure & Management Bot

![Ubuntu](https://img.shields.io/badge/OS-Ubuntu%2024.04%20LTS-E95420?logo=ubuntu&logoColor=white)
![Docker](https://img.shields.io/badge/Container-Docker-2496ED?logo=docker&logoColor=white)
![Bash](https://img.shields.io/badge/Scripting-Bash-4EAA25?logo=gnubash&logoColor=white)
![Python](https://img.shields.io/badge/Backend-Python%203.12-3776AB?logo=python&logoColor=white)
![Nginx](https://img.shields.io/badge/Proxy-Nginx-009639?logo=nginx&logoColor=white)
![Security](https://img.shields.io/badge/Security-UFW%20%2B%20Fail2ban-red)

Профессиональная инфраструктура для развёртывания, автоматического мониторинга и администрирования защищённого VPN-сервера AmneziaWG на базе ОС **Ubuntu 24.04 LTS**. Проект включает в себя Telegram-бота для интерактивного контроля и веб-панель статуса с аутентификацией.

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

- **Защита переменных**: Конфигурационный файл `/root/.vpn-env` закрыт маской `600` (только root).
- **Systemd Isolation**: Сервисы бота работают в песочнице с флагами `NoNewPrivileges=true`, `ProtectSystem=full` и `PrivateTmp=true`.
- **Сетевая безопасность**: UFW открывает только порты `22`, `443` и `45678`. Fail2ban мониторит логи и банит подозрительную активность с алертами в Telegram.
- **Синхронизация времени (NTP)**: `systemd-timesyncd` принудительно активен. Это критически важно для предотвращения replay-атак в WireGuard/AmneziaWG.
- **Защита от переполнения диска**: Docker настроен на автоматическую ротацию логов (макс. 3 файла по 10 МБ), что исключает отказ системы из-за нехватки места.
- **Hardening Nginx**: Веб-сервер скрыл свою версию (`server_tokens off`) и ограничил максимальный размер запроса (`1M`) для защиты от DoS-атак на панель.

## 🏗️ Архитектурные схемы

### 1. Операционная архитектура

```mermaid
flowchart LR
    subgraph Admin["👤 Administrator Zone"]
        AdminLaptop["🖥️ SSH Client"]
    end

    subgraph Internet["🌐 Internet"]
        Cloud["☁️ Public Network"]
    end

    subgraph VPS["🖥️ VPS Host Ubuntu 24.04"]
        direction TB
        
        subgraph Kernel["⚙️ Kernel Layer"]
            BBR["📡 TCP BBR + Extended Buffers"]
        end
        
        subgraph Firewall["🛡️ UFW Firewall"]
            UFW["Default DENY<br/>Port Isolation"]
            RouteRule["🔀 UFW Route Rule<br/>NAT to Docker"]
        end
        
        subgraph Docker["🐳 Docker Network 10.8.1.0/24"]
            direction TB
            wg0["🔌 Virtual Interface wg0"]
            Container["📦 amnezia-awg2 Container<br/>UDP 36991 Obfuscated"]
            wg0 --> Container
        end
        
        subgraph Web["🌐 Web Panel Stack"]
            Nginx["🔒 Nginx Reverse Proxy<br/>TCP 45678 + SSL"]
            Flask["🐍 Flask App<br/>localhost:8080"]
            Nginx --> Flask
        end
    end

    subgraph Clients["📱 VPN Clients Zone"]
        Client1["📱 Mobile Client 1"]
        Client2["💻 Desktop Client"]
        Client3["📱 Mobile Client 2"]
    end

    subgraph Monitoring["🤖 Monitoring"]
        TGBot["☁️ Telegram Bot API"]
        TGAdmin["📱 Admin Telegram Client"]
        BotService["🤖 vpn-bot.service<br/>Python JSON Parser"]
    end

    AdminLaptop -->|"SSH Port 22<br/>Encrypted"| UFW
    UFW --> Kernel
    Kernel -->|"Localhost"| Flask
    UFW -->|"Route Rule"| RouteRule
    RouteRule -->|"NAT/Masquerade"| Container
    
    Client1 & Client2 & Client3 -->|"WireGuard Tunnel<br/>UDP 36991<br/>Obfuscated"| UFW
    UFW -->|"Forward to Docker"| Container
    
    Container -->|"Metrics"| BotService
    BotService -->|"curl API<br/>Auto-split >3800 chars"| TGBot
    TGBot -->|"Push Alerts"| TGAdmin
    
    style Admin fill:#e3f2fd,stroke:#1976d2
    style VPS fill:#f3e5f5,stroke:#7b1fa2
    style Clients fill:#e8f5e9,stroke:#388e3c
    style Monitoring fill:#fff3e0,stroke:#f57c00
    style Container fill:#9c27b0,stroke:#4a148c,color:#fff
    style UFW fill:#f44336,stroke:#b71c1c,color:#fff
```

### 2. Полная инфраструктура VPS

```mermaid
flowchart TD
    subgraph AdminZone["👤 Administrator Zone"]
        Admin["💻 Admin Laptop"]
        SSH["🔐 SSH Key Auth"]
        TGClient["📱 Telegram Client<br/>Monitoring & Alerts"]
        Admin --> SSH
        Admin --> TGClient
    end

    subgraph VPS["🖥️ VPS Infrastructure"]
        direction TB
        
        subgraph Perimeter["🛡️ Perimeter Security"]
            UFW["UFW Firewall<br/>Default DENY"]
            Fail2ban["Fail2ban<br/>SSH + VPN Jails"]
        end
        
        subgraph Host["Ubuntu Host 24.04 LTS"]
            direction TB
            
            subgraph DockerLayer["🐳 Docker Layer"]
                AWG["amnezia-awg2<br/>UDP 36991<br/>10.8.1.0/24"]
            end
            
            subgraph SystemLayer["⚙️ System Layer"]
                BotService["vpn-bot.service<br/>ProtectSystem=full<br/>NoNewPrivileges=true"]
                FlaskService["status.service<br/>Flask Web UI"]
                KernelTuning["⚙️ Kernel Tuning<br/>BBR + Net Buffers"]
            end
            
            subgraph CronJobs["🕒 Cron Automation"]
                Watchdog["🔄 watchdog.sh<br/>every 5 min"]
                Metrics["📊 metrics-logger.sh<br/>every 15 min"]
                AutoReboot["🔄 auto-reboot.sh<br/>Mon/Wed 03:00"]
                PostCheck["✅ post-reboot-check.sh<br/>After reboot"]
                Backup["💾 backup-docker.sh<br/>Daily"]
            end
        end
        
        subgraph WebStack["🌐 Web Panel"]
            Nginx["Nginx<br/>TCP 45678 + SSL"]
            Flask["Flask App<br/>localhost:8080"]
            Nginx --> Flask
        end
        
        Perimeter --> Host
        Host --> WebStack
    end

    subgraph ClientZone["📱 Client Zone"]
        Client1["📱 Amnezia App"]
        Client2["💻 WireGuard Client"]
        Client3["📱 Mobile Client"]
    end

    subgraph Telegram["☁️ Telegram Cloud"]
        TGAPI["Telegram Bot API"]
    end

    SSH -->|"Port 22<br/>Encrypted"| UFW
    UFW --> Host
    
    Client1 & Client2 & Client3 -->|"UDP 36991<br/>Obfuscated WG"| UFW
    UFW -->|"NAT Forward"| AWG
    
    AWG -->|"wg show metrics"| BotService
    BotService -->|"Python json.dumps<br/>Auto-split >3800 chars"| TGAPI
    TGAPI -->|"Push Notifications"| TGClient
    
    Watchdog & Metrics & AutoReboot & PostCheck & Backup --> BotService
    Flask -->|"Read metrics"| AWG
    Flask -->|"System stats"| BotService
    
    style AdminZone fill:#e3f2fd,stroke:#1976d2
    style VPS fill:#f3e5f5,stroke:#7b1fa2
    style ClientZone fill:#e8f5e9,stroke:#388e3c
    style Telegram fill:#fff3e0,stroke:#f57c00
    style AWG fill:#9c27b0,stroke:#4a148c,color:#fff
    style BotService fill:#d32f2f,stroke:#b71c1c,color:#fff
    style UFW fill:#f44336,stroke:#b71c1c,color:#fff
```

### 3. Модель безопасности (Defense in Depth)

```mermaid
flowchart TB
    subgraph External["⚠️ External Threats"]
        Attacker["👤 Potential Attacker"]
        Internet["☁️ Public Internet"]
    end

    subgraph Perimeter["🛡️ Perimeter Security Layer"]
        direction TB
        UFW["🔥 UFW Firewall<br/>Default Policy: DENY ALL<br/>Allowed: 22/tcp, 45678/tcp, 36991/udp"]
        Fail2ban["🚫 Fail2ban<br/>Jails: sshd, vpn-monitoring<br/>Ban Time: 1h - 24h"]
        
        UFW --> Fail2ban
    end

    subgraph AccessControl["🔐 Access Control Layer"]
        SSHKey["🔑 SSH Key-Only Auth<br/>PasswordAuthentication no"]
        PortIsolation["🚧 Port Isolation<br/>22: Admin Only<br/>45678: Admin Only<br/>36991: VPN Clients Only"]
        Fail2banBf["🛑 Fail2ban Brute-Force<br/>MaxRetry: 3-5<br/>FindTime: 10min"]
        
        SSHKey --> PortIsolation --> Fail2banBf
    end

    subgraph SystemIsolation["🔒 System Isolation Layer"]
        direction TB
        SystemdSandbox["⚙️ systemd Sandboxing<br/>vpn-bot.service:<br/>ProtectSystem=full<br/>PrivateTmp=true<br/>NoNewPrivileges=true<br/>ProtectKernelTunables=true"]
        DockerIsolation["🐳 Docker Isolation<br/>Container: amnezia-awg2<br/>Network: 10.8.1.0/24<br/>No host filesystem access"]
        
        SystemdSandbox --> DockerIsolation
    end

    subgraph DataProtection["🔐 Data Protection Layer"]
        EnvSecrets["🔑 /root/.vpn-env<br/>Permissions: chmod 600<br/>Owner: root:root<br/>Secrets via ENV variables"]
        NoPII["❌ No Persistent PII Storage<br/>Logs rotated & cleaned<br/>No user data on disk"]
        EncryptedTunnel["🔐 Encrypted WireGuard Tunnel<br/>AmneziaWG Obfuscation<br/>UDP 36991<br/>Modern Cryptography"]
        
        EnvSecrets --> NoPII --> EncryptedTunnel
    end

    subgraph Monitoring["📊 Monitoring & Alerting"]
        BotSecure["🤖 Secure Bot Communication<br/>Python json.dumps<br/>Input Sanitization<br/>Regex Validation"]
        TGBotAPI["☁️ Telegram Bot API<br/>Token in ENV<br/>HTTPS Only"]
        AdminAlerts["📱 Admin Alerts<br/>Real-time notifications<br/>Ban events<br/>System health"]
        
        BotSecure --> TGBotAPI --> AdminAlerts
    end

    Attacker -->|"Port Scanning<br/>Brute Force"| UFW
    Internet -->|"Legitimate Traffic"| UFW
    UFW --> AccessControl
    AccessControl --> SystemIsolation
    SystemIsolation --> DataProtection
    DataProtection --> Monitoring
    
    style Perimeter fill:#ffebee,stroke:#c62828,stroke-width:3px
    style AccessControl fill:#e3f2fd,stroke:#1565c0,stroke-width:2px
    style SystemIsolation fill:#f3e5f5,stroke:#6a1b9a,stroke-width:2px
    style DataProtection fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px
    style Monitoring fill:#fff3e0,stroke:#ef6c00,stroke-width:2px
    style UFW fill:#f44336,stroke:#b71c1c,color:#fff
    style EnvSecrets fill:#43a047,stroke:#1b5e20,color:#fff
```

### 4. Auto-Recovery & Self-Healing

```mermaid
flowchart TD
    subgraph Admin["👤 Administrator"]
        SSH["🔐 SSH Access<br/>Port 22"]
        TG["📱 Telegram Client<br/>Monitoring"]
    end

    subgraph VPS["🖥️ VPS Host Ubuntu 24.04"]
        direction TB
        
        subgraph DockerLayer["🐳 Docker Layer"]
            AWG["🛡️ amnezia-awg2 Container<br/>VPN: UDP 36991<br/>Subnet: 10.8.1.0/24<br/>Interface: wg0"]
        end
        
        subgraph SystemLayer["⚙️ System Layer"]
            Bot["🤖 vpn-bot.service<br/>Bash Long-Polling<br/>Python JSON Parser<br/>Systemd Hardening:<br/>ProtectSystem=full<br/>NoNewPrivileges=true"]
            
            subgraph Cron["🕒 Cron Jobs"]
                Watchdog["🔄 watchdog.sh<br/>5 min"]
                Metrics["📊 metrics-logger.sh<br/>15 min"]
                AutoReboot["🔄 auto-reboot.sh<br/>Mon/Wed 03:00"]
                PostCheck["✅ post-reboot-check.sh<br/>On boot"]
                Backup["💾 backup-docker.sh<br/>Daily 02:00"]
            end
            
            subgraph WebPanel["🌐 Web Panel"]
                Nginx["🔒 Nginx<br/>TCP 45678 + SSL<br/>Self-signed cert"]
                Flask["🐍 Flask App<br/>localhost:8080<br/>Auth Required"]
                Nginx --> Flask
            end
            
            subgraph Kernel["⚙️ Kernel Tuning"]
                BBR["📡 TCP BBR<br/>Extended Buffers<br/>net.core.rmem_max"]
            end
        end
        
        subgraph Security["🛡️ Security"]
            UFW["🔥 UFW<br/>Default DENY"]
            F2B["🚫 Fail2ban<br/>SSH + VPN Jails"]
        end
        
        DockerLayer --> SystemLayer
        SystemLayer --> Security
    end

    subgraph Clients["📱 VPN Clients"]
        C1["📱 Mobile"]
        C2["💻 Desktop"]
        C3["📱 Tablet"]
    end

    subgraph Recovery["🔄 Auto-Recovery & Self-Healing"]
        WatchdogSvc["🤖 Watchdog Service<br/>Monitor container health"]
        AutoRestart["♻️ Restart=always<br/>Systemd auto-restart"]
        BackupScript["💾 backup-docker.sh<br/>Config backup"]
        HealthCheck["✅ Health Checks<br/>Post-reboot validation"]
        
        WatchdogSvc --> AutoRestart
        BackupScript --> HealthCheck
    end

    subgraph Telegram["☁️ Telegram Cloud"]
        TGAPI["Telegram Bot API<br/>HTTPS"]
    end

    SSH -->|"Encrypted"| UFW
    UFW -->|"Allow"| DockerLayer
    UFW -->|"Allow"| Nginx
    
    C1 & C2 & C3 -->|"WG Tunnel<br/>UDP 36991<br/>Obfuscated"| UFW
    UFW -->|"NAT Forward"| AWG
    
    AWG -->|"wg show<br/>metrics"| Bot
    AWG -->|"Read stats"| Flask
    Bot -->|"System metrics"| Flask
    
    Bot -->|"Python json.dumps<br/>Auto-split >3800 chars"| TGAPI
    TGAPI -->|"Push Alerts<br/>Real-time"| TG
    
    Watchdog & Metrics & AutoReboot & PostCheck & Backup --> Bot
    Bot --> Recovery
    Flask --> Recovery
    
    style Admin fill:#e3f2fd,stroke:#1976d2
    style VPS fill:#f3e5f5,stroke:#7b1fa2
    style Clients fill:#e8f5e9,stroke:#388e3c
    style Recovery fill:#fff3e0,stroke:#f57c00
    style Telegram fill:#e0f7fa,stroke:#00838f
    style AWG fill:#9c27b0,stroke:#4a148c,color:#fff
    style Bot fill:#d32f2f,stroke:#b71c1c,color:#fff
    style UFW fill:#f44336,stroke:#b71c1c,color:#fff
```

## 🛠️ Шпаргалка админа

```bash
# === МОНИТОРИНГ И СТАТУС ===
# Проверка здоровья всей системы
./install.sh --check

# Статус сервисов
systemctl status vpn-bot.service
docker ps --filter name=amnezia-awg2

# === БЕЗОПАСНОСТЬ ===
# Просмотр забаненных IP
sudo fail2ban-client status vpn-monitoring
sudo fail2ban-client set vpn-monitoring unbanip <IP_АДРЕС>

# Проверка синхронизации времени (должно быть synchronized: yes)
timedatectl status | grep synchronized

# Проверка лимитов логов Docker
cat /etc/docker/daemon.json

# === ОБСЛУЖИВАНИЕ ===
# Ручной бэкап конфигураций
/root/scripts/backup-docker.sh

# Очистка дискового пространства и старых образов
/root/scripts/cleanup-orphans.sh
```
