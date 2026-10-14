#!/usr/bin/env python3
"""fix-readme-v1.4.py - убрать упоминание VSCode Remote (личный инструмент разработки)
"""
import pathlib

p = pathlib.Path("/opt/vpn-amnezia-infrastructure/README.md")
text = p.read_text(encoding="utf-8")

# Удаляем строку про VSCode Remote в списке внутренних портов
target = "- `45419/tcp` - VSCode Remote\n"

if target in text:
    text = text.replace(target, "")
    p.write_text(text, encoding="utf-8")
    print("[OK] строка про VSCode Remote удалена")
elif "45419" in text or "VSCode" in text:
    print("[WARN] '45419' или 'VSCode' ещё встречается в README, но точная строка не найдена:")
    for i, line in enumerate(text.splitlines(), 1):
        if "45419" in line or "VSCode" in line:
            print(f"  строка {i}: {line!r}")
    print("  → проверь вручную, какой формат строки используется")
else:
    print("[SKIP] упоминаний VSCode Remote не найдено — уже убрано")
