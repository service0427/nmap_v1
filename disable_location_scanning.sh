#!/usr/bin/env bash

# Get connected devices
DEVICES=$(adb devices | grep -w "device" | awk '{print $1}')

if [ -z "$DEVICES" ]; then
    echo "No devices connected."
    exit 1
fi

for serial in $DEVICES; do
    echo "--------------------------------------------------"
    echo "Processing device: $serial"
    
    # Check for root
    HAS_SU=$(adb -s "$serial" shell "which su" 2>/dev/null | tr -d '\r')
    
    # 1. Disable Wi-Fi Scanning (Wi-Fi 찾기)
    echo "[*] Disabling Wi-Fi Scanning..."
    adb -s "$serial" shell "settings put global wifi_scan_always_enabled 0"
    
    # 2. Disable Bluetooth Scanning (블루투스 찾기)
    echo "[*] Disabling Bluetooth Scanning..."
    adb -s "$serial" shell "settings put global ble_scan_always_enabled 0"
    
    # 3. Disable Nearby Scanning (주변 기기 찾기)
    echo "[*] Disabling Nearby Scanning..."
    adb -s "$serial" shell "settings put system nearby_scanning_enabled 0" 2>/dev/null
    
    # Verify results
    WIFI_SCAN=$(adb -s "$serial" shell "settings get global wifi_scan_always_enabled" | tr -d '\r')
    BLE_SCAN=$(adb -s "$serial" shell "settings get global ble_scan_always_enabled" | tr -d '\r')
    NEARBY_SCAN=$(adb -s "$serial" shell "settings get system nearby_scanning_enabled" | tr -d '\r')
    
    echo "[$serial] Result:"
    echo "    - Wi-Fi Scanning: $([ "$WIFI_SCAN" == "0" ] && echo 'OFF (0)' || echo 'ON (1)')"
    echo "    - Bluetooth Scanning: $([ "$BLE_SCAN" == "0" ] && echo 'OFF (0)' || echo 'ON (1)')"
    echo "    - Nearby Scanning: $([ "$NEARBY_SCAN" == "0" ] && echo 'OFF (0)' || echo 'ON (1)')"
done

echo "--------------------------------------------------"
echo "Done."
