#!/bin/bash

# Variables iniciales
LOGFILE="ssh_tunnels.log"
REPORTFILE="ssh_tunnels_report.txt"
PIDFILE="ssh_tunnels_pids.txt"
START_PORT=10000  # Starting port range

# Función para verificar si un puerto específico está libre
is_port_free() {
    local port=$1
    # Use ss to check port availability
    if ss -tuln | grep -q ":$port "; then
        return 1  # Port is in use
    fi
    return 0  # Port is free
}

# Función para encontrar un puerto local único
find_unique_local_port() {
    local base_port=$START_PORT
    local dest_ip=$1
    local dest_port=$2
    local attempt=0

    while [[ $attempt -lt 1000 ]]; do
        local current_port=$((base_port + attempt))
        
        # Check if port is free
        if is_port_free "$current_port"; then
            # Additional check to ensure no existing tunnel uses this port
            if ! grep -q "Local $current_port ->" "$REPORTFILE" 2>/dev/null; then
                echo "$current_port"
                return
            fi
        fi
        
        ((attempt++))
    done

    echo "Error: Could not find a free port" >&2
    exit 1
}

# Modo: detener túneles
if [[ "$1" == "stop" ]]; then
    if [[ -f "$PIDFILE" ]]; then
        echo "Deteniendo túneles SSH..."
        while read -r pid; do
            if [[ -n "$pid" ]]; then
                kill -9 "$pid" &>/dev/null
                echo "Túnel con PID $pid detenido."
            fi
        done < "$PIDFILE"
        rm -f "$PIDFILE"
        echo "Todos los túneles registrados han sido detenidos."
    else
        echo "No se encontraron túneles activos registrados."
    fi
    exit 0
fi

# Solicitar datos al usuario
read -p "IP del host de destino: " DEST_IP
read -p "Host intermediario (salto): " JUMP_HOST
read -p "¿Usar clave SSH? (s/n): " USE_SSH_KEY
read -p "¿Tipo de túnel? (1: Forward / 2: Reverse): " TUNNEL_TYPE

if [[ "$USE_SSH_KEY" == "s" || "$USE_SSH_KEY" == "S" ]]; then
    read -p "Ruta de la clave SSH: " SSH_KEY
else
    read -p "Usuario SSH: " SSH_USER
    read -s -p "Contraseña SSH: " SSH_PASS
    echo
fi

# Preparar archivos de log, reporte y PIDs
echo "Log de túneles SSH - $(date)" > "$LOGFILE"
echo "Reporte de túneles SSH - $(date)" > "$REPORTFILE"
> "$PIDFILE"

# Configurar túneles
if [[ "$TUNNEL_TYPE" == "1" ]]; then
    read -p "Puertos remotos a redirigir (separados por comas): " REMOTE_PORTS
    IFS=',' read -ra PORTS <<< "$REMOTE_PORTS"
    
    for REMOTE_PORT in "${PORTS[@]}"; do
        LOCAL_PORT=$(find_unique_local_port "$DEST_IP" "$REMOTE_PORT")
        
        # Comando base
        if [[ "$USE_SSH_KEY" == "s" || "$USE_SSH_KEY" == "S" ]]; then
            SSH_CMD="ssh -i $SSH_KEY -L ${LOCAL_PORT}:${DEST_IP}:${REMOTE_PORT} $JUMP_HOST -N"
        else
            SSH_CMD="sshpass -p $SSH_PASS ssh -L ${LOCAL_PORT}:${DEST_IP}:${REMOTE_PORT} ${SSH_USER}@${JUMP_HOST} -N"
        fi

        # Ejecutar comando y capturar PID
        $SSH_CMD &
        PID=$!
        if kill -0 "$PID" &>/dev/null; then
            echo "$PID" >> "$PIDFILE"
            echo "Túnel creado: Local $LOCAL_PORT -> ${DEST_IP}:${REMOTE_PORT}" | tee -a "$LOGFILE"
            echo "Local $LOCAL_PORT -> Remoto ${DEST_IP}:${REMOTE_PORT}" >> "$REPORTFILE"
        else
            echo "Error: No se pudo crear el túnel para ${REMOTE_PORT}" | tee -a "$LOGFILE"
            exit 1
        fi
    done
elif [[ "$TUNNEL_TYPE" == "2" ]]; then
    read -p "Puertos locales a recibir conexión (separados por comas): " LOCAL_PORTS
    IFS=',' read -ra PORTS <<< "$LOCAL_PORTS"
    
    for LOCAL_PORT in "${PORTS[@]}"; do
        REMOTE_PORT=$(find_unique_local_port "$DEST_IP" "$LOCAL_PORT")
        
        # Comando base
        if [[ "$USE_SSH_KEY" == "s" || "$USE_SSH_KEY" == "S" ]]; then
            SSH_CMD="ssh -i $SSH_KEY -R ${REMOTE_PORT}:localhost:${LOCAL_PORT} $JUMP_HOST -N"
        else
            SSH_CMD="sshpass -p $SSH_PASS ssh -R ${REMOTE_PORT}:localhost:${LOCAL_PORT} ${SSH_USER}@${JUMP_HOST} -N"
        fi

        # Ejecutar comando y capturar PID
        $SSH_CMD &
        PID=$!
        if kill -0 "$PID" &>/dev/null; then
            echo "$PID" >> "$PIDFILE"
            echo "Túnel reverso creado: Remoto ${REMOTE_PORT} -> Local ${LOCAL_PORT}" | tee -a "$LOGFILE"
            echo "Remoto ${REMOTE_PORT} -> Local ${LOCAL_PORT}" >> "$REPORTFILE"
        else
            echo "Error: No se pudo crear el túnel reverso para ${LOCAL_PORT}" | tee -a "$LOGFILE"
            exit 1
        fi
    done
else
    echo "Opción no válida. Saliendo."
    exit 1
fi

# Mostrar resumen al usuario
echo "Túneles configurados. Revisa el archivo de reporte: $REPORTFILE"
