#!/bin/bash
set -euo pipefail

# ----------------------------
# Global Variables & Files
# ----------------------------
LOGFILE="ssh_tunnels.log"
REPORTFILE="ssh_tunnels_report.txt"
PIDFILE="ssh_tunnels_pids.txt"
LOCKFILE="/tmp/ssh_tunnels.lock"
START_PORT=10000  # Starting port for forward tunnels

# ----------------------------
# Functions
# ----------------------------

# Check if a given port is free (using ss)
is_port_free() {
    local port=$1
    if ss -tuln | grep -q ":${port}[[:space:]]"; then
        return 1  # Port is in use
    fi
    return 0  # Port is free
}

# Find a unique free local port for forward tunnels
find_unique_local_port() {
    local attempt=0
    while [[ $attempt -lt 1000 ]]; do
        local current_port=$((START_PORT + attempt))
        if is_port_free "$current_port" && ! grep -q "Local $current_port ->" "$REPORTFILE" 2>/dev/null; then
            echo "$current_port"
            return 0
        fi
        ((attempt++))
    done
    echo "Error: No free port found" >&2
    exit 1
}

# Cleanup LOCKFILE on exit
cleanup_lock() {
    rm -f "$LOCKFILE"
}
trap cleanup_lock EXIT

# ----------------------------
# Ensure Single Instance
# ----------------------------
if [[ -e "$LOCKFILE" ]]; then
    echo "Error: Script is already running. Remove $LOCKFILE if this is not the case."
    exit 1
fi
touch "$LOCKFILE"

# ----------------------------
# Stop Mode: Kill Existing Tunnels
# ----------------------------
if [[ "${1:-}" == "stop" ]]; then
    if [[ -f "$PIDFILE" ]]; then
        echo "Stopping SSH tunnels..."
        while read -r pid; do
            if [[ -n "$pid" ]] && kill -0 "$pid" &>/dev/null; then
                kill "$pid"    # Graceful kill
                sleep 1
                kill -9 "$pid" 2>/dev/null  # Force if needed
                echo "Stopped tunnel with PID $pid."
            fi
        done < "$PIDFILE"
        rm -f "$PIDFILE"
        echo "All tunnels stopped."
    else
        echo "No active tunnel PID file found."
    fi
    exit 0
fi

# ----------------------------
# Dependency Checks
# ----------------------------
for cmd in ss ssh; do
    command -v "$cmd" &>/dev/null || { echo "Error: '$cmd' is not installed."; exit 1; }
done

# ----------------------------
# User Input Section
# ----------------------------
# Prompt for destination IP (validate IPv4)
while true; do
    read -rp "Enter destination host IP: " DEST_IP
    if [[ "$DEST_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        break
    else
        echo "Please enter a valid IPv4 address (e.g., 192.168.1.1)."
    fi
done

# Get the jump host
read -rp "Enter jump host: " JUMP_HOST
if [[ -z "$JUMP_HOST" ]]; then
    echo "Error: Jump host cannot be empty."
    exit 1
fi

# Choose authentication: SSH key or password?
read -rp "Use SSH key? (s/n): " USE_SSH_KEY
if [[ "$USE_SSH_KEY" =~ ^[sS]$ ]]; then
    while true; do
        read -rp "Enter path to SSH key: " SSH_KEY
        if [[ -f "$SSH_KEY" ]]; then
            break
        else
            echo "SSH key not found. Try again."
        fi
    done
else
    echo "Using password (less secure)."
    read -rp "Enter SSH username: " SSH_USER
    if [[ -z "$SSH_USER" ]]; then
        echo "Error: Username cannot be empty."
        exit 1
    fi
    read -rs -rp "Enter SSH password: " SSH_PASS
    echo
    command -v sshpass &>/dev/null || { echo "Error: sshpass is required for password mode."; exit 1; }
fi

# Choose tunnel type: Forward (1) or Reverse (2)
while true; do
    read -rp "Select tunnel type (1: Forward, 2: Reverse): " TUNNEL_TYPE
    if [[ "$TUNNEL_TYPE" == "1" || "$TUNNEL_TYPE" == "2" ]]; then
        break
    else
        echo "Invalid selection. Enter 1 for Forward or 2 for Reverse."
    fi
done

# For forward tunnels, ask for remote ports (comma separated)
if [[ "$TUNNEL_TYPE" == "1" ]]; then
    while true; do
        read -rp "Enter remote ports to forward (e.g., 80,443): " REMOTE_PORTS
        IFS=',' read -r -a PORTS <<< "$REMOTE_PORTS"
        valid=true
        for port in "${PORTS[@]}"; do
            if ! [[ "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
                echo "Invalid port: $port. Must be between 1 and 65535."
                valid=false
                break
            fi
        done
        $valid && break
    done
else
    # For reverse tunnels, ask for local ports
    while true; do
        read -rp "Enter local ports to expose (comma separated, e.g., 8080,22): " LOCAL_PORTS
        IFS=',' read -r -a PORTS <<< "$LOCAL_PORTS"
        valid=true
        for port in "${PORTS[@]}"; do
            if ! [[ "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
                echo "Invalid port: $port. Must be between 1 and 65535."
                valid=false
                break
            fi
        done
        $valid && break
    done
fi

# ----------------------------
# Prepare Log/Report/PID Files
# ----------------------------
echo "SSH Tunnels Log - $(date)" >> "$LOGFILE"
echo "SSH Tunnels Report - $(date)" >> "$REPORTFILE"
: > "$PIDFILE"  # Truncate PID file

# ----------------------------
# Tunnel Creation
# ----------------------------
if [[ "$TUNNEL_TYPE" == "1" ]]; then
    # Forward Tunnel Mode
    for REMOTE_PORT in "${PORTS[@]}"; do
        LOCAL_PORT=$(find_unique_local_port "$DEST_IP" "$REMOTE_PORT")
        if [[ "$USE_SSH_KEY" =~ ^[sS]$ ]]; then
            SSH_CMD=(ssh -i "$SSH_KEY" -o ExitOnForwardFailure=yes -L "${LOCAL_PORT}:${DEST_IP}:${REMOTE_PORT}" "$JUMP_HOST" -N)
        else
            SSH_CMD=(sshpass -p "$SSH_PASS" ssh -o ExitOnForwardFailure=yes -L "${LOCAL_PORT}:${DEST_IP}:${REMOTE_PORT}" "${SSH_USER}@${JUMP_HOST}" -N)
        fi
        # Run tunnel in background
        "${SSH_CMD[@]}" &
        PID=$!
        sleep 2
        if kill -0 "$PID" &>/dev/null; then
            echo "$PID" >> "$PIDFILE"
            echo "Tunnel created: Local ${LOCAL_PORT} -> ${DEST_IP}:${REMOTE_PORT}" | tee -a "$LOGFILE"
            echo "Local ${LOCAL_PORT} -> Remote ${DEST_IP}:${REMOTE_PORT}" >> "$REPORTFILE"
        else
            echo "Error: Failed to establish tunnel for remote port ${REMOTE_PORT}." | tee -a "$LOGFILE"
            exit 1
        fi
    done
elif [[ "$TUNNEL_TYPE" == "2" ]]; then
    # Reverse Tunnel Mode
    for LOCAL_PORT in "${PORTS[@]}"; do
        while true; do
            read -rp "Enter jump host port for reverse tunnel corresponding to local port ${LOCAL_PORT}: " JUMP_HOST_PORT
            if [[ "$JUMP_HOST_PORT" =~ ^[0-9]+$ ]] && (( JUMP_HOST_PORT >= 1 && JUMP_HOST_PORT <= 65535 )); then
                break
            else
                echo "Invalid port. Please enter a number between 1 and 65535."
            fi
        done
        if [[ "$USE_SSH_KEY" =~ ^[sS]$ ]]; then
            SSH_CMD=(ssh -i "$SSH_KEY" -o ExitOnForwardFailure=yes -R "${JUMP_HOST_PORT}:localhost:${LOCAL_PORT}" "$JUMP_HOST" -N)
        else
            SSH_CMD=(sshpass -p "$SSH_PASS" ssh -o ExitOnForwardFailure=yes -R "${JUMP_HOST_PORT}:localhost:${LOCAL_PORT}" "${SSH_USER}@${JUMP_HOST}" -N)
        fi
        "${SSH_CMD[@]}" &
        PID=$!
        sleep 2
        if kill -0 "$PID" &>/dev/null; then
            echo "$PID" >> "$PIDFILE"
            echo "Reverse tunnel created: Jump ${JUMP_HOST_PORT} -> Local ${LOCAL_PORT}" | tee -a "$LOGFILE"
            echo "Jump ${JUMP_HOST_PORT} -> Local ${LOCAL_PORT}" >> "$REPORTFILE"
        else
            echo "Error: Failed to establish reverse tunnel for local port ${LOCAL_PORT}." | tee -a "$LOGFILE"
            exit 1
        fi
    done
fi

echo "Tunnels configured. See report: $REPORTFILE"
