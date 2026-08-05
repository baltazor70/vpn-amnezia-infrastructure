#!/bin/bash
# /root/scripts/check-client.sh

CLIENT_IP="10.8.1.27"

echo "🔍 Проверка клиента $CLIENT_IP"
echo "════════════════════════════════"

# 1. Статус в WireGuard
echo "📡 WireGuard peer:"
docker exec amnezia-awg2 wg show | grep -A 5 "$CLIENT_IP" || echo "❌ Не найден"

# 2. Трафик
echo -e "\n📊 Трафик:"
docker exec amnezia-awg2 wg show | grep -A 10 "peer:" | grep -B 10 "$CLIENT_IP" | grep "transfer"

# 3. Пинг до Discord
echo -e "\n🌐 Discord доступность:"
ping -c 2 -W 2 discord.com && echo "✅ OK" || echo "❌ Не доступен"

# 4. Порты
echo -e "\n🔌 Порты Discord:"
nc -zvw1 discord.com 443 && echo "✅ TCP 443 OK" || echo "❌ TCP 443 FAIL"
nc -zvw1 -u discord.com 50000 && echo "✅ UDP 50000 OK" || echo "❌ UDP 50000 FAIL"

echo "════════════════════════════════"
