# 🛡️ VPN AmneziaWG Infrastructure

> Лёгкая, надёжная и полностью автоматизированная инфраструктура для личного WireGuard-VPN на базе AmneziaWG с управлением через Telegram.

![Status](https://img.shields.io/badge/status-stable-green)
![License](https://img.shields.io/badge/license-MIT-blue)

---

## 🎯 Возможности

### 🤖 Управление через Telegram
- `/stat` — статистика VPN
- `/clients` — список клиентов
- `/traffic` — трафик по клиентам
- `/server_status` — CPU, RAM, диск
- `/restart_container` — перезапуск VPN
- `/cleanup` — очистка диска
- `/backup` — бэкап

### 🔔 Автоматические уведомления
- 🟢 Новые подключения
- 🔴 Отключения клиентов
- ⚠️ Превышение порогов ресурсов
- 🔄 Уведомления о перезагрузке

### 🛡️ Безопасность
- ✅ Fail2ban защита SSH
- ✅ Автоматические обновления
- ✅ Шифрованные бэкапы
- ✅ Секреты через .env файлы

---

## 🚀 Установка

```bash
# 1. Клонируй репозиторий
git clone https://github.com/baltazor70/vpn-amnezia-infrastructure.git
cd vpn-amnezia-infrastructure

# 2. Настрой переменные
cp examples/.vpn-env.example /root/.vpn-env
nano /root/.vpn-env

# 3. Запусти установку
chmod +x install.sh
./install.sh
