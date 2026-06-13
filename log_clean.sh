#!/bin/bash
# log_clean.sh: Robust Hourly log cleanup for wifi_single (V1.0.0)

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LOG_ROOT="$SCRIPT_DIR/wifi_single/logs"
NOW=$(date +"%Y-%m-%d %H:%M:%S")

echo "[$NOW] Starting Robust Hourly Cleanup for wifi_single..."

if [ ! -d "$LOG_ROOT" ]; then
    echo "[$NOW] [!] Log root not found: $LOG_ROOT"
    exit 1
fi

# 1. Delete everything older than 1 hour at depth 2 or deeper
# (wifi_single/logs/{DEVICE}/{DATE} or wifi_single/logs/{DEVICE}/{DATE}/{SESSION})
find "$LOG_ROOT" -mindepth 2 -not -newermt "1 hour ago" \
    ! -path "*/tmp*" \
    ! -name "current_task.json" \
    ! -name "nmap_lock" \
    -exec rm -rf {} + 2>/dev/null

# 2. Cleanup empty directories
find "$LOG_ROOT" -mindepth 2 -type d -empty -delete 2>/dev/null

echo "[$NOW] Cleanup complete for wifi_single."
