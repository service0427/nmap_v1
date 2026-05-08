#!/usr/bin/env bash

echo "Disabling MTP Popups on all devices..."

devices=$(adb devices | grep -v "List of devices attached" | grep -w "device" | awk '{print $1}')

if [ -z "$devices" ]; then
    echo "No devices connected."
    exit 0
fi

for serial in $devices; do
    echo "[$serial] Forcing Persistent USB: ADB Only (No MTP)..."
    # 1. Set Persistent & Current USB configuration to 'adb' only (Disables MTP at descriptor level)
    # Using su -c to ensure we have permission to set persist properties
    adb -s "$serial" shell "su -c 'setprop persist.sys.usb.config adb && setprop sys.usb.config adb'" 2>/dev/null
    
    # 2. Double check with svc usb (Samsung specific often helps)
    adb -s "$serial" shell "su -c 'svc usb setFunctions adb'" 2>/dev/null
    
    # 3. Disable MTP system packages (Triple layer protection)
    adb -s "$serial" shell pm disable-user --user 0 com.samsung.android.mtp >/dev/null 2>&1 || true
    adb -s "$serial" shell pm disable-user --user 0 com.samsung.android.mtpapplication >/dev/null 2>&1 || true
    adb -s "$serial" shell pm disable-user --user 0 com.android.mtp >/dev/null 2>&1 || true
done

echo "Done."
