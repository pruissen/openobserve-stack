#!/bin/bash

SESSION_NAME="pf-demo"
NAMESPACE="devteam-1"
SERVICE="svc/opentelemetry-demo-frontendproxy"
LOCAL_PORT="8080"
REMOTE_PORT="8080"
URL="http://localhost:$LOCAL_PORT"
USER="(No Auth)"

check_port() {
    if lsof -Pi :$LOCAL_PORT -sTCP:LISTEN -t >/dev/null ; then
        echo "⚠️  Port $LOCAL_PORT is already in use."
        return 1
    fi
    return 0
}

start() {
    if screen -list | grep -q "\.$SESSION_NAME"; then
        echo "✅ OTel Demo port-forward is already running."
        return
    fi
    if ! kubectl get $SERVICE -n $NAMESPACE >/dev/null 2>&1; then
        echo "⚠️  OTel Demo service not found. Skipping start."
        return
    fi
    
    check_port
    echo "🚀 Starting OTel Demo port-forward..."
    screen -dmS $SESSION_NAME bash -c "while true; do echo 'Starting forward...'; kubectl port-forward $SERVICE -n $NAMESPACE $LOCAL_PORT:$REMOTE_PORT; echo 'Connection lost, retrying in 2s...'; sleep 2; done"
}

stop() {
    if screen -list | grep -q "\.$SESSION_NAME"; then
        screen -S $SESSION_NAME -X quit
        echo "🛑 OTel Demo port-forward stopped."
    else
        echo "⚠️  OTel Demo port-forward was not running."
    fi
}

show() {
    PASS=""
    STATUS="Stopped 🔴"
    if screen -list | grep -q "\.$SESSION_NAME"; then
        STATUS="Running 🟢"
    fi
    printf "%-15s | %-30s | %-20s | %-15s | %s\n" "OTel Demo" "$URL" "$USER" "$PASS" "$STATUS"
}

case "$1" in
    start) start ;;
    stop)  stop ;;
    show)  show ;;
    *) echo "Usage: $0 {start|stop|show}" ;;
esac