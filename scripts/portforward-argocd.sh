#!/bin/bash

SESSION_NAME="pf-argocd"
NAMESPACE="argocd-system"
SERVICE="svc/argocd-server"
LOCAL_PORT="8443"
# When insecure is enabled, ArgoCD usually exposes port 80.
REMOTE_PORT="80" 
URL="http://localhost:$LOCAL_PORT"
USER="admin"

get_password() {
    # UPDATED: o2-platform-secret
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
        echo "✅ ArgoCD port-forward is already running."
    else
        check_port
        echo "🚀 Starting ArgoCD port-forward..."
        screen -dmS $SESSION_NAME bash -c "while true; do echo 'Starting forward...'; kubectl port-forward $SERVICE -n $NAMESPACE $LOCAL_PORT:$REMOTE_PORT; echo 'Connection lost, retrying in 2s...'; sleep 2; done"
    fi
}

stop() {
    if screen -list | grep -q "\.$SESSION_NAME"; then
        screen -S $SESSION_NAME -X quit
        echo "🛑 ArgoCD port-forward stopped."
    else
        echo "⚠️  ArgoCD port-forward was not running."
    fi
}

show() {
    PASS=$(get_password)
    STATUS="Stopped 🔴"
    if screen -list | grep -q "\.$SESSION_NAME"; then
        STATUS="Running 🟢"
    fi
    printf "%-15s | %-30s | %-20s | %-15s | %s\n" "ArgoCD" "$URL" "$USER" "$PASS" "$STATUS"
}

case "$1" in
    start) start ;;
    stop)  stop ;;
    show)  show ;;
    *) echo "Usage: $0 {start|stop|show}" ;;
esac