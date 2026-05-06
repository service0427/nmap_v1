#!/usr/bin/env bash

echo "Applying stealth/dark mode to all connected devices..."

# Get all connected devices
devices=$(adb devices | grep -v "List of devices attached" | grep -w "device" | awk '{print $1}')

if [ -z "$devices" ]; then
    echo "No devices connected."
    exit 0
fi

for serial in $devices; do
    echo "[$serial] Applying dark mode (Brightness 0, Mute, Zen Mode)..."
    
    # 1. Disable auto-brightness and set to 0
    adb -s "$serial" shell settings put system screen_brightness_mode 0
    adb -s "$serial" shell settings put system screen_brightness 0
    
    # 2. Mute all volume streams: 1=System, 2=Ring, 3=Music, 4=Alarm, 5=Notification
    for stream in 1 2 3 4 5; do
        adb -s "$serial" shell cmd media_session volume --stream $stream --set 0 >/dev/null 2>&1 || true
    done
    
    # 4. 애니메이션 배율 0 (GPU 부하 감소)
    adb -s "$serial" shell settings put global window_animation_scale 0
    adb -s "$serial" shell settings put global transition_animation_scale 0
    adb -s "$serial" shell settings put global animator_duration_scale 0

    # 3. Enable Do Not Disturb (Zen Mode)
    adb -s "$serial" shell settings put global zen_mode 1 >/dev/null 2>&1 || true
done

echo "Done. All devices are now stealthy."
