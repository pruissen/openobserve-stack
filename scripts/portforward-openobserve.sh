#!/bin/bash

SESSION_NAME="pf-o2"
NAMESPACE="o2-system"
SERVICE="svc/openobserve-router"
LOCAL_PORT="5080"
REMOTE_PORT="5080"
URL="http://localhost:$LOCAL_PORT"
API_URL="http://localhost:$LOCAL_PORT/swagger"
USER="admin@platform.com"

get_password() {
    kubectl get secret o2-platform-secret -n $NAMESPACE -o jsonpath='{.data.rootPassword}' 2>/dev/null | base64 -d
}

check_port() {
    if lsof -Pi :$LOCAL_PORT -sTCP:LISTEN -t >/dev/null ; then
        echo "⚠️  Port $LOCAL_PORT is already in use."
        return 1
    fi
    return 0
}

start() {
    if screen -list | grep -q "\.$SESSION_NAME"; then
        echo "✅ OpenObserve port-forward is already running."
    else
        check_port
        echo "🚀 Starting OpenObserve port-forward..."
        screen -dmS $SESSION_NAME bash -c "while true; do echo 'Starting forward...'; kubectl port-forward $SERVICE -n $NAMESPACE $LOCAL_PORT:$REMOTE_PORT; echo 'Connection lost, retrying in 2s...'; sleep 2; done"
    fi
}

stop() {
    if screen -list | grep -q "\.$SESSION_NAME"; then
        screen -S $SESSION_NAME -X quit
        echo "🛑 OpenObserve port-forward stopped."
    else
        echo "⚠️  OpenObserve port-forward was not running."
    fi
}

show() {
    PASS=$(get_password)
    STATUS="Stopped 🔴"
    if screen -list | grep -q "\.$SESSION_NAME"; then
        STATUS="Running 🟢"
    fi
    # Print Main UI Row
    printf "%-15s | %-30s | %-20s | %-15s | %s\n" "OpenObserve" "$URL" "$USER" "$PASS" "$STATUS"
    # Print API Row (Empty User/Pass/Status columns for visual cleanliness)
    printf "%-15s | %-30s | %-20s | %-15s | %s\n" "  ↳ API" "$API_URL" "" "" ""
}

case "$1" in
    start) start ;;
    stop)  stop ;;
    show)  show ;;
    *) echo "Usage: $0 {start|stop|show}" ;;
esac