#!/bin/bash

CMD=$1
SESSION_NAME="k8s-pf"

# Helper to find a free port or kill existing process on that port
cleanup_port() {
    local PORT=$1
    PID=$(lsof -ti :$PORT)
    if [ -n "$PID" ]; then
        echo "   -> Freeing port $PORT (Killing PID $PID)"
        kill -9 $PID
    fi
}

start_pf() {
    echo "=================================================================="
    echo "STARTING PORT FORWARDS (SCREEN SESSION: $SESSION_NAME)"
    echo "=================================================================="

    # 1. Check if session already exists
    if screen -list | grep -q "\.$SESSION_NAME"; then
        echo "⚠️  Screen session '$SESSION_NAME' already exists."
        echo "   Use './manage-local-connection.sh restart' to force a reset."
        return
    fi

    # 2. Cleanup Ports first to prevent bind errors
    cleanup_port 8443
    cleanup_port 5080
    cleanup_port 9001

    # 3. Create the detached screen session
    # We start with a dummy shell to keep the session alive while we add windows
    screen -dmS $SESSION_NAME bash

    # 4. Add Windows for each service
    
    # ArgoCD
    echo "   + Adding ArgoCD (8443)..."
    screen -S $SESSION_NAME -X screen -t argocd bash -c "kubectl port-forward svc/argocd-server -n argocd 8443:443; exec bash"
    
    # OpenObserve
    echo "   + Adding OpenObserve (5080)..."
    screen -S $SESSION_NAME -X screen -t openobserve bash -c "kubectl port-forward svc/openobserve-router -n openobserve-system 5080:5080; exec bash"
    
    # MinIO
    echo "   + Adding MinIO (9001)..."
    screen -S $SESSION_NAME -X screen -t minio bash -c "kubectl port-forward svc/minio-console -n minio-system 9001:9001; exec bash"

    echo "✅ Port forwards running in background."
    echo "   To view logs: ./manage-local-connection.sh attach"
}

stop_pf() {
    echo "=================================================================="
    echo "STOPPING PORT FORWARDS"
    echo "=================================================================="
    
    if screen -list | grep -q "\.$SESSION_NAME"; then
        screen -S $SESSION_NAME -X quit
        echo "✅ Screen session '$SESSION_NAME' terminated."
    else
        echo "ℹ️  No active screen session found."
    fi

    # Fallback cleanup just in case orphaned processes remain
    cleanup_port 8443
    cleanup_port 5080
    cleanup_port 9001
}

show_info() {
    echo ""
    echo "=================================================================="
    echo "ACCESS INFORMATION"
    echo "=================================================================="
    
    # Decode logic using kubectl template (Cross-platform)
    ARGO_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o go-template='{{.data.password | base64decode}}' 2>/dev/null)
    ZO_USER=$(kubectl -n openobserve-system get secret openobserve-creds -o go-template='{{.data.ZO_ROOT_USER_EMAIL | base64decode}}' 2>/dev/null)
    ZO_PASS=$(kubectl -n openobserve-system get secret openobserve-creds -o go-template='{{.data.ZO_ROOT_USER_PASSWORD | base64decode}}' 2>/dev/null)
    MINIO_USER=$(kubectl -n minio-system get secret minio-creds -o go-template='{{.data.rootUser | base64decode}}' 2>/dev/null)
    MINIO_PASS=$(kubectl -n minio-system get secret minio-creds -o go-template='{{.data.rootPassword | base64decode}}' 2>/dev/null)

    if [ -z "$ARGO_PASS" ]; then ARGO_PASS="<Not Found>"; fi
    if [ -z "$ZO_USER" ]; then ZO_USER="<Not Found>"; fi

    printf "%-15s | %-25s | %-20s | %s\n" "Service" "URL" "User" "Password"
    echo "------------------------------------------------------------------------------------------------"
    printf "%-15s | %-25s | %-20s | %s\n" "ArgoCD" "https://127.0.0.1:8443" "admin" "$ARGO_PASS"
    printf "%-15s | %-25s | %-20s | %s\n" "OpenObserve" "http://127.0.0.1:5080" "$ZO_USER" "$ZO_PASS"
    printf "%-15s | %-25s | %-20s | %s\n" "MinIO" "http://127.0.0.1:9001" "$MINIO_USER" "$MINIO_PASS"
    echo "=================================================================="
    echo ""
}

# Ensure 'screen' is installed
if ! command -v screen &> /dev/null; then
    echo "❌ Error: 'screen' is not installed. Please install it (e.g., sudo apt install screen)."
    exit 1
fi

case "$CMD" in
    start)
        start_pf
        show_info
        ;;
    stop)
        stop_pf
        ;;
    info)
        show_info
        ;;
    restart)
        stop_pf
        sleep 2
        start_pf
        show_info
        ;;
    attach)
        echo "Attaching to screen session... (Press Ctrl+A, then D to detach)"
        screen -r $SESSION_NAME
        ;;
    *)
        echo "Usage: ./manage-local-connection.sh [start|stop|restart|info|attach]"
        exit 1
        ;;
esac