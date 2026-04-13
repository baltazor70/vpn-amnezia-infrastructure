[ -f /root/.vpn-env ] && source /root/.vpn-env
#!/bin/bash
# vpn-traffic.sh — показывает трафик всех клиентов

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  📊 VPN КЛИЕНТЫ — $(TZ=Europe/Moscow date '+%H:%M:%S')                          ║"
echo "╠════════════════════════════════════════════════════════════════╣"
echo "║ IP           │ Трафик (▼ скачано / ▲ отправлено) │ Статус    ║"
echo "╠════════════════════════════════════════════════════════════════╣"

docker exec amnezia-awg2 wg show | awk '
BEGIN { peer=""; ip=""; rx=""; tx=""; hs="" }
/peer:/ { 
    if (ip != "") {
        status = (hs == "" || hs == "(none)") ? "🔴 оффлайн" : "🟢 онлайн"
        if (rx == "") {
            traffic = "▼ 0 B / ▲ 0 B"
        } else {
            traffic = "▼ " rx " " rxu " / ▲ " tx " " txu
        }
        printf "║ %-12s │ %-35s │ %-9s ║\n", ip, traffic, status
    }
    peer = $2; ip = ""; rx = ""; tx = ""; hs = ""
}
/allowed ips:/ { ip = $3 }
/transfer:/ { 
    rx = $2; rxu = $3; tx = $5; txu = $6
}
/latest handshake:/ { hs = $3 " " $4 " " $5 }
END {
    if (ip != "") {
        status = (hs == "" || hs == "(none)") ? "🔴 оффлайн" : "🟢 онлайн"
        if (rx == "") {
            traffic = "▼ 0 B / ▲ 0 B"
        } else {
            traffic = "▼ " rx " " rxu " / ▲ " tx " " txu
        }
        printf "║ %-12s │ %-35s │ %-9s ║\n", ip, traffic, status
    }
}
'

echo "╚════════════════════════════════════════════════════════════════╝"
echo "🟢 = активен | 🔴 = оффлайн (нет handshake)"
