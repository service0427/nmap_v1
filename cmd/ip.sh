#!/usr/bin/env bash

echo "Toggling Airplane Mode to update IP..."

# Get all connected devices
devices=$(adb devices | grep -v "List of devices attached" | grep -w "device" | awk '{print $1}')

if [ -z "$devices" ]; then
    echo "No devices connected."
    exit 0
fi

for serial in $devices; do
    echo "[$serial] Turning Airplane Mode ON..."
    # Find su path
    has_su=$(adb -s "$serial" shell "which su" 2>/dev/null | tr -d '\r')
    if [ -z "$has_su" ]; then
        has_su=$(adb -s "$serial" shell "ls /system/bin/su /system/xbin/su /sbin/su 2>/dev/null" | head -1 | tr -d '\r')
    fi
    [ -z "$has_su" ] && has_su="su"
    # Enable Airplane Mode via root cmd connectivity
    adb -s "$serial" shell "$has_su -c 'cmd connectivity airplane-mode enable'"
done

echo "Waiting 3 seconds to ensure connection drops..."
sleep 3

for serial in $devices; do
    echo "[$serial] Turning Airplane Mode OFF..."
    # Find su path
    has_su=$(adb -s "$serial" shell "which su" 2>/dev/null | tr -d '\r')
    if [ -z "$has_su" ]; then
        has_su=$(adb -s "$serial" shell "ls /system/bin/su /system/xbin/su /sbin/su 2>/dev/null" | head -1 | tr -d '\r')
    fi
    [ -z "$has_su" ] && has_su="su"
    # Disable Airplane Mode via root cmd connectivity
    adb -s "$serial" shell "$has_su -c 'cmd connectivity airplane-mode disable'"
done

echo "IP toggle complete."
