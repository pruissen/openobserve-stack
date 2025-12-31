#!/bin/bash

SESSION_NAME="pf-minio"
NAMESPACE="o2-system"
# The built-in chart usually names the service 'openobserve-minio'
SERVICE="svc/openobserve-minio"
LOCAL_PORT="9001"
REMOTE_PORT="9001"
URL="http://localhost:$LOCAL_PORT"

get_user() {
    kubectl get secret o2-platform-secret -n $NAMESPACE -o jsonpath='{.data.rootUser}' 2>/dev/null | base64 -d
}

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
        echo "✅ MinIO port-forward is already running."
    else
        check_port
        echo "🚀 Starting MinIO port-forward..."
        # Forwarding Console port 9001
        screen -dmS $SESSION_NAME bash -c "while true; do echo 'Starting forward...'; kubectl port-forward $SERVICE -n $NAMESPACE $LOCAL_PORT:$REMOTE_PORT; echo 'Connection lost, retrying in 2s...'; sleep 2; done"
    fi
}

stop() {
    if screen -list | grep -q "\.$SESSION_NAME"; then
        screen -S $SESSION_NAME -X quit
        echo "🛑 MinIO port-forward stopped."
    else
        echo "⚠️  MinIO port-forward was not running."
    fi
}

show() {
    USER=$(get_user)
    PASS=$(get_password)
    STATUS="Stopped 🔴"
    if screen -list | grep -q "\.$SESSION_NAME"; then
        STATUS="Running 🟢"
    fi
    printf "%-15s | %-30s | %-20s | %-15s | %s\n" "MinIO" "$URL" "$USER" "$PASS" "$STATUS"
}

case "$1" in
    start) start ;;
    stop)  stop ;;
    show)  show ;;
    *) echo "Usage: $0 {start|stop|show}" ;;
esac