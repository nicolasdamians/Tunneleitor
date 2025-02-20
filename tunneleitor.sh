#!/bin/bash

# Variables iniciales
LOGFILE="ssh_tunnels.log"
REPORTFILE="ssh_tunnels_report.txt"
PIDFILE="ssh_tunnels_pids.txt"
LOCKFILE="/tmp/ssh_tunnels.lock"
START_PORT=10000  # Starting port range for forward tunnels

# Función para verificar si un puerto local está libre
is_port_free() {
    local port=$1
    if ss -tuln | grep -q ":$port "; then
        return 1  # Port is in use
    fi
    return 0  # Port is free
}

# Función para encontrar un puerto local único (usado solo para forward tunnels)
find_unique_local_port() {
    local base_port=$START_PORT
    local dest_ip=$1
    local dest_port=$2
    local attempt=0

    while [[ $attempt -lt 1000 ]]; do
        local current_port=$((base_port + attempt))
        if is_port_free "$current_port" && ! grep -q "Local $current_port ->" "$REPORTFILE" 2>/dev/null; then
            echo "$current_port"
            return 0
        fi
        ((attempt++))
    done

    echo "Error: No se pudo encontrar un puerto libre" >&2
    exit 1
}

# Verificar si el script ya está en ejecución
if [[ -e "$LOCKFILE" ]]; then
    echo "Error: El script ya está en ejecución. Elimine $LOCKFILE si esto es un error."
    exit 1
fi
touch "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

# Modo: detener túneles
if [[ "$1" == "stop" ]]; then
    if [[ -f "$PIDFILE" ]]; then
        echo "Deteniendo túneles SSH..."
        while read -r pid; do
            if [[ -n "$pid" ]] && kill -0 "$pid" &>/dev/null; then
                kill "$pid"  # Intentar cierre graceful
                sleep 1
                kill -9 "$pid" 2>/dev/null  # Forzar si es necesario
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

# Validar dependencias
if ! command -v ss >/dev/null 2>&1; then
    echo "Error: 'ss' no está instalado. Instálelo para continuar."
    exit 1
fi

# Solicitar datos al usuario con validación
while true; do
    read -p "IP del host de destino: " DEST_IP
    if [[ "$DEST_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        break
    else
        echo "Error: Ingrese una IP válida (ejemplo: 192.168.1.1)"
    fi
done

read -p "Host intermediario (salto): " JUMP_HOST
if [[ -z "$JUMP_HOST" ]]; then
    echo "Error: El host intermediario no puede estar vacío"
    exit 1
fi

read -p "¿Usar clave SSH? (s/n): " USE_SSH_KEY
if [[ "$USE_SSH_KEY" =~ ^[sS]$ ]]; then
    while true; do
        read -p "Ruta de la clave SSH: " SSH_KEY
        if [[ -f "$SSH_KEY" ]]; then
            break
        else
            echo "Error: Archivo no encontrado. Ingrese una ruta válida."
        fi
    done
else
    echo "Advertencia: Usar contraseñas es menos seguro. Considere claves SSH."
    read -p "Usuario SSH: " SSH_USER
    if [[ -z "$SSH_USER" ]]; then
        echo "Error: El usuario no puede estar vacío"
        exit 1
    fi
    read -s -p "Contraseña SSH: " SSH_PASS
    echo
    if ! command -v sshpass >/dev/null 2>&1; then
        echo "Error: 'sshpass' no está instalado. Instálelo o use una clave SSH."
        exit 1
    fi
fi

while true; do
    read -p "¿Tipo de túnel? (1: Forward / 2: Reverse): " TUNNEL_TYPE
    if [[ "$TUNNEL_TYPE" == "1" || "$TUNNEL_TYPE" == "2" ]]; then
        break
    else
        echo "Error: Ingrese 1 para Forward o 2 para Reverse"
    fi
done

# Preparar archivos de log, reporte y PIDs (append en lugar de overwrite)
echo "Log de túneles SSH - $(date)" >> "$LOGFILE"
echo "Reporte de túneles SSH - $(date)" >> "$REPORTFILE"
[[ -f "$PIDFILE" ]] || > "$PIDFILE"

# Configurar túneles
if [[ "$TUNNEL_TYPE" == "1" ]]; then
    while true; do
        read -p "Puertos remotos a redirigir (separados por comas, ej: 80,443): " REMOTE_PORTS
        IFS=',' read -ra PORTS <<< "$REMOTE_PORTS"
        valid=true
        for port in "${PORTS[@]}"; do
            if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
                echo "Error: '$port' no es un puerto válido (1-65535)"
                valid=false
                break
            fi
        done
        [[ "$valid" == true ]] && break
    done

    for REMOTE_PORT in "${PORTS[@]}"; do
        LOCAL_PORT=$(find_unique_local_port "$DEST_IP" "$REMOTE_PORT")
        
        if [[ "$USE_SSH_KEY" =~ ^[sS]$ ]]; then
            SSH_CMD="ssh -i $SSH_KEY -L ${LOCAL_PORT}:${DEST_IP}:${REMOTE_PORT} $JUMP_HOST -N"
        else
            SSH_CMD="sshpass -p $SSH_PASS ssh -L ${LOCAL_PORT}:${DEST_IP}:${REMOTE_PORT} ${SSH_USER}@${JUMP_HOST} -N"
        fi

        $SSH_CMD -f
        PID=$!
        sleep 2  # Esperar para verificar si el túnel se establece
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
    while true; do
        read -p "Puertos locales a recibir conexión (separados por comas, ej: 8080,22): " LOCAL_PORTS
        IFS=',' read -ra PORTS <<< "$LOCAL_PORTS"
        valid=true
        for port in "${PORTS[@]}"; do
            if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
                echo "Error: '$port' no es un puerto válido (1-65535)"
                valid=false
                break
            fi
        done
        [[ "$valid" == true ]] && break
    done

    for LOCAL_PORT in "${PORTS[@]}"; do
        while true; do
            read -p "Puerto en el jump host para el túnel reverso ${LOCAL_PORT}: " JUMP_HOST_PORT
            if [[ "$JUMP_HOST_PORT" =~ ^[0-9]+$ ]] && [[ "$JUMP_HOST_PORT" -ge 1 ]] && [[ "$JUMP_HOST_PORT" -le 65535 ]]; then
                break
            else
                echo "Error: Ingrese un puerto válido (1-65535)"
            fi
        done
        
        if [[ "$USE_SSH_KEY" =~ ^[sS]$ ]]; then
            SSH_CMD="ssh -i $SSH_KEY -R ${JUMP_HOST_PORT}:localhost:${LOCAL_PORT} $JUMP_HOST -N"
        else
            SSH_CMD="sshpass -p $SSH_PASS ssh -R ${JUMP_HOST_PORT}:localhost:${LOCAL_PORT} ${SSH_USER}@${JUMP_HOST} -N"
        fi

        $SSH_CMD -f
        PID=$!
        sleep 2
        if kill -0 "$PID" &>/dev/null; then
            echo "$PID" >> "$PIDFILE"
            echo "Túnel reverso creado: Jump ${JUMP_HOST_PORT} -> Local ${LOCAL_PORT}" | tee -a "$LOGFILE"
            echo "Jump ${JUMP_HOST_PORT} -> Local ${LOCAL_PORT}" >> "$REPORTFILE"
        else
            echo "Error: No se pudo crear el túnel reverso para ${LOCAL_PORT}" | tee -a "$LOGFILE"
            exit 1
        fi
    done
fi

# Mostrar resumen al usuario
echo "Túneles configurados. Revisa el archivo de reporte: $REPORTFILE"
