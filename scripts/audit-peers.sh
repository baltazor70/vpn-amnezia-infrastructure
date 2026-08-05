#!/bin/bash
printf "%-15s | %-30s | %-33s | %-25s | %-30s\n" "IP Адрес" "Публичный ключ" "Имя пользователя" "Последний Handshake" "Трафик"
printf "%-15s | %-30s | %-33s | %-25s | %-30s\n" "----------------" "-------------------------------" "-----------------------------------" "---------------------------" "------------------------------"

docker exec amnezia-awg2 wg show | awk '
/peer:/ { peer=$2 }
/allowed ips:/ { ip=$3; sub(/\/32/,"",ip) }
/latest handshake:/ { handshake=$0; sub(/.*latest handshake: /,"",handshake) }
/transfer:/ { transfer=$0; sub(/.*transfer: /,"",transfer) }
/^$/ {
    if (peer && ip) {
        printf "%s|%s|%s|%s\n", ip, peer, handshake, transfer
    }
    peer=""; ip=""; handshake=""; transfer=""
}
END {
    if (peer && ip) printf "%s|%s|%s|%s\n", ip, peer, handshake, transfer
}
' | sort -t. -k4 -n | while IFS='|' read ip key handshake traffic; do
    # Ищем имя ТОЛЬКО по allowedIps, игнорируя allowed_ips
    name=$(docker exec amnezia-awg2 cat /opt/amnezia/awg/clientsTable 2>/dev/null | \
        awk -v ip="$ip" '
        /"allowedIps": "/ { if ($0 ~ "\"" ip "/32\"") { found=1 } }
        found && /"clientName":/ { print $0; found=0 }
        ' | head -1 | awk -F'"' '{print $4}')
    [ -z "$name" ] && name="Unknown"
    [ -z "$handshake" ] && handshake="N/A"
    [ -z "$traffic" ] && traffic="N/A"
    short_key="${key:0:29}..."
    printf "%-15s | %-30s | %-33s | %-25s | %-30s\n" "$ip" "$short_key" "$name" "$handshake" "$traffic"
done
