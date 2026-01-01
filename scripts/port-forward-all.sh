#!/bin/bash

SCRIPT_DIR=$(dirname "$0")

# Colors
BOLD="\033[1m"
RESET="\033[0m"
GREEN="\033[32m"
BLUE="\033[34m"
CYAN="\033[36m"
GRAY="\033[90m"

# Icons
ICON_START="🚀"
ICON_STOP="🛑"
ICON_RESTART="♻️ "
ICON_SHOW="🔍"
ICON_ERROR="❌"

check_screen() {
    if ! command -v screen &> /dev/null; then
        echo -e "${RED}$ICON_ERROR Error: 'screen' is not installed.${RESET}"
        exit 1
    fi
}

start_all() {
    echo -e "${BLUE}=======================================================${RESET}"
    echo -e "${BOLD}$ICON_START   STARTING PORT FORWARDS${RESET}"
    echo -e "${BLUE}=======================================================${RESET}"
    $SCRIPT_DIR/portforward-argocd.sh start
    $SCRIPT_DIR/portforward-openobserve.sh start
    $SCRIPT_DIR/portforward-minio.sh start
    $SCRIPT_DIR/portforward-oteldemo.sh start
    echo ""
    $0 show
}

stop_all() {
    echo -e "${BLUE}=======================================================${RESET}"
    echo -e "${BOLD}$ICON_STOP   STOPPING PORT FORWARDS${RESET}"
    echo -e "${BLUE}=======================================================${RESET}"
    $SCRIPT_DIR/portforward-argocd.sh stop
    $SCRIPT_DIR/portforward-openobserve.sh stop
    $SCRIPT_DIR/portforward-minio.sh stop
    $SCRIPT_DIR/portforward-oteldemo.sh stop
}

restart_all() {
    echo -e "${BLUE}=======================================================${RESET}"
    echo -e "${BOLD}$ICON_RESTART RESTARTING PORT FORWARDS${RESET}"
    echo -e "${BLUE}=======================================================${RESET}"
    stop_all
    echo -e "${GRAY}⏳ Waiting for cleanup...${RESET}"
    sleep 2
    echo ""
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
        echo -e "${BOLD}ACCESS INFORMATION${RESET}"
        echo -e "${GRAY}----------------------------------------------------------------------------------------------------------------------------------${RESET}"
        # Adjusted widths: Service(15) | URL(35) | User(25) | Pass(25) | Status
        printf "${CYAN}%-15s${RESET} | ${CYAN}%-35s${RESET} | ${CYAN}%-25s${RESET} | ${CYAN}%-25s${RESET} | ${CYAN}%s${RESET}\n" "SERVICE" "URL" "USER" "PASSWORD" "STATUS"
        echo -e "${GRAY}----------------------------------------------------------------------------------------------------------------------------------${RESET}"
        $SCRIPT_DIR/portforward-argocd.sh show
        $SCRIPT_DIR/portforward-openobserve.sh show
        $SCRIPT_DIR/portforward-minio.sh show
        $SCRIPT_DIR/portforward-oteldemo.sh show
        echo -e "${GRAY}----------------------------------------------------------------------------------------------------------------------------------${RESET}"
        echo ""
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|show}"
        exit 1
        ;;
esac