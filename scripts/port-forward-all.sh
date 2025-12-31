#!/bin/bash

SCRIPT_DIR=$(dirname "$0")

# Icons
ICON_START="🚀"
ICON_STOP="🛑"
ICON_RESTART="♻️ "
ICON_SHOW="🔍"
ICON_ERROR="❌"
ICON_SUCCESS="✅"

check_screen() {
    if ! command -v screen &> /dev/null; then
        echo "$ICON_ERROR Error: 'screen' is not installed."
        exit 1
    fi
}

start_all() {
    echo "======================================================="
    echo "$ICON_START   STARTING PORT FORWARDS (SCREEN SESSIONS)"
    echo "======================================================="
    $SCRIPT_DIR/portforward-argocd.sh start
    $SCRIPT_DIR/portforward-openobserve.sh start
    $SCRIPT_DIR/portforward-minio.sh start
    $SCRIPT_DIR/portforward-oteldemo.sh start
    echo ""
    $0 show
}

stop_all() {
    echo "======================================================="
    echo "$ICON_STOP   STOPPING PORT FORWARDS"
    echo "======================================================="
    $SCRIPT_DIR/portforward-argocd.sh stop
    $SCRIPT_DIR/portforward-openobserve.sh stop
    $SCRIPT_DIR/portforward-minio.sh stop
    $SCRIPT_DIR/portforward-oteldemo.sh stop
}

restart_all() {
    echo "======================================================="
    echo "$ICON_RESTART RESTARTING PORT FORWARDS"
    echo "======================================================="
    stop_all
    echo "⏳ Waiting for cleanup..."
    sleep 2
    start_all
}

case "$1" in
    start)
        check_screen
        start_all
        ;;
    stop)
        stop_all
        ;;
    restart)
        check_screen
        restart_all
        ;;
    show)
        echo ""
        echo "=========================================================================================================="
        printf "%-15s | %-30s | %-20s | %-15s | %s\n" "SERVICE" "URL" "USER" "PASSWORD" "STATUS"
        echo "----------------------------------------------------------------------------------------------------------"
        $SCRIPT_DIR/portforward-argocd.sh show
        $SCRIPT_DIR/portforward-openobserve.sh show
        $SCRIPT_DIR/portforward-minio.sh show
        $SCRIPT_DIR/portforward-oteldemo.sh show
        echo "=========================================================================================================="
        echo ""
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|show}"
        exit 1
        ;;
esac