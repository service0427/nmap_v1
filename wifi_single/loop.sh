#!/bin/bash
# wifi_single: Smart Multi-Device Task Orchestrator (V1.0.0 - Single Mode)

# Parse Arguments
SKIP_IP=false; SINGLE_DEV_ID=""
for arg in "$@"; do
    if [ "$arg" == "--no-ip" ]; then SKIP_IP=true; elif [[ "$arg" != --* ]]; then SINGLE_DEV_ID="$arg"; fi
done

# --- [PATH SETUP] ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR" || exit 1

export MODE_WIFI_ROOT="$SCRIPT_DIR"
export MODE_WIFI_LOGS="$SCRIPT_DIR/logs"
export MODE_WIFI_LIB="$SCRIPT_DIR/lib"

PKG_NAME="com.nhn.android.nmap"
export API_SERVER="114.207.112.245:8000"

# --- [CORE] Functions ---
NOW() { date +"%H:%M:%S.%3N"; }
log_info() { echo "[$(NOW)] [*] $1"; }
log_success() { echo "[$(NOW)] [🚀] $1"; }
log_busy() { echo "[$(NOW)] [⏳] $1"; }

echo "============================================================"
echo "   NMAP V2 DYNAMIC TASK ORCHESTRATOR (V2.9.8)"
echo "   Action: Stability & Robust Connectivity"
echo "============================================================"

# 0. Initial Purge
pkill -9 -f "lib/main.sh"
pkill -9 -f "auto_reloader.py"
pkill -9 -f "monitor.sh"
pkill -9 -f "mitmdump"
pkill -9 -f "frida"
sleep 2

# [REFACTORED] LTE Modem Auto-Doctor (Sync with lte_ip_rotator logic)
fix_modems() {
    # 1. Rename and ensure link UP
    for iface in $(ls /sys/class/net/ | grep -vE "lo|eno|wlo|tailscale|lte"); do
        sudo ip link set "$iface" up 2>/dev/null
        local IP=$(ip -4 addr show "$iface" | grep -oP '(?<=inet\s)192\.168\.[0-9]+\.[0-9]+' | head -n 1)
        if [ -n "$IP" ]; then
            local SUB=$(echo "$IP" | cut -d. -f3)
            if [ "$SUB" -ge 11 ] && [ "$SUB" -le 20 ]; then
                log_info "Modem detected on $iface (IP: $IP). Renaming to lte$SUB..."
                sudo ip link set "$iface" down && sudo ip link set "$iface" name "lte$SUB" && sudo ip link set "lte$SUB" up
            fi
        fi
    done

    # 2. Re-apply PBR rules and routes periodically
    for SUB in {11..20}; do
        local IF="lte$SUB"
        if [ -d "/sys/class/net/$IF" ]; then
            local IP=$(ip -4 addr show "$IF" | grep -oP '(?<=inet\s)192\.168\.[0-9]+\.[0-9]+' | head -n 1)
            if [ -n "$IP" ]; then
                sudo ip route replace default via 192.168.$SUB.1 dev "$IF" table "1$SUB" 2>/dev/null
                sudo ip rule add from "$IP" table "1$SUB" priority "1$SUB" 2>/dev/null
            fi
        fi
    done
}

get_devices() {
    if [ -n "$SINGLE_DEV_ID" ]; then echo "$SINGLE_DEV_ID"; else timeout 5 /usr/bin/adb devices | grep -w "device" | awk '{print $1}'; fi
}

force_purge_device() {
    local TARGET_DEV=$1
    log_info "[$TARGET_DEV] Executing comprehensive purge for background workers..."
    
    # 1. Kill main.sh script
    local PIDS=$(pgrep -f "main.sh $TARGET_DEV" | xargs)
    [ -n "$PIDS" ] && kill -9 $PIDS 2>/dev/null
    
    # 2. Kill child workers based on target device signature
    local DEV_SEQ=$(echo "$TARGET_DEV" | cksum | awk '{print $1 % 1000}')
    local EXP_FRIDA=$((6000 + DEV_SEQ))
    local EXP_MITM=$((EXP_FRIDA + 10000))
    
    pkill -9 -f "mitmdump -p $EXP_MITM" 2>/dev/null
    pkill -9 -f "monitor.sh $TARGET_DEV" 2>/dev/null
    pkill -9 -f "auto_reloader.py.*$TARGET_DEV" 2>/dev/null
    pkill -9 -f "frida -H localhost:$EXP_FRIDA" 2>/dev/null
    
    # 3. Terminate android app and GPS service
    timeout 5 /usr/bin/adb -s "$TARGET_DEV" shell am force-stop com.nhn.android.nmap 2>/dev/null
    
    local su_path=$(timeout 5 /usr/bin/adb -s "$TARGET_DEV" shell "which su" 2>/dev/null | tr -d '\r')
    [ -z "$su_path" ] && su_path="su"
    timeout 5 /usr/bin/adb -s "$TARGET_DEV" shell "$su_path -c 'am stopservice com.rosteam.gpsemulator/.servicex2484'" 2>/dev/null
    
    # 4. Reset network & proxy configurations
    timeout 5 /usr/bin/adb -s "$TARGET_DEV" shell settings put global http_proxy :0 2>/dev/null
    timeout 5 /usr/bin/adb -s "$TARGET_DEV" reverse --remove tcp:$EXP_FRIDA 2>/dev/null
    timeout 5 /usr/bin/adb -s "$TARGET_DEV" reverse --remove tcp:$EXP_MITM 2>/dev/null
    timeout 5 /usr/bin/adb -s "$TARGET_DEV" forward --remove tcp:$EXP_FRIDA 2>/dev/null
}

while true; do
    # [AUTO-DOCTOR] Fix modem names and routing every cycle
    fix_modems

    DEVICES=$(get_devices)
    if [ -z "$DEVICES" ]; then
        # Offline Recovery
        OFFLINE_DEVICES=$(/usr/bin/adb devices | grep -w "offline" | awk '{print $1}')
        if [ -n "$OFFLINE_DEVICES" ]; then
            log_info "Offline devices detected: $OFFLINE_DEVICES. Attempting reconnect..."
            for OFF_ID in $OFFLINE_DEVICES; do /usr/bin/adb -s "$OFF_ID" reconnect 2>/dev/null; done
            sleep 2
        fi
        log_info "No active devices detected. Retrying in 10s..."
        sleep 10
        continue
    fi

    echo "------------------------------------------------------------"
    log_info "Scanning devices..."

    for DEV_ID in $DEVICES; do
        DEV_TMP_DIR="${MODE_WIFI_LOGS}/${DEV_ID}/tmp"
        mkdir -p "$DEV_TMP_DIR"

        SCRIPT_PIDS=$(pgrep -f "main.sh $DEV_ID" | xargs)
        CURRENT_TASK_JSON="${MODE_WIFI_LOGS}/${DEV_ID}/current_task.json"
        
        # 1. Global Safety Check
        if [ -f "$CURRENT_TASK_JSON" ]; then
            START_TS=$(jq -r '.start_ts // 0' "$CURRENT_TASK_JSON" 2>/dev/null)
            NOW_TS=$(date +%s)
            AGE=$((NOW_TS - START_TS))
            
            # 15-Min Hard Kill
            if [ "$AGE" -gt 900 ]; then
                log_info "[$DEV_ID] GLOBAL TIMEOUT ($AGE s > 15m). Force Purging..."
                force_purge_device "$DEV_ID"
                rm -f "$CURRENT_TASK_JSON" "${DEV_TMP_DIR}/nmap_lock"
                continue
            fi
        fi

        # 2. Ghost App & Stale Process Detection
        CURRENT_FOCUS=$(timeout 5 /usr/bin/adb -s "$DEV_ID" shell "dumpsys activity activities | grep -E 'mResumedActivity|mCurrentFocus|topResumedActivity' | grep com.nhn.android.nmap" 2>/dev/null)
        if [ -n "$CURRENT_FOCUS" ] && [ -z "$SCRIPT_PIDS" ]; then
            log_info "[$DEV_ID] GHOST APP detected (No script running). Force stopping..."
            timeout 5 /usr/bin/adb -s "$DEV_ID" shell am force-stop com.nhn.android.nmap 2>/dev/null
            continue
        fi

        if [ -n "$SCRIPT_PIDS" ]; then
            LOCK_FILE="${DEV_TMP_DIR}/nmap_lock"
            LOCK_TIME=$(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0)
            AGE=0
            
            if [ "$LOCK_TIME" -gt 0 ]; then
                AGE=$(( $(date +%s) - LOCK_TIME ))
                [ $AGE -lt 60 ] && continue # Wait up to 60s for heartbeat
            else
                START_TS=$(jq -r '.start_ts // 0' "$CURRENT_TASK_JSON" 2>/dev/null || echo 0)
                SESSION_AGE=$(( $(date +%s) - START_TS ))
                [ "$SESSION_AGE" -lt 180 ] && continue # 3-min grace period for initial setup
                AGE="NO_LOCK_$SESSION_AGE"
            fi
            
            log_info "[$DEV_ID] STALE Session (Age: $AGE). Reason: Heartbeat timeout. Purging..."
            force_purge_device "$DEV_ID"
            rm -f "$LOCK_FILE" "$CURRENT_TASK_JSON"
            continue
        fi

        # 3. Battery Safety
        BATT_LEVEL=$(timeout 5 /usr/bin/adb -s "$DEV_ID" shell "dumpsys battery" | grep "level:" | grep -oE '[0-9]+' | head -n 1)
        if [ -n "$BATT_LEVEL" ] && [ "$BATT_LEVEL" -lt 10 ]; then
            log_info "[$DEV_ID] Battery too low (${BATT_LEVEL}%). Skipping..."
            continue
        fi

        # 4. Proxy Clean-up (Prevent loop from broken proxy)
        timeout 5 /usr/bin/adb -s "$DEV_ID" shell "settings put global http_proxy :0" >/dev/null 2>&1

        # 5. Network Connectivity Verification
        # Check internal IP (fast)
        CUR_IP=$(timeout 5 /usr/bin/adb -s "$DEV_ID" shell "ip -4 addr show" | grep -oP '(?<=inet\s)192\.168\.[0-9.]+' | head -n 1)
        if [ -z "$CUR_IP" ]; then
            log_info "[$DEV_ID] Network offline (No internal IP). Triggering system recovery..."
            sudo bash "$MODE_WIFI_ROOT/../utils/lte_surgical_setup.sh" >/dev/null 2>&1
            sleep 5
            continue
        fi

        # 6. Request Task from API
        REQ_PAYLOAD="{\"device_id\":\"$DEV_ID\",\"ip\":\"$CUR_IP\"}"
        RESPONSE=$(curl -s -X POST "http://$API_SERVER/api/v1/request_task" \
             -H "Content-Type: application/json" \
             -d "$REQ_PAYLOAD")
        
        if [ -z "$RESPONSE" ] || ! echo "$RESPONSE" | jq -e . >/dev/null 2>&1 || [ "$(echo "$RESPONSE" | jq -r '.status')" != "ok" ]; then
            log_info "[$DEV_ID] No task or API error."
            continue
        fi

        TASK_ID=$(echo "$RESPONSE" | jq -r '.task_id')
        NAME=$(echo "$RESPONSE" | jq -r '.destination.target_name')
        
        # Port Logic
        DEV_SEQ=$(echo "$DEV_ID" | cksum | awk '{print $1 % 1000}')
        FRIDA_PORT=$((6000 + DEV_SEQ))
        MITM_PORT=$((FRIDA_PORT + 10000))
        
        log_success "[$DEV_ID] ALLOCATED: $NAME | TaskID: $TASK_ID"

        # Record Spoofed Identity
        SPOOFED_JSON=$(echo "$RESPONSE" | jq -c '.identity.spoofed // empty')
        if [ -n "$SPOOFED_JSON" ]; then
            curl -s -X POST "http://$API_SERVER/api/v1/update_status" \
                 -H "Content-Type: application/json" \
                 -d "{\"task_id\": $TASK_ID, \"status\": \"ALLOCATED\", \"device_id\": \"$DEV_ID\", \"spoofed_identity\": $SPOOFED_JSON}" >> "${DEV_TMP_DIR}/main_debug.log" 2>/dev/null
        fi

        # Pre-register for safety
        echo "{\"task_id\": \"$TASK_ID\", \"start_ts\": $(date +%s), \"status\": \"ALLOCATING\"}" > "$CURRENT_TASK_JSON"

        # 7. EXECUTE ENGINE
        DEBUG_LOG="${DEV_TMP_DIR}/main_debug.log"
        ARR_TIME=$(echo "$RESPONSE" | jq -r '.arrival_time // 0')
        
        NMAP_API_RESPONSE="$RESPONSE" \
        NMAP_LOG_ID="$TASK_ID" \
        NMAP_TASK_ID="$TASK_ID" \
        NMAP_DEST_ID=$(echo "$RESPONSE" | jq -r '.destination.id') \
        NMAP_DEST_LAT=$(echo "$RESPONSE" | jq -r '.destination.lat') \
        NMAP_DEST_LNG=$(echo "$RESPONSE" | jq -r '.destination.lng') \
        NMAP_DEST_NAME="$NAME" \
        NMAP_DEST_ADDR=$(echo "$RESPONSE" | jq -r '.destination.address // empty') \
        NMAP_START_LAT=$(echo "$RESPONSE" | jq -r '.start_pos.lat') \
        NMAP_START_LNG=$(echo "$RESPONSE" | jq -r '.start_pos.lng') \
        NMAP_START_SPEED=$(echo "$RESPONSE" | jq -r '.start_pos.speed_kmh // 0') \
        NMAP_START_DIST=$(echo "$RESPONSE" | jq -r '.start_pos.dist_m // 0') \
        NMAP_MIN_ARRIVAL="$ARR_TIME" \
        NMAP_MAX_ARRIVAL=$(( ARR_TIME + 60 )) \
        NMAP_ID_SSAID=$(echo "$RESPONSE" | jq -r '.identity.spoofed.ssaid // empty') \
        NMAP_ID_ADID=$(echo "$RESPONSE" | jq -r '.identity.spoofed.adid // empty') \
        NMAP_ID_IDFV=$(echo "$RESPONSE" | jq -r '.identity.spoofed.idfv // empty') \
        NMAP_ID_NI=$(echo "$RESPONSE" | jq -r '.identity.spoofed.ni // empty') \
        NMAP_ID_TOKEN=$(echo "$RESPONSE" | jq -r '.identity.spoofed.token // empty') \
        NMAP_ORIG_SSAID=$(echo "$RESPONSE" | jq -r '.identity.original.ssaid // empty') \
        NMAP_ORIG_ADID=$(echo "$RESPONSE" | jq -r '.identity.original.adid // empty') \
        NMAP_ORIG_IDFV=$(echo "$RESPONSE" | jq -r '.identity.original.idfv // empty') \
        NMAP_ORIG_NI=$(echo "$RESPONSE" | jq -r '.identity.original.ni // empty') \
        NMAP_ORIG_TOKEN=$(echo "$RESPONSE" | jq -r '.identity.original.token // empty') \
        NMAP_FRIDA_PORT="$FRIDA_PORT" \
        NMAP_NO_IP="$SKIP_IP" \
        setsid bash "$MODE_WIFI_LIB/main.sh" "$DEV_ID" >> "$DEBUG_LOG" 2>&1 &
        
        log_info "[$DEV_ID] Engine forked."
        sleep 2
    done
    
    sleep 20
done
