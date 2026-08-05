#!/bin/bash
LOG_DIR="/var/log/vpn-metrics"
mkdir -p "$LOG_DIR"

# CPU
CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)

# RAM
RAM_USED=$(free -m | awk '/Mem:/{print $3}')
RAM_TOTAL=$(free -m | awk '/Mem:/{print $2}')
RAM_PERCENT=$((RAM_USED * 100 / RAM_TOTAL))

# Disk
DISK=$(df -h / | awk 'NR==2{print $5}' | tr -d '%')

# Traffic
CONTAINER="amnezia-awg2"
TRAFFIC=$(docker exec $CONTAINER wg show | grep "transfer:" | head -1 | awk '{print $2, $3, $5, $6}')
RX=$(echo $TRAFFIC | awk '{print $1}')
RX_UNIT=$(echo $TRAFFIC | awk '{print $2}')
TX=$(echo $TRAFFIC | awk '{print $3}')
TX_UNIT=$(echo $TRAFFIC | awk '{print $4}')

# Сохраняем
echo "$(date +%H:%M) ${CPU}% ${RAM_PERCENT}% ${DISK}% ${RX} ${RX_UNIT} ${TX} ${TX_UNIT}" >> "$LOG_DIR/cpu.log"
echo "$(date +%H:%M) ${CPU}% ${RAM_PERCENT}% ${DISK}% ${RX} ${RX_UNIT} ${TX} ${TX_UNIT}" >> "$LOG_DIR/ram.log"
echo "$(date +%H:%M) ${CPU}% ${RAM_PERCENT}% ${DISK}% ${RX} ${RX_UNIT} ${TX} ${TX_UNIT}" >> "$LOG_DIR/disk.log"
echo "$(date +%H:%M) ${CPU}% ${RAM_PERCENT}% ${DISK}% ${RX} ${RX_UNIT} ${TX} ${TX_UNIT}" >> "$LOG_DIR/traffic.log"

# Оставляем только последние 96 записей (24 часа / 15 минут = 96)
for log in cpu.log ram.log disk.log traffic.log; do
    tail -96 "$LOG_DIR/$log" > /tmp/metrics-tmp && mv /tmp/metrics-tmp "$LOG_DIR/$log"
done
