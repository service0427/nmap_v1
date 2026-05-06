#!/usr/bin/env bash

echo "Forcing all devices to Portrait mode and blocking App orientation requests..."

# Get all connected devices
devices=$(adb devices | grep -v "List of devices attached" | grep -w "device" | awk '{print $1}')

if [ -z "$devices" ]; then
    echo "No devices connected."
    exit 0
fi

for serial in $devices; do
    echo "[$serial] Locking orientation to Portrait..."
    
    # 1. Turn off auto-rotation
    adb -s "$serial" shell settings put system accelerometer_rotation 0
    
    # 2. Force system UI rotation to Portrait (0 degrees)
    adb -s "$serial" shell settings put system user_rotation 0
    
    # 3. Ignore App's requested orientation (Forces apps like Naver Map to stay Portrait)
    adb -s "$serial" shell wm set-ignore-orientation-request true >/dev/null 2>&1 || true
    
    # 4. Force Window Manager to strictly follow user-rotation
    adb -s "$serial" shell wm fixed-to-user-rotation enabled >/dev/null 2>&1 || true

done

echo "Done."
