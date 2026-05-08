#!/usr/bin/env bash

# Central dispatch script for various actions
CMD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/cmd" &> /dev/null && pwd)"

case "$1" in
    --home)
        bash "$CMD_DIR/home.sh"
        ;;
    --mute)
        bash "$CMD_DIR/mute.sh"
        ;;
    --dark)
        bash "$CMD_DIR/dark.sh"
        ;;
    --portrait|--portait)
        bash "$CMD_DIR/portrait.sh"
        ;;
    --data)
        bash "$CMD_DIR/data_always.sh"
        ;;
    --ip)
        bash "$CMD_DIR/ip.sh"
        ;;
    --gps)
        bash "$CMD_DIR/gps.sh" "$2"
        ;;
    --move)
        bash "$CMD_DIR/move.sh" "$2" "$3"
        ;;
    --speed)
        bash "$CMD_DIR/speed.sh" "$2" "$3"
        ;;
    --no-mtp)
        bash "$CMD_DIR/disable_mtp.sh"
        ;;
    --reboot)
        bash "$CMD_DIR/reboot.sh"
        ;;
    --reload)
        bash "$CMD_DIR/reload.sh" "$2"
        ;;
    *)
        # Default behavior: run open_missing.py to open disconnected screens
        python3 "$CMD_DIR/open_missing.py" --keep "$@"
        ;;
esac
