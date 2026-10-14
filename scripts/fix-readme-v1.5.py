#!/usr/bin/env python3
"""fix-readme-v1.5.py - финальные правки README:
  1. Добавить recidive-jail + unattended-upgrades в раздел "Безопасность"
  2. Переделать схему 3 в компактную "змейку" (flowchart LR)
  3. Дополнить шпаргалку админа блоками recidive + unattended
"""
import pathlib

p = pathlib.Path("/opt/vpn-amnezia-infrastructure/README.md")
text = p.read_text(encoding="utf-8")
changed = False

# === 1. Раздел "Безопасность и Харденинг" — добавить 2 пункта ===
old_tail = """- **Hardening Nginx**: Веб-сервер скрыл свою версию (`server_tokens off`) и ограничил максимальный размер запроса (`1M`) для защиты от DoS-атак на панель."""

new_tail = """- **Fail2ban с recidive-jail**: помимо базовых jail'ов (`sshd`, `vpn-monitoring`) работает `recidive` — рецидивисты получают бан на **7 дней** при 3+ повторных попытках за 24 часа. Читает `/var/log/fail2ban.log` через `backend = polling`, блокирует на уровне iptables (цепочка `f2b-recidive` в `INPUT`).
- **Автообновления безопасности**: `unattended-upgrades` устанавливает security-патчи Ubuntu ежедневно (обычно в 06:00). В связке с плановым ребутом (Пн/Ср 03:00) это гарантирует применение свежего ядра без ручного вмешательства.
- **Hardening Nginx**: Веб-сервер скрыл свою версию (`server_tokens off`) и ограничил максимальный размер запроса (`1M`) для защиты от DoS-атак на панель."""

if old_tail in text and "recidive-jail" not in text:
    text = text.replace(old_tail, new_tail)
    print("[OK] Безопасность: добавлены recidive + unattended-upgrades")
    changed = True
elif "recidive-jail" in text:
    print("[SKIP] Безопасность: уже дополнено")
else:
    print("[WARN] Раздел 'Hardening Nginx' не найден")

# === 2. Схема 3 — переделать в "змейку" (LR-направление) ===
old_schema3_start = '```mermaid\nflowchart TB\n    subgraph External["⚠️ External Threats"]'
new_schema3 = '''```mermaid
flowchart LR
    subgraph External["⚠️ External"]
        direction TB
        Attacker["👤 Attacker"]
        Internet["☁️ Internet"]
    end

    subgraph L1["1️⃣ Perimeter"]
        direction TB
        UFW["🔥 UFW<br/>DENY ALL<br/>22, 45678, 36991"]
        Fail2ban["🚫 Fail2ban<br/>sshd, vpn-monitoring<br/>recidive (7d)"]
    end

    subgraph L2["2️⃣ Access Control"]
        direction TB
        SSHKey["🔑 SSH Key-Only<br/>PasswordAuth no"]
        PortIso["🚧 Port Isolation<br/>22/45678/36991"]
        F2BBrute["🛑 Brute-Force<br/>MaxRetry 3-5"]
    end

    subgraph L3["3️⃣ System Isolation"]
        direction TB
        SysdSandbox["⚙️ systemd Sandbox<br/>ProtectSystem=full<br/>NoNewPrivileges=true<br/>PrivateTmp=true"]
        DockIso["🐳 Docker Isolation<br/>amnezia-awg2<br/>10.8.1.0/24"]
    end

    subgraph L4["4️⃣ Data Protection"]
        direction TB
        Secrets["🔑 /root/.vpn-env<br/>chmod 600<br/>root:root"]
        NoPeer["❌ No Persistent<br/>Peer Data<br/>Only runtime metrics"]
        Tunnel["🔐 Encrypted<br/>WireGuard Tunnel<br/>UDP 36991"]
    end

    subgraph L5["5️⃣ Monitoring"]
        direction TB
        BotSec["🤖 Secure Bot<br/>JSON sanitize"]
        TGAPI["☁️ Telegram API<br/>HTTPS + ENV token"]
        Alerts["📱 Admin Alerts<br/>Real-time"]
    end

    Attacker -->|"Scan / Brute"| UFW
    Internet -->|"Legit"| UFW
    UFW --> Fail2ban
    Fail2ban --> SSHKey
    SSHKey --> PortIso
    PortIso --> F2BBrute
    F2BBrute --> SysdSandbox
    SysdSandbox --> DockIso
    DockIso --> Secrets
    Secrets --> NoPeer
    NoPeer --> Tunnel
    Tunnel --> BotSec
    BotSec --> TGAPI
    TGAPI --> Alerts

    style External fill:#ffebee,stroke:#c62828,stroke-width:2px
    style L1 fill:#ffebee,stroke:#c62828,stroke-width:2px
    style L2 fill:#e3f2fd,stroke:#1565c0,stroke-width:2px
    style L3 fill:#f3e5f5,stroke:#6a1b9a,stroke-width:2px
    style L4 fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px
    style L5 fill:#fff3e0,stroke:#ef6c00,stroke-width:2px
    style UFW fill:#f44336,stroke:#b71c1c,color:#fff
    style Secrets fill:#43a047,stroke:#1b5e20,color:#fff
```'''

# Найдём старую схему 3 целиком (от flowchart TB до закрывающего ```)
import re
pattern = re.compile(
    r'```mermaid\nflowchart TB\n    subgraph External\["⚠️ External Threats"\].*?\n```',
    re.DOTALL,
)
match = pattern.search(text)

if match and "1️⃣ Perimeter" not in text:
    text = text[:match.start()] + new_schema3 + text[match.end():]
    print("[OK] Схема 3 переделана в компактную змейку (LR)")
    changed = True
elif "1️⃣ Perimeter" in text:
    print("[SKIP] Схема 3 уже переделана")
else:
    print("[WARN] Схема 3 не найдена по паттерну")

# === 3. Шпаргалка — добавить блоки recidive + unattended ===
old_audit = """# Аудит скриптов на ошибки
shellcheck /root/scripts/*.sh /opt/vpn-amnezia-infrastructure/install.sh"""

new_audit = """# Аудит скриптов на ошибки
shellcheck /root/scripts/*.sh /opt/vpn-amnezia-infrastructure/install.sh

# === RECIDIVE (долгие баны) ===
# Статус: кого поймал
sudo fail2ban-client status recidive
# Реальные правила блокировки в ядре
sudo iptables -L f2b-recidive -n -v
# Разбанить вручную (если IP ложный)
sudo fail2ban-client set recidive unbanip <IP>

# === АВТООБНОВЛЕНИЯ БЕЗОПАСНОСТИ ===
# Лог: что установилось
sudo tail -20 /var/log/unattended-upgrades/unattended-upgrades.log
# Dry-run: что БУДЕТ установлено в след. раз
sudo unattended-upgrade --dry-run"""

if old_audit in text and "RECIDIVE (долгие баны)" not in text:
    text = text.replace(old_audit, new_audit)
    print("[OK] Шпаргалка: добавлены блоки recidive + unattended")
    changed = True
elif "RECIDIVE (долгие баны)" in text:
    print("[SKIP] Шпаргалка: уже дополнена")
else:
    print("[WARN] Блок 'Аудит скриптов' не найден")

if changed:
    p.write_text(text, encoding="utf-8")
    print("[DONE] README.md обновлён")
else:
    print("[DONE] изменений не требуется")
