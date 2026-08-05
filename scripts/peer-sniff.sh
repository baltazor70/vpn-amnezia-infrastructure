#!/bin/bash

if [ -z "$1" ]; then
    echo "Использование: $0 <IP-адрес пира>"
    exit 1
fi

PEER_IP="$1"
CONTAINER="amnezia-awg2"

echo "=== Захват трафика для $PEER_IP (60 секунд) ==="
echo "Нажми Ctrl+C для остановки"
echo ""

# Захват трафика внутри контейнера на интерфейсе awg0
timeout 60 docker exec $CONTAINER tcpdump -i awg0 host $PEER_IP -A -s 0 2>/dev/null || true

echo ""
echo "=== Захват завершён ==="
