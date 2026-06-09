#!/usr/bin/env bash

# ============================================================
# Sound/Ringer Initialization Module
# ============================================================

init_sound() {
    local serial=$1
    local has_su=$2
    local YELLOW="\e[1;33m"
    local GREEN="\e[1;32m"
    local NC="\e[0m"

    echo -e "\n[*] Checking Sound/Ringer status..."
    local ringer_mode=$(adb -s "$serial" shell "dumpsys audio" 2>/dev/null | grep "mode (internal)" | awk -F'= ' '{print $2}' | tr -d '\r ')
    
    # Fallback checking if dumpsys output is empty
    if [ -z "$ringer_mode" ]; then
        local global_ringer=$(adb -s "$serial" shell "settings get global mode_ringer" 2>/dev/null | tr -d '\r')
        if [ "$global_ringer" = "0" ]; then
            ringer_mode="SILENT"
        fi
    fi

    local all_sound_off_val=$(adb -s "$serial" shell "settings get system all_sound_off" 2>/dev/null | tr -d '\r')
    local music_vol=$(adb -s "$serial" shell "dumpsys audio" 2>/dev/null | grep -A 5 "STREAM_MUSIC" | grep "streamVolume:" | awk -F':' '{print $2}' | tr -d '\r ')

    # Defaults if empty
    all_sound_off_val=${all_sound_off_val:-0}
    music_vol=${music_vol:-0}

    local needs_sound_mute=false
    if [ "$ringer_mode" != "SILENT" ] || [ "$all_sound_off_val" != "1" ] || [ "$music_vol" != "0" ]; then
        needs_sound_mute=true
    fi

    if [ "$needs_sound_mute" = true ]; then
        echo -e "    - Current status: Ringer=$ringer_mode, AllSoundsOff=$all_sound_off_val, MediaVolume=$music_vol"
        echo -e "    - Silencing device and muting all audio streams..."
        
        local su_cmd="su"
        if [ -n "$has_su" ]; then
            su_cmd="$has_su"
        fi
        adb -s "$serial" shell "$su_cmd -c 'cmd notification allow_dnd com.android.shell'" >/dev/null 2>&1 || true
        adb -s "$serial" shell "$su_cmd -c 'cmd notification set_dnd none'" >/dev/null 2>&1 || true
        adb -s "$serial" shell "settings put system all_sound_off 1"
        adb -s "$serial" shell "settings put system mode_ringer 0"
        adb -s "$serial" shell "settings put global mode_ringer 0"
        # Additional database volume overrides
        adb -s "$serial" shell "settings put system volume_ring 0" >/dev/null 2>&1
        adb -s "$serial" shell "settings put system volume_system 0" >/dev/null 2>&1
        adb -s "$serial" shell "settings put system volume_notification 0" >/dev/null 2>&1
        adb -s "$serial" shell "settings put system volume_music 0" >/dev/null 2>&1
        
        # Mute all streams (0 to 15) using cmd media_session
        for i in {0..15}; do
            adb -s "$serial" shell "cmd media_session volume --stream $i --set 0" >/dev/null 2>&1
        done

        # Verify
        local ringer_verify=$(adb -s "$serial" shell "dumpsys audio" 2>/dev/null | grep "mode (internal)" | awk -F'= ' '{print $2}' | tr -d '\r ')
        local music_verify=$(adb -s "$serial" shell "dumpsys audio" 2>/dev/null | grep -A 5 "STREAM_MUSIC" | grep "streamVolume:" | awk -F':' '{print $2}' | tr -d '\r ')
        music_verify=${music_verify:-0}
        
        if [ "$ringer_verify" = "SILENT" ] && [ "$music_verify" = "0" ]; then
            echo -e "    [✓] Sound configuration applied (All streams muted)."
        else
            echo -e "    [!] Check silent mode state (Ringer: ${ringer_verify:-UNKNOWN}, MediaVolume: $music_verify)."
        fi
    else
        echo -e "    [✓] Sound is already fully muted (Silent/All sounds off). Skipping."
    fi
}
