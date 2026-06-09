#!/bin/bash
# test_nmap_v2/gps/static.sh: Multi-device Static GPS Initializer

# --- [ADB TIMEOUT WRAPPER] ---
# 'command' 대신 실제 경로를 사용하여 timeout이 정상적으로 실행되도록 합니다.
adb() {
    timeout 10 /usr/bin/adb "$@"
}

DEVICE_ID=$1
BASE_LAT=$2
BASE_LNG=$3

if [ -z "$DEVICE_ID" ] || [ -z "$BASE_LAT" ] || [ -z "$BASE_LNG" ]; then
    echo "Usage: ./static.sh <DEVICE_ID> <LAT> <LNG>"
    exit 1
fi

PKG_NAME="com.rosteam.gpsemulator"

# 1. 목적지 인근 5~10km 지점 계산 (V1 smart_route_gen.py 로직 이식)
RAND_COORD=$(python3 -c "
import random, math
lat, lng = float($BASE_LAT), float($BASE_LNG)
r_min = 5.0 / 111.0
r_max = 10.0 / 111.0
u, v = random.random(), random.random()
w = math.sqrt(u * (r_max**2 - r_min**2) + r_min**2)
t = 2 * math.pi * v
target_lat = lat + w * math.sin(t)
target_lng = lng + (w * math.cos(t)) / math.cos(math.radians(lat))
print(f'{target_lat:.7f},{target_lng:.7f}')
")
TARGET_LAT=$(echo $RAND_COORD | cut -d',' -f1)
TARGET_LNG=$(echo $RAND_COORD | cut -d',' -f2)

# 2. XML 생성 (정적 모드 - 기기별 격리된 tmp 폴더 사용)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DEV_TMP_DIR="${SCRIPT_DIR}/../logs/${DEVICE_ID}/tmp"
mkdir -p "$DEV_TMP_DIR"
LOCAL_XML="${DEV_TMP_DIR}/static_prefs.xml"

cat <<EOF > "$LOCAL_XML"
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <boolean name="noads" value="true" />
    <boolean name="onettimeblock" value="true" />
    <int name="pagbookmark" value="1" />
    <int name="accion" value="0" />
    <float name="velocidad" value="0.0" />
    <string name="ruta0">Parking+1+0.0+0.0+${TARGET_LAT},${TARGET_LNG};${TARGET_LAT},${TARGET_LNG};</string>
    <string name="lastloc">Current+${TARGET_LAT},${TARGET_LNG}+15.0</string>
</map>
EOF

# 3. 주입 및 시작
PREFS_PATH="/data/data/$PKG_NAME/shared_prefs/${PKG_NAME}_preferences.xml"
adb -s "$DEVICE_ID" shell am force-stop "$PKG_NAME"
adb -s "$DEVICE_ID" push "$LOCAL_XML" "/data/local/tmp/static_gps.xml" >/dev/null 2>&1
# Find su path
has_su=$(adb -s "$DEVICE_ID" shell "which su" 2>/dev/null | tr -d '\r')
if [ -z "$has_su" ]; then
    has_su=$(adb -s "$DEVICE_ID" shell "ls /system/bin/su /system/xbin/su /sbin/su 2>/dev/null" | head -1 | tr -d '\r')
fi
[ -z "$has_su" ] && has_su="su"

adb -s "$DEVICE_ID" shell "$has_su -c 'cp /data/local/tmp/static_gps.xml $PREFS_PATH && chown \$(stat -c %u:%g /data/data/$PKG_NAME) $PREFS_PATH && chmod 660 $PREFS_PATH && rm /data/local/tmp/static_gps.xml'"

# Headless 모드로 서비스 시작 (속도 0으로 멈춰있음)
adb -s "$DEVICE_ID" shell "$has_su -c \"am start-foreground-service -n $PKG_NAME/.servicex2484 -a ACTION_START_CONTINUOUS --es uy.digitools.RUTA 'ruta0' --ef velocidad 0.0 --ei loopMode 1\"" > /dev/null 2>&1

rm -f "$LOCAL_XML"
echo "[✓] [$DEVICE_ID] Static GPS set at $TARGET_LAT, $TARGET_LNG"
