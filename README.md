# Tunneleitor

**Tunneleitor** is a Bash script designed to automate the creation and management of SSH tunnels, including both **forwarding** and **reverse** tunneling. It simplifies the process of creating multiple SSH tunnels, ensuring no port conflicts, tracking tunnel processes, and logging activities for easy management.

## Features

- **Forwarding Tunnels**: Forward ports from your local machine to a remote server.
- **Reverse Tunnels**: Forward ports from a remote machine back to your local machine.
- **Port Availability Check**: Automatically checks if ports are free to avoid conflicts.
- **PID Management**: Tracks active tunnels and allows for stopping them when needed.
- **Logging and Reporting**: Keeps detailed logs and generates a report on active tunnels.

## Prerequisites

- **ssh**: The SSH client must be installed on your machine.
- **ss**: Used to check if ports are free.
- **sshpass** (optional): For password-based SSH authentication.
- A remote jump host or gateway server for tunneling.

## Installation

1. Clone the repository to your local machine:
   ```bash
   git clone https://github.com/yourusername/tunneleitor.git
   cd tunneleitor
   ```

2. Make the script executable:
   ```bash
   chmod +x tunneleitor.sh
   ```

3. (Optional) If you want to use password-based authentication, install `sshpass`:
   ```bash
   sudo apt-get install sshpass
   ```

## Usage

### 1. Running the Script to Create Tunnels

You can create SSH tunnels either by forwarding or reverse tunneling. The script will prompt you for necessary inputs such as the destination IP, jump host, authentication method, and tunnel type.

#### Example for Forwarding Tunnel (Local -> Remote):

```bash
./tunneleitor.sh
```

- **Tunnel Type**: Select `1` for a forward tunnel.
- **Remote Ports**: Enter the ports to be forwarded (comma-separated).

#### Example for Reverse Tunnel (Remote -> Local):

```bash
./tunneleitor.sh
```

- **Tunnel Type**: Select `2` for a reverse tunnel.
- **Local Ports**: Enter the ports to receive connections (comma-separated).

### 2. Stopping Active Tunnels

To stop previously created tunnels:

```bash
./tunneleitor.sh stop
```

This will stop all active tunnels and remove their respective PID entries from the `ssh_tunnels_pids.txt` file.

### Parameters Explained:

- **IP del host de destino**: The IP address of the remote server to which you want to forward or receive traffic.
- **Host intermediario (salto)**: The jump host (gateway server) for SSH tunneling.
- **¿Usar clave SSH?**: Choose whether to use an SSH key (`s`) or SSH password-based authentication (`n`).
- **Tipo de túnel**:
  - `1`: Forward Tunnel (Local -> Remote)
  - `2`: Reverse Tunnel (Remote -> Local)
- **Puertos remotos**: Ports on the remote host to forward (for local-to-remote tunnels).
- **Puertos locales**: Ports on the local machine to receive connections (for remote-to-local tunnels).

## Files Generated:

- **ssh_tunnels.log**: A log file containing detailed information about each tunnel created.
- **ssh_tunnels_report.txt**: A report summarizing the configured tunnels.
- **ssh_tunnels_pids.txt**: A file that stores the process IDs (PIDs) of active tunnels for management.

## Example Log Output

- **For Forward Tunnel**: 
  ```
  Túnel creado: Local 10000 -> 192.168.1.100:80
  ```

- **For Reverse Tunnel**:
  ```
  Túnel reverso creado: Remoto 20000 -> Local 30000
  ```

## Requirements

- **sshpass** (Optional, only needed for password-based authentication).
- **ss**: Installed on the system to check available ports.

## Troubleshooting

- **Port conflicts**: The script will automatically check for port availability. If a port is in use, it will try the next available one.
- **SSH Key**: Ensure the path to the SSH key is correct if using key-based authentication.

## Contributing

Contributions are welcome! Feel free to submit issues or pull requests for bug fixes, features, or improvements.
```

