#!/usr/bin/env python3
"""fix-readme-v1.3.py - финальные правки README:
  1. PII -> Peer Data в Mermaid-схеме 3 (DataProtection)
  2. shellcheck в шпаргалку админа
"""
import pathlib

p = pathlib.Path("/opt/vpn-amnezia-infrastructure/README.md")
text = p.read_text(encoding="utf-8")
changed = False

# --- 1. PII -> Peer Data в Mermaid-схеме 3 ---
old_pii = 'NoPII["\u274C No Persistent PII Storage<br/>Logs rotated & cleaned<br/>No user data on disk"]'
new_pii = 'NoPII["\u274C No Persistent Peer Data<br/>Logs rotated & cleaned<br/>Only runtime metrics kept"]'

if old_pii in text:
    text = text.replace(old_pii, new_pii)
    print("[OK] PII -> Peer Data: заменено в схеме 3")
    changed = True
elif "No Persistent Peer Data" in text:
    print("[SKIP] PII -> Peer Data: уже заменено ранее")
else:
    print("[WARN] PII-строка не найдена, проверь вручную:")
    print("       grep 'No Persistent' README.md")

# --- 2. shellcheck в шпаргалку ---
if "shellcheck /root/scripts" not in text:
    old_block = """# Очистка дискового пространства и старых образов
/root/scripts/cleanup-orphans.sh"""
    new_block = """# Очистка дискового пространства и старых образов
/root/scripts/cleanup-orphans.sh

# Аудит скриптов на ошибки
shellcheck /root/scripts/*.sh /opt/vpn-amnezia-infrastructure/install.sh"""
    if old_block in text:
        text = text.replace(old_block, new_block)
        print("[OK] shellcheck: добавлен в шпаргалку")
        changed = True
    else:
        print("[WARN] блок cleanup-orphans не найден, проверь вручную")
else:
    print("[SKIP] shellcheck: уже есть в README")

if changed:
    p.write_text(text, encoding="utf-8")
    print("[DONE] README.md обновлён")
else:
    print("[DONE] изменений не требуется")
