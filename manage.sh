#!/bin/bash

CMD=$1

# Helper to find a free port or kill existing process on that port
cleanup_port() {
    local PORT=$1
    PID=$(lsof -ti :$PORT)
    if [ -n "$PID" ]; then
        echo "Killing existing process $PID on port $PORT"
        kill -9 $PID
    fi
}

start_pf() {
    echo "=================================================================="
    echo "STARTING PORT FORWARDS"
    echo "=================================================================="
    
    # 1. ArgoCD
    cleanup_port 8443
    echo "Starting ArgoCD (8443)..."
    nohup kubectl port-forward svc/argocd-server -n argocd 8443:443 > /dev/null 2>&1 &
    
    # 2. OpenObserve
    cleanup_port 5080
    echo "Starting OpenObserve (5080)..."
    nohup kubectl port-forward svc/openobserve-router -n openobserve-system 5080:5080 > /dev/null 2>&1 &
    
    # 3. MinIO
    cleanup_port 9001
    echo "Starting MinIO Console (9001)..."
    nohup kubectl port-forward svc/minio-console -n minio-system 9001:9001 > /dev/null 2>&1 &
    
    echo "Done. Running in background."
}

stop_pf() {
    echo "Stopping all kubectl port-forwards..."
    pkill -f "kubectl port-forward"
    echo "Stopped."
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

    printf "%-15s | %-25s | %-20s | %s\n" "Service" "URL" "User" "Password"
    echo "------------------------------------------------------------------------------------------------"
    printf "%-15s | %-25s | %-20s | %s\n" "ArgoCD" "https://127.0.0.1:8443" "admin" "$ARGO_PASS"
    printf "%-15s | %-25s | %-20s | %s\n" "OpenObserve" "http://127.0.0.1:5080" "$ZO_USER" "$ZO_PASS"
    printf "%-15s | %-25s | %-20s | %s\n" "MinIO" "http://127.0.0.1:9001" "$MINIO_USER" "$MINIO_PASS"
    echo "=================================================================="
    echo ""
}

case "$CMD" in
    start)
        start_pf
        ;;
    stop)
        stop_pf
        ;;
    info)
        show_info
        ;;
    restart)
        stop_pf
        sleep 1
        start_pf
        show_info
        ;;
    *)
        echo "Usage: ./manage.sh [start|stop|restart|info]"
        exit 1
        ;;
esac