#!/bin/bash
# wifi_single/lib/main.sh: Unified Task Execution Engine (V4.1 - Real IP Verification)
export PATH="$HOME/.local/bin:$PATH"

# --- [ADB TIMEOUT WRAPPER] ---
# ADB 서버 데드락 및 좀비 프로세스 방지를 위해 모든 adb 명령에 10초 타임아웃 적용
# 'command'는 쉘 내장 명령어라 timeout이 실행할 수 없으므로 실제 경로(/usr/bin/adb)를 사용합니다.
adb() {
    timeout 10 /usr/bin/adb "$@"
}
export -f adb

cd "$MODE_WIFI_ROOT" || exit 1

DEV_ID=$1
if [ -z "$DEV_ID" ]; then exit 1; fi

RESET_MODE=true; AGREE_MODE=true
PKG_NAME="com.nhn.android.nmap"; GPS_PKG="com.rosteam.gpsemulator"

if [ -z "$NMAP_LOG_ID" ] || [ -z "$NMAP_DEST_ID" ]; then exit 1; fi
NMAP_MITM_PORT=$((NMAP_FRIDA_PORT + 10000))

# Export Constants
export NMAP_LOG_ID NMAP_DEST_ID CAPTURE_LOG_DIR
export NMAP_DEST_NAME NMAP_DEST_ADDR
export NMAP_MIN_ARRIVAL NMAP_MAX_ARRIVAL
export NMAP_ID_SSAID NMAP_ID_ADID NMAP_ID_NI NMAP_ID_IDFV NMAP_ID_TOKEN

# 1. Setup Logs
DATE_STR=$(date +%Y%m%d); TIME_STR=$(date +%H%M%S)
LOG_REL_PATH="logs/${DEV_ID}/${DATE_STR}/${TIME_STR}_${NMAP_DEST_ID}"
export CAPTURE_LOG_DIR="${MODE_WIFI_LOGS}/${DEV_ID}/${DATE_STR}/${TIME_STR}_${NMAP_DEST_ID}"
mkdir -p "$CAPTURE_LOG_DIR"

# 기기별 격리된 tmp 폴더 경로 설정 및 생성 (하트비트 조기 시작)
DEV_TMP_DIR="${MODE_WIFI_LOGS}/${DEV_ID}/tmp"
mkdir -p "$DEV_TMP_DIR"
LOCK_FILE="${DEV_TMP_DIR}/nmap_lock"

( while true; do touch "$LOCK_FILE"; sleep 10; done ) &
HEARTBEAT_PID=$!

cleanup() {
    local REASON=$1
    [ -z "$REASON" ] && REASON="Unknown Reason"
    echo -e "\n[$DEV_ID] Cleaning up session. Reason: $REASON"
    
    # [V3 STYLE] Report Final Result
    local FINAL_STATUS="FAIL"
    local SUMMARY_PATH="$CAPTURE_LOG_DIR/session_summary.json"
    
    # Check for perfect success
    if [ -f "$CAPTURE_LOG_DIR/.success" ]; then
        FINAL_STATUS="SUCCESS"
        REASON="Task Completed Successfully"
    else
        # [NEW] Partial Success Recovery (90%+ driven)
        if [ -f "$CAPTURE_LOG_DIR/.remaining_dist" ]; then
            local REM_KM=$(cat "$CAPTURE_LOG_DIR/.remaining_dist" | grep -oE "^[0-9.]+" || echo "999")
            local START_KM=$(awk "BEGIN {print $NMAP_START_DIST / 1000}")
            if (( $(echo "$REM_KM < 1.0" | bc -l) )) || (( $(echo "$REM_KM < ($START_KM * 0.1)" | bc -l) )); then
                FINAL_STATUS="SUCCESS_PARTIAL"
                REASON="Recovered Partial Success: Driven > 90% before crash/network drop (Rem: ${REM_KM}km)"
                echo "[$DEV_ID] [🌟] $REASON"
            fi
        fi
    fi
    
    local REQ_PAYLOAD="{\"task_id\": $NMAP_TASK_ID, \"device_id\": \"$DEV_ID\", \"status\": \"$FINAL_STATUS\", \"message\": \"Terminated: $REASON\"}"
    echo "[$(date +"%H:%M:%S.%3N")] [REQ] /api/v1/report_result | Payload: $REQ_PAYLOAD" >> "$EXEC_LOG"
    local RESPONSE=$(curl -s -X POST "http://${API_SERVER:-localhost:8000}/api/v1/report_result" -H "Content-Type: application/json" -d "$REQ_PAYLOAD")
    echo "[$(date +"%H:%M:%S.%3N")] [RES] $RESPONSE" >> "$EXEC_LOG"


    kill -9 $MITM_PID $FRIDA_PID $MONITOR_PID $RELOAD_PID $HEARTBEAT_PID 2>/dev/null
    adb -s "$DEV_ID" shell am force-stop $PKG_NAME
    local su_path=$(adb -s "$DEV_ID" shell "which su" 2>/dev/null | tr -d '\r')
    if [ -z "$su_path" ]; then
        su_path=$(adb -s "$DEV_ID" shell "ls /system/bin/su /system/xbin/su /sbin/su 2>/dev/null" | head -1 | tr -d '\r')
    fi
    [ -z "$su_path" ] && su_path="su"
    adb -s "$DEV_ID" shell "$su_path -c 'am stopservice $GPS_PKG/.servicex2484'" 2>/dev/null
    local cur_proxy=$(adb -s "$DEV_ID" shell settings get global http_proxy 2>/dev/null | tr -d '\r\n')
    if [[ "$cur_proxy" == *":"$NMAP_MITM_PORT ]]; then
        adb -s "$DEV_ID" shell settings put global http_proxy :0 2>/dev/null
    fi
    adb -s "$DEV_ID" reverse --remove tcp:"$NMAP_FRIDA_PORT" 2>/dev/null
    adb -s "$DEV_ID" reverse --remove tcp:"$NMAP_MITM_PORT" 2>/dev/null
    adb -s "$DEV_ID" forward --remove tcp:"$NMAP_FRIDA_PORT" 2>/dev/null
    rm -f "$LOCK_FILE"
    rm -f "$CURRENT_TASK_JSON"
    echo "[$DEV_ID] Session terminated safely."
    exit 0
}
trap "cleanup 'Interrupted by Signal'" INT TERM

# Save Original API Response
if [ -n "$NMAP_API_RESPONSE" ]; then
    echo "$NMAP_API_RESPONSE" | jq '.' > "$CAPTURE_LOG_DIR/api_response.json" 2>/dev/null
fi

EXEC_LOG="$CAPTURE_LOG_DIR/execution.log"
exec > >(tee -a "$EXEC_LOG") 2>&1

echo "============================================================"
echo " [$DEV_ID] TASK STARTED (LogID: $NMAP_LOG_ID)"
echo " Destination: $NMAP_DEST_NAME (ID: $NMAP_DEST_ID)"
echo " FRIDA:$NMAP_FRIDA_PORT | MITM:$NMAP_MITM_PORT"
echo "------------------------------------------------------------"

# 1.5 IP Change & REAL IP Verification
if [ "$NMAP_NO_IP" != "true" ]; then
    REAL_IP="Unknown"
    CONNECTED=false
    # 최대 30초 대기
    for i in {1..30}; do
        if adb -s "$DEV_ID" shell "ping -c 1 -W 1 8.8.8.8" >/dev/null 2>&1; then
            # 실제 HTTP 요청이 성공하는지 확인 (static curl DNS & SSL CA 우회 지원)
            resolved_ip=$(adb -s "$DEV_ID" shell "ping -c 1 -W 2 ifconfig.me | head -n 1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'" | tr -d '\r\n')
            if [ -n "$resolved_ip" ]; then
                REAL_IP=$(adb -s "$DEV_ID" shell "[ -x /data/local/tmp/curl ] && /data/local/tmp/curl -4 -s --connect-timeout 3 --resolve ifconfig.me:80:$resolved_ip http://ifconfig.me || curl -4 -s --connect-timeout 3 --resolve ifconfig.me:80:$resolved_ip http://ifconfig.me" | tr -d '\r\n')
                if [ -n "$REAL_IP" ] && [[ "$REAL_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    echo " [✓] Connected! Real IPv4: $REAL_IP"
                    CONNECTED=true
                    break
                fi
            fi
        fi
        echo -n "."
        sleep 1
    done
    
    if [ "$CONNECTED" = false ]; then
        echo " [🚨] Network verification FAILED. Terminating session."
        REQ_PAYLOAD="{\"task_id\": $NMAP_TASK_ID, \"status\": \"FAIL_NETWORK_TIMEOUT\", \"device_id\": \"$DEV_ID\", \"drive_dist\": 0, \"drive_time\": 0}"
        echo "[$(date +"%H:%M:%S.%3N")] [REQ] /api/v1/update_status | Payload: $REQ_PAYLOAD" >> "$EXEC_LOG"
        RES=$(curl -s -X POST "http://${API_SERVER:-localhost:8000}/api/v1/update_status" -H "Content-Type: application/json" -d "$REQ_PAYLOAD")
        echo "[$(date +"%H:%M:%S.%3N")] [RES] $RES" >> "$EXEC_LOG"
        exit 1
    fi

    # Update Status to Server with Real IP
    REQ_PAYLOAD="{\"task_id\": $NMAP_TASK_ID, \"status\": \"IP_CHANGED\", \"device_id\": \"$DEV_ID\", \"real_ip\": \"$REAL_IP\", \"drive_dist\": 0, \"drive_time\": 0}"
    echo "[$(date +"%H:%M:%S.%3N")] [REQ] /api/v1/update_status | Payload: $REQ_PAYLOAD" >> "$EXEC_LOG"
    RES=$(curl -s -X POST "http://${API_SERVER:-localhost:8000}/api/v1/update_status" -H "Content-Type: application/json" -d "$REQ_PAYLOAD")
    echo "[$(date +"%H:%M:%S.%3N")] [RES] $RES" >> "$EXEC_LOG"
    export NMAP_REAL_IP="$REAL_IP"
    sleep 2
fi

# 1.55 Gather Environmental Metrics
ENV_TEMP=$(adb -s "$DEV_ID" shell dumpsys battery | grep temperature | awk '{print $2}' | tr -d '\r\n' || echo "0")
ENV_BATT=$(adb -s "$DEV_ID" shell dumpsys battery | grep level | awk '{print $2}' | tr -d '\r\n' || echo "0")
ENV_WIFI=$(adb -s "$DEV_ID" shell cmd wifi status 2>/dev/null | grep RSSI | sed -E 's/.*RSSI: ([-0-9]+).*/\1/' | tr -d '\r\n' || echo "0")
ENV_RAM=$(adb -s "$DEV_ID" shell cat /proc/meminfo 2>/dev/null | grep MemAvailable | awk '{print $2}' | tr -d '\r\n' || echo "0")
ENV_TEMP_C=$(awk "BEGIN {print $ENV_TEMP / 10}")

echo "[$DEV_ID] [📊] Environment Snapshot: Temp=${ENV_TEMP_C}°C | Batt=${ENV_BATT}% | Wi-Fi RSSI=${ENV_WIFI}dBm | Free RAM=${ENV_RAM}kB" >> "$EXEC_LOG"

# 1.6 Initialize Session Summary
echo "{\"task_id\": $NMAP_TASK_ID, \"device_id\": \"$DEV_ID\", \"real_ip\": \"$NMAP_REAL_IP\", \"task_start_time\": \"$(date +%Y-%m-%dT%H:%M:%S)\", \"status\": \"STARTED\", \"env\": {\"temp_c\": $ENV_TEMP_C, \"battery\": $ENV_BATT, \"wifi_rssi\": \"$ENV_WIFI\", \"free_ram_kb\": \"$ENV_RAM\"}}" > "$CAPTURE_LOG_DIR/session_summary.json"

# [NEW] Create Live Task Badge for Web Monitor (즉시 할당 정보 반영)
CURRENT_TASK_JSON="${MODE_WIFI_LOGS}/${DEV_ID}/current_task.json"
jq -n \
  --arg lid "$NMAP_TASK_ID" \
  --arg dname "$NMAP_DEST_NAME" \
  --arg tmin "$NMAP_MIN_ARRIVAL" \
  --arg tmax "$NMAP_MAX_ARRIVAL" \
  --arg dist "$NMAP_START_DIST" \
  --arg speed "$NMAP_START_SPEED" \
  --arg target_sec "$NMAP_MIN_ARRIVAL" \
  --arg sts "$(date +%s)" \
  --arg siso "$(date -Iseconds)" \
  --arg ip "$NMAP_REAL_IP" \
  --arg path "$LOG_REL_PATH" \
  --arg fport "$NMAP_FRIDA_PORT" \
  --arg mport "$NMAP_MITM_PORT" \
  '{task_id: $lid, dest_name: $dname, status: "INITIALIZING", target_range: ($tmin + "~" + $tmax), target_sec: ($target_sec|tonumber), total_dist_km: ($dist|tonumber / 1000), avg_speed_kmh: ($speed|tonumber), start_ts: ($sts|tonumber), start_iso: $siso, real_ip: $ip, session_path: $path, ports: {frida: $fport, mitm: $mport}}' \
  > "$CURRENT_TASK_JSON" 2>/dev/null

# 2. Cleanup, Screen Wakeup & Popup Clear
echo "[$DEV_ID] Waking up screen and clearing system popups..."
# 화면 켜기 (224) 및 잠금 해제 (82)
adb -s "$DEV_ID" shell input keyevent 224
adb -s "$DEV_ID" shell input keyevent 82
# 혹시 모를 팝업(배터리, 시스템 알림)을 치우기 위해 뒤로가기(4) 후 홈(3)으로 이동
adb -s "$DEV_ID" shell input keyevent 4
adb -s "$DEV_ID" shell input keyevent 3

adb -s "$DEV_ID" shell am force-stop $PKG_NAME
adb -s "$DEV_ID" shell am force-stop $GPS_PKG
adb -s "$DEV_ID" shell settings put global http_proxy :0 2>/dev/null
pkill -9 -f "mitmdump.*-p[[:space:]]+$NMAP_MITM_PORT" 2>/dev/null

ADB_KB_PKG="com.android.adbkeyboard"
adb -s "$DEV_ID" shell ime enable $ADB_KB_PKG/.AdbIME >/dev/null 2>&1
adb -s "$DEV_ID" shell ime set $ADB_KB_PKG/.AdbIME >/dev/null 2>&1

# 3. Golden Template Injection
if [ "$RESET_MODE" = true ]; then
    APP_UID=$(adb -s "$DEV_ID" shell "pm list packages -U $PKG_NAME" | grep -oE "uid:[0-9]+" | cut -d: -f2 | head -n 1)
    [ -z "$APP_UID" ] && APP_UID="root"
    chmod +x lib/inject_template.sh
    ./lib/inject_template.sh "$DEV_ID" "$PKG_NAME" "$APP_UID" "$NMAP_ORIG_SSAID"
fi

# 4. Networking & Proxy
echo "[$DEV_ID] Setting up Proxy Tunnel (MITM:$NMAP_MITM_PORT)..."
fuser -k -n tcp "$NMAP_FRIDA_PORT" >/dev/null 2>&1
fuser -k -n tcp "$NMAP_MITM_PORT" >/dev/null 2>&1
adb -s "$DEV_ID" reverse tcp:"$NMAP_FRIDA_PORT" tcp:"$NMAP_FRIDA_PORT" >/dev/null 2>&1
adb -s "$DEV_ID" reverse tcp:"$NMAP_MITM_PORT" tcp:"$NMAP_MITM_PORT" >/dev/null 2>&1
adb -s "$DEV_ID" shell settings put global http_proxy localhost:"$NMAP_MITM_PORT"

# [NEW] Dynamic Multi-LTE Binding Logic (SSID Based)
# This logic supports 1:N (1 Modem : Multiple Devices)
echo "[$DEV_ID] Detecting connected Wi-Fi SSID..."
CURRENT_SSID=$(adb -s "$DEV_ID" shell "cmd wifi status" 2>/dev/null | grep "SSID:" | head -1 | sed -E 's/.*SSID: "([^"]+)".*/\1/' | tr -d '\r\n')

CONNECT_ADDR_OPT=""
if [ -n "$CURRENT_SSID" ]; then
    # SSID 이름에서 가장 마지막에 나오는 11~20 사이의 숫자 추출 (예: U26-06-11 -> 11)
    SUBNET_NUM=$(echo "$CURRENT_SSID" | grep -oE "1[1-9]|20" | tail -n 1)
    
    if [ -z "$SUBNET_NUM" ]; then
        # [Single Mode Fallback] If no specific subnet in SSID, pick the first available LTE interface
        TARGET_IF=$(ip -br link show | grep -E "^lte" | awk '{print $1}' | head -n 1)
        if [ -n "$TARGET_IF" ]; then
            TARGET_IP=$(ip -4 addr show "$TARGET_IF" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)
        fi
    else
        TARGET_IF="lte$SUBNET_NUM"
        TARGET_IP=$(ip -4 addr show "$TARGET_IF" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)
    fi
    
    if [ -n "$TARGET_IP" ]; then
        echo "[$DEV_ID] WiFi($CURRENT_SSID) -> Interface($TARGET_IF) -> IP($TARGET_IP)"
        CONNECT_ADDR_OPT="--set connect_addr=$TARGET_IP"
    else
        echo "[$DEV_ID] [⚠️] Interface $TARGET_IF not found or has no IP. Falling back to default routing."
    fi
else
    # Even without Wi-Fi SSID, try to bind to LTE for safety
    TARGET_IF=$(ip -br link show | grep -E "^lte" | awk '{print $1}' | head -n 1)
    if [ -n "$TARGET_IF" ]; then
        TARGET_IP=$(ip -4 addr show "$TARGET_IF" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)
        if [ -n "$TARGET_IP" ]; then
            echo "[$DEV_ID] No SSID, but forcing Interface($TARGET_IF) -> IP($TARGET_IP)"
            CONNECT_ADDR_OPT="--set connect_addr=$TARGET_IP"
        fi
    fi
    [ -z "$TARGET_IP" ] && echo "[$DEV_ID] [⚠️] Device not connected to any Wi-Fi. Falling back to default routing."
fi

# 5. Workers
nohup mitmdump -p "$NMAP_MITM_PORT" $CONNECT_ADDR_OPT -s mitm/addon.py --ssl-insecure --listen-host 0.0.0.0 --set flow_detail=0 > "$CAPTURE_LOG_DIR/mitm.log" 2>&1 &
MITM_PID=$!
chmod +x macro/monitor.sh
nohup ./macro/monitor.sh "$DEV_ID" "$CAPTURE_LOG_DIR" "$NMAP_DEST_ID" &
MONITOR_PID=$!
setsid python3 gps/auto_reloader.py "$CAPTURE_LOG_DIR" "$DEV_ID" >> "$EXEC_LOG" 2>&1 &
RELOAD_PID=$!

# 6. Launch & Frida
echo "[$DEV_ID] Launching Optimized Session via Frida Spawn (Zero-Gap)..."
FRIDA_LOG="$CAPTURE_LOG_DIR/frida.log"
adb -s "$DEV_ID" forward tcp:"$NMAP_FRIDA_PORT" tcp:27042 >/dev/null 2>&1

# [NEW] Clear App Cache to prevent OOM/Stale Cache Crashes
CACHE_SU_PATH=$(adb -s "$DEV_ID" shell "which su" 2>/dev/null | tr -d '\r')
[ -z "$CACHE_SU_PATH" ] && CACHE_SU_PATH="su"
adb -s "$DEV_ID" shell "$CACHE_SU_PATH -c 'rm -rf /data/user/0/$PKG_NAME/cache/*'" 2>/dev/null
echo "[$DEV_ID] App cache cleared."

# [V3 STYLE] Start at API-provided location
./gps/static.sh "$DEV_ID" "$NMAP_START_LAT" "$NMAP_START_LNG"

# Use Frida to SPAWN the app (-f)
# This completely eliminates the timing gap where the app could detect root/frida before hooks apply.
nohup frida -H localhost:"$NMAP_FRIDA_PORT" --runtime=v8 -f "$PKG_NAME" \
    -l lib/hooks/network_hook.js \
    -l lib/hooks/_core_survival.js \
    --no-auto-reload > "$FRIDA_LOG" 2>&1 &
FRIDA_PID=$!

# Give the app a few seconds to fully initialize
sleep 5

# Trap is already configured at the top

while true; do
    PID=$(adb -s "$DEV_ID" shell pidof "$PKG_NAME" 2>/dev/null)
    [ -z "$PID" ] && cleanup "App process missing (Crash or killed by OS)"
    
    if ! kill -0 $FRIDA_PID 2>/dev/null; then
        cleanup "Frida disconnected or crashed"
    fi

    sleep 5
done
