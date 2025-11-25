#!/bin/bash
# Filename: 00-init.sh

CONFIG_FILE="config.env"

# Function to prompt for input if not set
ask_var() {
    local var_name=$1
    local prompt_text=$2
    local default_val=$3
    
    # If variable is already set in current shell, use it
    if [ -n "${!var_name}" ]; then
        return
    fi

    read -p "$prompt_text [$default_val]: " input_val
    if [ -z "$input_val" ]; then
        eval "$var_name=\"$default_val\""
    else
        eval "$var_name=\"$input_val\""
    fi
}

echo "=================================================================="
echo "INITIALIZATION & CONFIGURATION"
echo "=================================================================="

if [ -f "$CONFIG_FILE" ]; then
    echo "Loading existing configuration from $CONFIG_FILE..."
    source "$CONFIG_FILE"
else
    echo "Creating new configuration..."
    
    ask_var ZO_ROOT_EMAIL "Enter OpenObserve Root Email" "admin@example.com"
    ask_var ZO_ROOT_PASSWORD "Enter OpenObserve Root Password" "ComplexPassword123!"
    ask_var MINIO_ROOT_USER "Enter MinIO Root User" "minioadmin"
    ask_var MINIO_ROOT_PASSWORD "Enter MinIO Root Password" "MinioPassword123!"
    ask_var ORG_TEAM "Enter Team Organization Name" "observability_team"
    ask_var ORG_PLATFORM "Enter Platform Organization Name" "observability_platform"

    # Save to file
    cat <<EOF > "$CONFIG_FILE"
# Auto-generated config
export ZO_ROOT_EMAIL="$ZO_ROOT_EMAIL"
export ZO_ROOT_PASSWORD="$ZO_ROOT_PASSWORD"
export MINIO_ROOT_USER="$MINIO_ROOT_USER"
export MINIO_ROOT_PASSWORD="$MINIO_ROOT_PASSWORD"
export ORG_TEAM="$ORG_TEAM"
export ORG_PLATFORM="$ORG_PLATFORM"
EOF
    echo "Configuration saved to $CONFIG_FILE"
fi

# Export common aliases function to be used by sourcing scripts
# Note: Aliases don't propagate to subshells easily, so we define a setup function
setup_env() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
    
    shopt -s expand_aliases
    alias lk='microk8s kubectl'
    alias lhelm='microk8s helm3'
    
    # Colors
    GREEN='\033[0;32m'
    BLUE='\033[0;34m'
    RED='\033[0;31m'
    NC='\033[0m'
}

log() { echo -e "\033[0;34m[$(date +'%H:%M:%S')] $1\033[0m"; }
success() { echo -e "\033[0;32m[SUCCESS] $1\033[0m"; }
error() { echo -e "\033[0;31m[ERROR] $1\033[0m"; }

# Check dependencies
check_deps() {
    if ! command -v jq &> /dev/null; then
        echo "Error: jq is not installed. Please run: sudo apt install jq (or brew install jq)"
        exit 1
    fi
}