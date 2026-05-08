#!/bin/bash
# test_nmap_v2: Smart Multi-Device Task Orchestrator (V2.9.5 - Anti-Storm Logic)

# Parse Arguments
SKIP_IP=false; SINGLE_DEV_ID=""
for arg in "$@"; do
    if [ "$arg" == "--no-ip" ]; then SKIP_IP=true; elif [[ "$arg" != --* ]]; then SINGLE_DEV_ID="$arg"; fi
done

PKG_NAME="com.nhn.android.nmap"
export API_SERVER="121.173.150.103:5003"

# --- [CORE] Functions ---
NOW() { date +"%H:%M:%S.%3N"; }
log_info() { echo "[$(NOW)] [*] $1"; }
log_success() { echo "[$(NOW)] [🚀] $1"; }
log_busy() { echo "[$(NOW)] [⏳] $1"; }

echo "============================================================"
echo "   NMAP V2 DYNAMIC TASK ORCHESTRATOR (V2.9.5)"
echo "   Action: Anti-Storm & Robust Busy Detection"
echo "============================================================"

# 0. Initial Purge
pkill -9 -f "lib/main.sh"
pkill -9 -f "auto_reloader.py"
pkill -9 -f "monitor.sh"
pkill -9 -f "mitmdump"
pkill -9 -f "frida"
sleep 2

get_devices() {
    if [ -n "$SINGLE_DEV_ID" ]; then echo "$SINGLE_DEV_ID"; else timeout 5 /usr/bin/adb devices | grep -w "device" | awk '{print $1}'; fi
}

LAST_CLEANUP=0
while true; do
    # --- [AUTO CLEANUP] Keep only 7 days of logs ---
    CUR_TS=$(date +%s)
    if [ $((CUR_TS - LAST_CLEANUP)) -gt 3600 ]; then
        log_info "Cleanup: Removing logs older than 7 days (protecting system folders)..."
        # 숫자 8자리(날짜) 형식의 폴더만 타겟팅하여 tmp나 기타 설정 폴더가 삭제되는 것을 원천 차단
        find "$(dirname "$0")/logs" -mindepth 2 -maxdepth 2 -type d -name "20[0-9][0-9][0-9][0-9][0-9][0-9]" -mtime +7 -exec rm -rf {} + 2>/dev/null
        LAST_CLEANUP=$CUR_TS
    fi

    DEVICES=$(get_devices)
    if [ -z "$DEVICES" ]; then
        log_info "No devices detected. Retrying in 10s..."
        sleep 10
        continue
    fi

    echo "------------------------------------------------------------"
    log_info "Scanning $(echo $DEVICES | wc -w) devices..."

    for DEV_ID in $DEVICES; do
        # 기기별 격리된 tmp 폴더 생성
        DEV_TMP_DIR="$(dirname "$0")/logs/${DEV_ID}/tmp"
        mkdir -p "$DEV_TMP_DIR"

        # 1. 프로세스 체크 (격리된 락파일 사용)
        SCRIPT_PIDS=$(pgrep -f "lib/main.sh $DEV_ID" | xargs)
        
        if [ -n "$SCRIPT_PIDS" ]; then
            LOCK_FILE="${DEV_TMP_DIR}/nmap_lock"
            LOCK_TIME=$(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0)
            if [ "$LOCK_TIME" -gt 0 ]; then
                AGE=$(( $(date +%s) - LOCK_TIME ))
                if [ $AGE -lt 45 ]; then
                    continue
                fi
            fi
            log_info "[$DEV_ID] STALE session ($AGE s). Purging PIDs: $SCRIPT_PIDS"
            kill -9 $SCRIPT_PIDS 2>/dev/null
            rm -f "$LOCK_FILE"
        fi

        # 2. 기기 상태 체크 (앱이 포그라운드인지)
        # [중요] 앱이 떠있으면 주행 중이거나 로딩 중이므로 절대 새 작업 할당 안 함
        CURRENT_FOCUS=$(timeout 5 /usr/bin/adb -s "$DEV_ID" shell "dumpsys activity activities | grep -E 'mResumedActivity|mCurrentFocus|topResumedActivity' | grep $PKG_NAME" 2>/dev/null)
        if [ -n "$CURRENT_FOCUS" ]; then
            continue
        fi

        # 3. Request Task
        API_URL="http://$API_SERVER/api/v1/request?device_id=$DEV_ID"
        RESPONSE=$(curl -s "$API_URL")
        
        if [ -z "$RESPONSE" ] || [ "$(echo "$RESPONSE" | jq -r '.status')" != "ok" ]; then
            continue
        fi

        # Extract
        LOG_ID=$(echo "$RESPONSE" | jq -r '.log_id')
        NAME=$(echo "$RESPONSE" | jq -r '.destination.name')
        FRIDA_PORT=$(echo "$RESPONSE" | jq -r '.port')
        MITM_PORT=$((FRIDA_PORT + 10000))
        
        log_success "[$DEV_ID] ALLOCATED: $NAME (LogID:$LOG_ID)"

        # Record Spoofed Identity
        SPOOFED_JSON=$(echo "$RESPONSE" | jq -c '.identity.spoofed')
        curl -s -X POST "http://$API_SERVER/api/v1/update_status" \
             -H "Content-Type: application/json" \
             -d "{\"log_id\": $LOG_ID, \"status\": \"ALLOCATED\", \"device_id\": \"$DEV_ID\", \"spoofed_identity\": $SPOOFED_JSON}" >> "${DEV_TMP_DIR}/main_debug.log"

        # Socket Purge
        timeout 5 /usr/bin/adb -s "$DEV_ID" forward --remove tcp:$FRIDA_PORT >/dev/null 2>&1 || true
        fuser -k -n tcp "$MITM_PORT" >/dev/null 2>&1
        sleep 1

        # 4. EXECUTE V2 ENGINE (환경변수 주입 후 백그라운드 실행)
        # setsid를 사용하여 loop.sh와 완전히 분리된 세션에서 실행
        DEBUG_LOG="${DEV_TMP_DIR}/main_debug.log"
        NMAP_API_RESPONSE="$RESPONSE" \
        NMAP_LOG_ID="$LOG_ID" \
        NMAP_DEST_ID=$(echo "$RESPONSE" | jq -r '.destination.id') \
        NMAP_DEST_LAT=$(echo "$RESPONSE" | jq -r '.destination.lat') \
        NMAP_DEST_LNG=$(echo "$RESPONSE" | jq -r '.destination.lng') \
        NMAP_DEST_NAME="$NAME" \
        NMAP_DEST_ADDR=$(echo "$RESPONSE" | jq -r '.destination.address') \
        NMAP_MIN_ARRIVAL=$(echo "$RESPONSE" | jq -r '.destination.min_arrival // 10') \
        NMAP_MAX_ARRIVAL=$(echo "$RESPONSE" | jq -r '.destination.max_arrival // 30') \
        NMAP_ID_SSAID=$(echo "$RESPONSE" | jq -r '.identity.spoofed.ssaid') \
        NMAP_ID_ADID=$(echo "$RESPONSE" | jq -r '.identity.spoofed.adid') \
        NMAP_ID_IDFV=$(echo "$RESPONSE" | jq -r '.identity.spoofed.idfv') \
        NMAP_ID_NI=$(echo "$RESPONSE" | jq -r '.identity.spoofed.ni') \
        NMAP_ID_TOKEN=$(echo "$RESPONSE" | jq -r '.identity.spoofed.token') \
        NMAP_ORIG_SSAID=$(echo "$RESPONSE" | jq -r '.identity.original.ssaid') \
        NMAP_ORIG_ADID=$(echo "$RESPONSE" | jq -r '.identity.original.adid') \
        NMAP_ORIG_IDFV=$(echo "$RESPONSE" | jq -r '.identity.original.idfv') \
        NMAP_ORIG_NI=$(echo "$RESPONSE" | jq -r '.identity.original.ni') \
        NMAP_ORIG_TOKEN=$(echo "$RESPONSE" | jq -r '.identity.original.token') \
        NMAP_FRIDA_PORT="$FRIDA_PORT" \
        NMAP_NO_IP="$SKIP_IP" \
        setsid bash lib/main.sh "$DEV_ID" >> "$DEBUG_LOG" 2>&1 &
        
        log_info "[$DEV_ID] Engine forked successfully."
        sleep 2
    done
    
    # 다음 전체 스캔까지 대기 (폭풍 할당 방지)
    sleep 20
done
