# 🛡️ VPN AmneziaWG Infrastructure

> Лёгкая, надёжная и полностью автоматизированная инфраструктура для личного WireGuard-VPN на базе **AmneziaWG** с управлением через **Telegram-бота**.

![Status](https://img.shields.io/badge/status-stable-green)
![License](https://img.shields.io/badge/license-MIT-blue)
![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04-orange)
![Docker](https://img.shields.io/badge/Docker-ready-blue)

---

## 📖 Описание

Этот проект — готовое решение для развёртывания личного VPN-сервера с полной автоматизацией. Все компоненты написаны на Bash, используют Docker и управляются через Telegram-бота.

**Идеально подходит для:**
- 👨‍👩‍👧‍👦 Личного использования (семья, друзья)
- 🏢 Малых команд (до 25-30 клиентов)
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
| **Локация** | Европа (Нидерланды) | Низкий пинг до РФ (~44ms) |

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

```mermaid
graph TB
    subgraph Clients["📱 Клиенты (19)"]
        iOS["iPhone (17)"]
        Android["Android (2)"]
    end
    
    subgraph Server["🇳🇱 Сервер (VPS)"]
        Docker["🐳 Docker: AmneziaWG"]
        Bot["🤖 Telegram Bot"]
        Fail2Ban["🛡️ Fail2ban"]
        Backup["💾 Авто-бэкапы"]
    end
    
    Clients -->|AmneziaWG UDP| Docker
    Docker --> Bot
    Docker --> Fail2Ban
    Docker --> Backup
