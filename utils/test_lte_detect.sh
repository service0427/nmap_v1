#!/bin/bash
# LTE Modem Discovery Test - Strict Range Verification
# Target: 192.168.11.100 ~ 192.168.20.200

echo "--------------------------------------------------------"
echo " [LTE Modem Discovery Test]"
echo " Target Range: 192.168.11.100 ~ 192.168.20.200"
echo "--------------------------------------------------------"

FOUND_COUNT=0

# Loop through all network interfaces except loopback
for iface in $(ls /sys/class/net/ | grep -v "lo"); do
    # Extract IPv4 addresses
    IPS=$(ip -4 addr show "$iface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    
    for IP in $IPS; do
        # Robust Regex for the specific range
        # Subnet: 11-19 (1[1-9]) or 20
        # Host: 100-199 (1[0-9][0-9]) or 200
        if [[ $IP =~ ^192\.168\.(1[1-9]|20)\.(1[0-9][0-9]|200)$ ]]; then
            SUBNET=$(echo "$IP" | cut -d. -f3)
            D_CLASS=$(echo "$IP" | cut -d. -f4)
            GW="192.168.$SUBNET.1"
            
            echo "[MATCH] Interface: $iface"
            echo "        IP Address: $IP"
            echo "        Detected Subnet: $SUBNET"
            echo "        Detected D-Class: $D_CLASS"
            echo "        Expected Gateway: $GW"
            echo "--------------------------------------------------------"
            ((FOUND_COUNT++))
        fi
    done
done

if [ $FOUND_COUNT -eq 0 ]; then
    echo " [!] No matching LTE modems found within the strict range."
    echo " Current IPs detected on the system:"
    ip -4 addr show | grep inet | awk '{print "    - " $2}'
else
    echo " [OK] Success: $FOUND_COUNT LTE modem(s) discovered."
fi
