#!/usr/bin/env python3
"""Добавляет раздел 'Команды Telegram-бота' в README."""
import pathlib

p = pathlib.Path("/opt/vpn-amnezia-infrastructure/README.md")
text = p.read_text(encoding="utf-8")

if "## \U0001F916 Команды Telegram-бота" in text:
    print("[SKIP] раздел уже есть")
    raise SystemExit(0)

commands_section = """## \U0001F916 Команды Telegram-бота

Все команды доступны **только администратору** (проверка `CHAT_ID` из `/root/.vpn-env`).

### \U0001F4CA Мониторинг
- `/status` — статус VPN (клиенты, трафик, контейнер, ресурсы)
- `/stat` — алиас `/status`
- `/server_status` — CPU, RAM, диск, аптайм хоста
- `/top` — топ-10 клиентов по трафику
- `/health` — health-check системы

### \U0001F465 Клиенты
- `/users` — краткий список (IP + имя)
- `/clients` — детальный список (статус, Rx/Tx, last handshake)
- `/userstatus <N>` — статус клиента по последнему октету IP

### \U0001F527 Управление (с двухэтапным подтверждением)
- `/restart_container` — перезапуск VPN-контейнера
- `/reboot_server` — перезагрузка сервера

### \U0001F6E0 Обслуживание
- `/cleanup` — очистка (`cleanup-server.sh`), показывает использование диска до/после

### \u2139\uFE0F Информация
- `/start` — приветствие
- `/help` — список команд
- `/ping` — проверка отклика бота
- `/logs` — последние записи лога

"""

anchor = "## \U0001F6E0\uFE0F Шпаргалка админа"
if anchor in text:
    text = text.replace(anchor, commands_section + anchor)
    p.write_text(text, encoding="utf-8")
    print("[OK] раздел 'Команды Telegram-бота' добавлен")
else:
    print("[WARN] не найден анкер '## Шпаргалка админа'")
