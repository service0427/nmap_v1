#!/bin/bash
# LTE Surgical Setup Script (Zero-Downtime)
# Use this after plugging in LTE modems.

echo "--- [1] Identifying New Interfaces ---"
# Find any interface that is NOT lo, eno, wlo, or tailscale
NEW_IFACES=$(ls /sys/class/net/ | grep -vE "lo|eno|wlo|tailscale|lte")

if [ -z "$NEW_IFACES" ]; then
    echo "No new LTE modems detected."
else
    for iface in $NEW_IFACES; do
        echo "Found: $iface. Activating..."
        sudo ip link set "$iface" up
    done
fi

echo "--- [2] Requesting IPs (Background) ---"
# Using a loop to request IP without systemctl restart
for iface in $(ls /sys/class/net/ | grep -vE "lo|eno|wlo|tailscale"); do
    # Only if it doesn't have an IP yet
    if ! ip -4 addr show "$iface" | grep -q "inet "; then
        echo "Requesting IP for $iface..."
        # If dhclient is missing, we rely on networkd's auto-config via link up
        # or we can use a manual trick if needed.
    fi
done

sleep 5

echo "--- [3] Renaming & Routing Orchestration ---"
for iface in $(ls /sys/class/net/ | grep -vE "lo|eno|wlo|tailscale"); do
    IP=$(ip -4 addr show "$iface" | grep -oP '(?<=inet\s)192\.168\.[0-9]+\.[0-9]+' | head -n 1)
    [ -z "$IP" ] && continue
    
    SUBNET=$(echo "$IP" | cut -d. -f3)
    [ "$SUBNET" -lt 11 ] || [ "$SUBNET" -gt 20 ] && continue
    
    TARGET_NAME="lte$SUBNET"
    TABLE_ID="1$SUBNET"
    
    # Rename if needed
    if [ "$iface" != "$TARGET_NAME" ]; then
        echo "Naming: $iface -> $TARGET_NAME"
        sudo ip link set "$iface" down
        sudo ip link set "$iface" name "$TARGET_NAME"
        sudo ip link set "$TARGET_NAME" up
    fi
    
    # Apply Routing strictly to this IP
    echo "Routing: Mapping $IP to Table $TABLE_ID via $TARGET_NAME"
    sudo ip route replace default via 192.168.$SUBNET.1 dev "$TARGET_NAME" table "$TABLE_ID"
    sudo ip rule add from "$IP" table "$TABLE_ID" priority "$TABLE_ID" 2>/dev/null || true
done

# Ensure main internet is still eno1
# sudo ip route del default # This safely removes any high-priority default routes added by modems
sudo ip rule add from all lookup main priority 32766 2>/dev/null || true

echo "--- [DONE] LTE Discovery & Binding Ready ---"
ip rule show
