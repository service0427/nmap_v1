#!/bin/bash
# test_nmap_v1: Minimal Single Device Launcher

BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$BASE_DIR" || exit 1

DEV_ID=$1
shift

if [ -z "$DEV_ID" ]; then
    echo "Usage: ./run_single.sh <DEVICE_ID> [--reset] [--id TARGET_ID] [--close] [--macro]"
    exit 1
fi

RESET_MODE=false
AGREE_MODE=false
IP_CHANGE_MODE=false
TARGET_ID=""
NO_FILTER="false"
CLOSE_ON_EXIT=false
MACRO_MODE=false
PKG_NAME="com.nhn.android.nmap"
GPS_PKG="com.rosteam.gpsemulator"

while [[ $# -gt 0 ]]; do
    case $1 in
        --reset) RESET_MODE=true; shift ;;
        --original) NO_FILTER="true"; shift ;;
        --id) TARGET_ID="$2"; shift 2 ;;
        --agree) AGREE_MODE=true; shift ;;
        --ip) IP_CHANGE_MODE=true; shift ;;
        --close) CLOSE_ON_EXIT=true; shift ;;
        --macro) MACRO_MODE=true; shift ;;
        *) shift ;;
    esac
done

# 0. Environment Setup
export PATH=$PATH:$HOME/.local/bin
if ! command -v mitmdump &> /dev/null; then
    echo -e "\e[1;31m[-] Error: mitmdump not found in PATH ($PATH)\e[0m"
    exit 1
fi
if ! command -v frida &> /dev/null; then
    echo -e "\e[1;31m[-] Error: frida not found in PATH\e[0m"
    exit 1
fi

CYAN="\e[1;36m"
GREEN="\e[1;32m"
YELLOW="\e[1;33m"
MAGENTA="\e[1;35m"
NC="\e[0m"

# 1. Fetch Configuration from devices.json
CONFIG_FILE="api/devices.json"

if [[ "$DEV_ID" =~ ^[0-9]+$ ]]; then
    DEV_INDEX="$DEV_ID"
    MAPPED_ID=$(jq -r ".devices[$DEV_INDEX].id // empty" "$CONFIG_FILE")
    if [ -n "$MAPPED_ID" ]; then
        echo -e "${YELLOW}[*] Index $DEV_ID Resoved to Device ID: $MAPPED_ID${NC}"
        DEV_ID="$MAPPED_ID"
    else
        echo -e "\e[1;31m[-] Invalid device index: $DEV_ID\e[0m"
        exit 1
    fi
else
    DEV_INDEX=$(jq -r ".devices | map(.id) | index(\"$DEV_ID\") // empty" "$CONFIG_FILE")
fi

DEV_JSON=$(jq -c ".devices[] | select(.id == \"$DEV_ID\")" "$CONFIG_FILE")

if [ -z "$DEV_JSON" ]; then
    echo "[-] Device $DEV_ID not found in $CONFIG_FILE!"
    exit 1
fi

BASE_MITM_PORT=$(jq -r '.base_mitm_port // 30000' "$CONFIG_FILE")
MITM_PORT=$((BASE_MITM_PORT + DEV_INDEX + 1))
ALIAS=$(echo "$DEV_JSON" | jq -r '.alias')
FRIDA_PORT=$((MITM_PORT + 10000))
ORIG_SSAID=$(echo "$DEV_JSON" | jq -r '.baseline.ssaid')
ORIG_ADID=$(echo "$DEV_JSON" | jq -r '.baseline.adid')
ORIG_IDFV=$(echo "$DEV_JSON" | jq -r '.baseline.idfv')
ORIG_NI=$(echo "$DEV_JSON" | jq -r '.baseline.ni')
ORIG_TOKEN=$(echo "$DEV_JSON" | jq -r '.baseline.token')

# 2. Generate Random Identity to bypass detection
echo -e "${CYAN}[$ALIAS]${NC} Generating Randomized Identities..."
export NMAP_ORIG_SSAID="$ORIG_SSAID"
export NMAP_ORIG_ADID="$ORIG_ADID"
export NMAP_ORIG_IDFV="$ORIG_IDFV"
export NMAP_ORIG_NI="$ORIG_NI"
export NMAP_ORIG_TOKEN="$ORIG_TOKEN"
export NMAP_SPOOFED_SSAID=$(cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 16 | head -n 1)
export NMAP_SPOOFED_ADID=$(cat /proc/sys/kernel/random/uuid)
export NMAP_SPOOFED_IDFV=$(cat /proc/sys/kernel/random/uuid)
export NMAP_SPOOFED_NI=$(echo -n "$NMAP_SPOOFED_SSAID" | md5sum | awk '{print $1}')
export NMAP_SPOOFED_NLOG_TOKEN=$(python3 -c "import string, random; print(''.join(random.choices(string.ascii_letters + string.digits, k=16)))")

export NMAP_NO_FILTER="$NO_FILTER"

echo "============================================================"
echo "   NMAP V1 MINIMAL: $ALIAS ($DEV_ID)"
echo "   MITM:$MITM_PORT | FRIDA:$FRIDA_PORT"
echo "   TARGET_ID : ${TARGET_ID:-None} | RESET: $RESET_MODE | FILTER: $NO_FILTER"
if [ "$NO_FILTER" != "true" ]; then
    echo "------------------------------------------------------------"
    echo "   [SPOOFING MAPPINGS (Values will be replaced in Proxy)]"
    echo "        \"ssaid\": \"$ORIG_SSAID\" -> \"$NMAP_SPOOFED_SSAID\"," 
    echo "        \"adid\": \"$ORIG_ADID\" -> \"$NMAP_SPOOFED_ADID\"," 
    echo "        \"idfv\": \"$ORIG_IDFV\" -> \"$NMAP_SPOOFED_IDFV\"," 
    echo "        \"ni\": \"$ORIG_NI\" -> \"$NMAP_SPOOFED_NI\"," 
    echo "        \"token\": \"$ORIG_TOKEN\" -> \"$NMAP_SPOOFED_NLOG_TOKEN\"" 
fi
echo "============================================================"

# 3. Setup Logs
DATE_STR=$(date +%Y%m%d)
TIME_STR=$(date +%H%M%S)

LOG_NAME="$TIME_STR"
[ "$RESET_MODE" = true ] && LOG_NAME="${LOG_NAME}-reset"
[ "$AGREE_MODE" = true ] && LOG_NAME="${LOG_NAME}-agree"
[ "$IP_CHANGE_MODE" = true ] && LOG_NAME="${LOG_NAME}-ip"
[ "$NO_FILTER" = "true" ] && LOG_NAME="${LOG_NAME}-orig"
[ -n "$TARGET_ID" ] && LOG_NAME="${LOG_NAME}-${TARGET_ID}"

LOG_DIR="logs/${DEV_ID}/${DATE_STR}/${LOG_NAME}"
mkdir -p "$LOG_DIR"
export CAPTURE_LOG_DIR="$(realpath "$LOG_DIR")"

# Start background Logcat recording
LOGCAT_FILE="$CAPTURE_LOG_DIR/crash_debug.log"
adb -s "$DEV_ID" logcat -c
nohup adb -s "$DEV_ID" logcat *:E > "$LOGCAT_FILE" 2>&1 &
LOGCAT_PID=$!

# 4. ADBKeyboard Verification & Activation
# echo -e "${CYAN}[$ALIAS]${NC} Verifying ADBKeyboard..."
# ADB_KB_PKG="com.android.adbkeyboard"
# if ! adb -s "$DEV_ID" shell pm list packages | grep -q "$ADB_KB_PKG"; then
#     echo -e "\e[1;31m[!] CRITICAL: ADBKeyboard ($ADB_KB_PKG) is NOT installed on $ALIAS!\e[0m"
#     echo -e "\e[1;31m    Please install it first: adb -s $DEV_ID install ADBKeyboard.apk\e[0m"
#     exit 1
# fi
# adb -s "$DEV_ID" shell ime enable $ADB_KB_PKG/.AdbIME >/dev/null 2>&1
# adb -s "$DEV_ID" shell ime set $ADB_KB_PKG/.AdbIME >/dev/null 2>&1

# 5. Cleanup & Purge
echo -e "${CYAN}[$ALIAS]${NC} Cleaning up existing sessions..."
adb -s "$DEV_ID" shell am force-stop $PKG_NAME
adb -s "$DEV_ID" shell am force-stop $GPS_PKG
adb -s "$DEV_ID" shell settings put global http_proxy :0 2>/dev/null
adb -s "$DEV_ID" reverse --remove-all 2>/dev/null
pkill -f "mitmdump.*$MITM_PORT" 2>/dev/null


if [ "$IP_CHANGE_MODE" = true ]; then
    echo -e "${YELLOW}[$ALIAS] Toggling Airplane Mode to rotate Mobile IP...${NC}"
    adb -s "$DEV_ID" shell su -c "cmd connectivity airplane-mode enable"
    sleep 3
    adb -s "$DEV_ID" shell su -c "cmd connectivity airplane-mode disable"
    # Give mobile network time to physically attach to cell tower and get IP
    echo -e "    > Waiting for network connection (pinging 8.8.8.8)..."
    NETWORK_OK=false
    for i in {1..15}; do
        if adb -s "$DEV_ID" shell "ping -c 1 -W 1 8.8.8.8" >/dev/null 2>&1; then
            echo -e "    > ${GREEN}[✓] Network connected! ($i/15)${NC}"
            NETWORK_OK=true
            break
        fi
        sleep 1
    done
    
    if [ "$NETWORK_OK" = false ]; then
        echo -e "    > ${YELLOW}[!] Network didn't connect within 15s. Proceeding anyway, but errors may occur.${NC}"
    fi
fi

if [ "$RESET_MODE" = true ]; then
    echo -e "${CYAN}[$ALIAS]${NC} Performing Absolute Data Purge (--reset)..."
    # Use find to preserve native libs on Android 15
    adb -s "$DEV_ID" shell su -c "find /data/data/$PKG_NAME -mindepth 1 -maxdepth 1 ! -name 'lib' -exec rm -rf {} +"
    echo -e "${GREEN}[✓] [$ALIAS] App Data Nuked.${NC}"
fi

if [ "$AGREE_MODE" = true ]; then
    echo -e "${CYAN}[$ALIAS]${NC} Injecting App Preferences (Clova, Navigation tab, High-pass)..."
    APP_UID=$(adb -s "$DEV_ID" shell "su -c 'stat -c %U /data/data/$PKG_NAME'")
    APP_UID=$(echo "$APP_UID" | tr -d '\r\n')
    cat <<EOF > tmp_prefs_$$_$DEV_ID.xml
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <boolean name="HIPASS_POPUP_SHOWN" value="true" />
    <boolean name="INTERNAL_NAVI_UUID_PERSONAL_ROUTE_TERMS_AGREED" value="true" />
    <int name="PREF_ROUTE_TYPE" value="2" />
</map>
EOF
    cat <<EOF > tmp_navi_$$_$DEV_ID.xml
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <boolean name="NaviUseHipassKey" value="true" />
    <boolean name="NaviAutoChangeRoute" value="true" />
</map>
EOF
    cat <<EOF > tmp_consent_$$_$DEV_ID.xml
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <boolean name="PREF_CONSENT_CLOVA_CHECKED" value="true" />
    <boolean name="PREF_CONSENT_CLOVA_AGREED" value="true" />
</map>
EOF

    adb -s "$DEV_ID" push tmp_prefs_$$_$DEV_ID.xml /data/local/tmp/com.nhn.android.nmap_preferences.xml >/dev/null 2>&1
    adb -s "$DEV_ID" push tmp_navi_$$_$DEV_ID.xml /data/local/tmp/NativeNaviDefaults.xml >/dev/null 2>&1
    adb -s "$DEV_ID" push tmp_consent_$$_$DEV_ID.xml /data/local/tmp/ConsentInfo.xml >/dev/null 2>&1
    
    adb -s "$DEV_ID" shell "su -c 'mkdir -p /data/data/$PKG_NAME/shared_prefs'"
    adb -s "$DEV_ID" shell "su -c 'cp /data/local/tmp/com.nhn.android.nmap_preferences.xml /data/data/$PKG_NAME/shared_prefs/'"
    adb -s "$DEV_ID" shell "su -c 'cp /data/local/tmp/NativeNaviDefaults.xml /data/data/$PKG_NAME/shared_prefs/'"
    adb -s "$DEV_ID" shell "su -c 'cp /data/local/tmp/ConsentInfo.xml /data/data/$PKG_NAME/shared_prefs/'"
    
    adb -s "$DEV_ID" shell "su -c 'chown -R $APP_UID:$APP_UID /data/data/$PKG_NAME/shared_prefs'"
    adb -s "$DEV_ID" shell "su -c 'chmod -R 777 /data/data/$PKG_NAME/shared_prefs'"
    adb -s "$DEV_ID" shell "su -c 'restorecon -R /data/data/$PKG_NAME/shared_prefs'"
    
    rm -f tmp_prefs_$$_$DEV_ID.xml tmp_navi_$$_$DEV_ID.xml tmp_consent_$$_$DEV_ID.xml
fi

# 6. MITM Network proxy
echo -e "${CYAN}[$ALIAS]${NC} Setting up Proxy Tunnel (localhost:$MITM_PORT)..."
adb -s "$DEV_ID" reverse tcp:"$MITM_PORT" tcp:"$MITM_PORT" >/dev/null 2>&1
adb -s "$DEV_ID" shell settings put global http_proxy localhost:"$MITM_PORT"
adb -s "$DEV_ID" shell su -c 'iptables -I OUTPUT -p udp --dport 443 -j DROP'

MITM_LOG="$CAPTURE_LOG_DIR/mitm.log"
PYTHONWARNINGS=ignore nohup mitmdump -p "$MITM_PORT" \
    -s lib/mitm_addon.py \
    --ssl-insecure --listen-host 0.0.0.0 --set flow_detail=0 \
    > "$MITM_LOG" 2>&1 &
MITM_PID=$!

# 7. GPS Setup (If target ID provided)
GPS_PID=""
if [ -n "$TARGET_ID" ]; then
    echo -e "${YELLOW}[$ALIAS] Initializing GPS Simulation for Target: $TARGET_ID${NC}"
    chmod +x utils/run_gps_multi.sh
    # Start GPS emulator script
    ./utils/run_gps_multi.sh "$DEV_ID" "$TARGET_ID" &
    GPS_PID=$!
    sleep 2
fi

# 8. Start App and Minimal Frida survival
echo -e "${CYAN}[$ALIAS]${NC} Starting Frida Server..."
adb -s "$DEV_ID" shell "su -c 'killall -9 frida-server 2>/dev/null'"

# Find frida-server path
FRIDA_SERVER_PATH=$(adb -s "$DEV_ID" shell "su -c 'which frida-server'")
FRIDA_SERVER_PATH=$(echo "$FRIDA_SERVER_PATH" | tr -d '\r\n')

if [ -z "$FRIDA_SERVER_PATH" ]; then
    # Fallback to common path
    FRIDA_SERVER_PATH="/data/local/tmp/frida-server"
fi

adb -s "$DEV_ID" shell "su -c '( $FRIDA_SERVER_PATH -D >/dev/null 2>&1 & )'"
sleep 2
adb -s "$DEV_ID" forward tcp:$FRIDA_PORT tcp:27042 >/dev/null 2>&1

echo -e "${CYAN}[$ALIAS]${NC} Selecting hooks for system stability..."
HOOK_OPTS="-l lib/hooks/survival_light.js -l lib/hooks/network_hook.js -l lib/hooks/data_collector.js"
if [ "$MACRO_MODE" = true ]; then
    echo -e "${MAGENTA}[$ALIAS] Enabling Agreement Macro Bot...${NC}"
    HOOK_OPTS="$HOOK_OPTS -l lib/hooks/macro_agreement.js"
fi

FRIDA_LOG="$CAPTURE_LOG_DIR/frida.log"
nohup frida -H 127.0.0.1:$FRIDA_PORT --runtime=v8 -f "$PKG_NAME" $HOOK_OPTS --no-auto-reload > "$FRIDA_LOG" 2>&1 &
FRIDA_PID=$!

# 9. Simple 2-Second Log Polling Monitor (Ultra-Stable)
AUTO_PID=""
if [ "$MACRO_MODE" = true ]; then
    chmod +x utils/log_monitor.sh
    ./utils/log_monitor.sh "$DEV_ID" "$CAPTURE_LOG_DIR" "$TARGET_ID" &
    AUTO_PID=$!
fi

(sleep 3; adb -s "$DEV_ID" shell monkey -p "$PKG_NAME" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1) &

echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN} [✓] [$ALIAS] SYSTEM READY. Manual/Auto driving enabled.${NC}"
echo -e " [!] Log Directory: $CAPTURE_LOG_DIR"
echo -e " [!] Press Ctrl+C to STOP"
echo -e "${GREEN}============================================================${NC}"

cleanup() {
    echo -e "\n${YELLOW}[$ALIAS] Stopping processes and restoring network...${NC}"

    # Suppress bash job termination messages ("죽었음")
    disown $LOGCAT_PID $MITM_PID $FRIDA_PID $GPS_PID $AUTO_PID 2>/dev/null
    kill -9 $MITM_PID $FRIDA_PID $LOGCAT_PID $GPS_PID $AUTO_PID 2>/dev/null    adb -s "$DEV_ID" shell am force-stop $PKG_NAME
    adb -s "$DEV_ID" shell am force-stop $GPS_PKG
    adb -s "$DEV_ID" shell settings put global http_proxy :0 2>/dev/null
    adb -s "$DEV_ID" reverse --remove-all 2>/dev/null
    adb -s "$DEV_ID" forward --remove-all 2>/dev/null
    exit 0
}
trap cleanup INT TERM

if [ "$CLOSE_ON_EXIT" = true ]; then
    echo -e "${YELLOW}[$ALIAS] Monitoring app status (Wait-for-Start)...${NC}"
    
    # Phase 1: Wait until the app is actually running (timeout 20s)
    MAX_START_WAIT=20
    START_COUNT=0
    while [ $START_COUNT -lt $MAX_START_WAIT ]; do
        if adb -s "$DEV_ID" shell pidof "$PKG_NAME" >/dev/null 2>&1; then
            echo -e "${GREEN}[$ALIAS] App confirmed running. Monitoring for termination...${NC}"
            break
        fi
        sleep 1
        ((START_COUNT++))
    done

    # Phase 2: Monitor for termination only if app started
    if [ $START_COUNT -eq $MAX_START_WAIT ]; then
        echo -e "${YELLOW}[!] [$ALIAS] App failed to start within ${MAX_START_WAIT}s. Terminating...${NC}"
        cleanup
    fi

    while true; do
        # Robust Dual Check:
        # 1. Check if the process is still alive
        PID=$(adb -s "$DEV_ID" shell pidof "$PKG_NAME" 2>/dev/null)
        
        # 2. Check if the app is still in focus (Foreground)
        # Using a more inclusive grep pattern for different Android versions
        CURRENT_FOCUS=$(adb -s "$DEV_ID" shell "dumpsys activity activities | grep -E 'mResumedActivity|mCurrentFocus|topResumedActivity'")
        
        if [ -z "$PID" ]; then
            echo -e "${MAGENTA}[$ALIAS] App process terminated. Closing session...${NC}"
            cleanup
        elif [[ "$CURRENT_FOCUS" != *"$PKG_NAME"* ]]; then
            echo -e "${MAGENTA}[$ALIAS] App is no longer in foreground. Closing session...${NC}"
            cleanup
        fi
        sleep 3
    done
else
    # Wait for manual cancellation
    wait
fi
