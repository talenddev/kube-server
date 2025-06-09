#!/bin/bash

# Script: install-minio-nessie.sh
# Purpose: Install and configure MinIO object storage and Nessie data catalog using Docker
# Author: Server Automation Library
# Date: 2025-01-09
# Version: 1.0

# Documentation
# =============
# Description:
#   Installs MinIO (S3-compatible object storage) and Nessie (data catalog)
#   using Docker containers with persistent storage and secure configuration.
#
# Dependencies:
#   - Docker: Container runtime
#   - docker-compose: For orchestrating containers
#   - curl: For health checks
#   - openssl: For generating secure passwords
#
# System Requirements:
#   - Supported OS: Ubuntu 20.04+, Debian 10+, CentOS 8+, RHEL 8+
#   - Required packages: docker, docker-compose
#   - Minimum RAM: 2GB (4GB recommended)
#   - Disk space: 10GB minimum for storage
#
# Configuration Variables:
#   - MINIO_ROOT_USER: MinIO root username (default: minioadmin)
#   - MINIO_ROOT_PASSWORD: MinIO root password (auto-generated if not provided)
#   - MINIO_PORT: MinIO API port (default: 9000)
#   - MINIO_CONSOLE_PORT: MinIO console port (default: 9001)
#   - MINIO_DATA_DIR: MinIO data directory (default: /var/lib/minio/data)
#   - NESSIE_PORT: Nessie API port (default: 19120)
#   - NESSIE_CATALOG: Default catalog name (default: nessie)
#   - POSTGRES_DB: PostgreSQL database for Nessie (default: nessie)
#   - POSTGRES_USER: PostgreSQL user (default: nessie)
#   - POSTGRES_PASSWORD: PostgreSQL password (auto-generated if not provided)
#
# Usage:
#   sudo ./install-minio-nessie.sh [options]
#
# Options:
#   -h, --help              Show this help message
#   -v, --verbose           Enable verbose output
#   --minio-user            MinIO root username
#   --minio-password        MinIO root password (auto-generated if not provided)
#   --minio-port            MinIO API port (default: 9000)
#   --minio-console-port    MinIO console port (default: 9001)
#   --nessie-port           Nessie API port (default: 19120)
#   --data-dir              Base data directory for storage
#
# Examples:
#   sudo ./install-minio-nessie.sh
#   sudo ./install-minio-nessie.sh --minio-user admin --minio-password secretpass
#   sudo ./install-minio-nessie.sh --data-dir /data/storage
#
# Post-Installation:
#   1. MinIO Console: http://localhost:9001
#   2. MinIO API: http://localhost:9000
#   3. Nessie API: http://localhost:19120/api/v1
#   4. Docker logs: docker-compose logs -f
#   5. Stop services: docker-compose down
#   6. Start services: docker-compose up -d

set -euo pipefail

# Script variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="/var/log/minio-nessie-install.log"
VERBOSE=false

# Service configuration
MINIO_ROOT_USER="minioadmin"
MINIO_ROOT_PASSWORD=""
MINIO_PORT=9000
MINIO_CONSOLE_PORT=9001
NESSIE_PORT=19120
NESSIE_CATALOG="nessie"
POSTGRES_DB="nessie"
POSTGRES_USER="nessie"
POSTGRES_PASSWORD=""
DATA_BASE_DIR="/var/lib"
MINIO_DATA_DIR="${DATA_BASE_DIR}/minio/data"
POSTGRES_DATA_DIR="${DATA_BASE_DIR}/postgres/data"
COMPOSE_FILE="/opt/minio-nessie/docker-compose.yml"

# Source common functions
source "${PARENT_DIR}/utilities/common-functions.sh"

# Additional functions specific to this installation
create_docker_network() {
    log "INFO" "Creating Docker network for services..."
    
    if ! docker network inspect minio-nessie &>/dev/null; then
        docker network create minio-nessie
        log "INFO" "Docker network 'minio-nessie' created"
    else
        log "INFO" "Docker network 'minio-nessie' already exists"
    fi
}

generate_passwords() {
    if [[ -z "$MINIO_ROOT_PASSWORD" ]]; then
        MINIO_ROOT_PASSWORD=$(generate_password 32)
        log "INFO" "Generated MinIO root password"
    fi
    
    if [[ -z "$POSTGRES_PASSWORD" ]]; then
        POSTGRES_PASSWORD=$(generate_password 25)
        log "INFO" "Generated PostgreSQL password for Nessie"
    fi
}

create_directories() {
    log "INFO" "Creating data directories..."
    
    # Create directories with proper permissions
    ensure_directory "${MINIO_DATA_DIR}" 1000 1000 755
    ensure_directory "${POSTGRES_DATA_DIR}" 999 999 700
    ensure_directory "/opt/minio-nessie" root root 755
    
    log "INFO" "Data directories created"
}

create_docker_compose() {
    log "INFO" "Creating Docker Compose configuration..."
    
    cat > "$COMPOSE_FILE" << EOF
version: '3.8'

services:
  minio:
    image: minio/minio:latest
    container_name: minio
    restart: unless-stopped
    ports:
      - "${MINIO_PORT}:9000"
      - "${MINIO_CONSOLE_PORT}:9001"
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD}
    volumes:
      - ${MINIO_DATA_DIR}:/data
    command: server /data --console-address ":9001"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
      interval: 30s
      timeout: 20s
      retries: 3
    networks:
      - minio-nessie

  postgres:
    image: postgres:15-alpine
    container_name: nessie-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - ${POSTGRES_DATA_DIR}:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 30s
      timeout: 20s
      retries: 3
    networks:
      - minio-nessie

  nessie:
    image: projectnessie/nessie:latest
    container_name: nessie
    restart: unless-stopped
    ports:
      - "${NESSIE_PORT}:19120"
    environment:
      NESSIE_VERSION_STORE_TYPE: JDBC
      QUARKUS_DATASOURCE_DB_KIND: postgresql
      QUARKUS_DATASOURCE_USERNAME: ${POSTGRES_USER}
      QUARKUS_DATASOURCE_PASSWORD: ${POSTGRES_PASSWORD}
      QUARKUS_DATASOURCE_JDBC_URL: jdbc:postgresql://postgres:5432/${POSTGRES_DB}
      NESSIE_CATALOG_DEFAULT_WAREHOUSE: s3://warehouse
      NESSIE_CATALOG_SERVICE_S3_DEFAULT_OPTIONS_ENDPOINT: http://minio:9000
      NESSIE_CATALOG_SERVICE_S3_DEFAULT_OPTIONS_PATH_STYLE_ACCESS: "true"
      NESSIE_CATALOG_SERVICE_S3_DEFAULT_OPTIONS_ACCESS_KEY: ${MINIO_ROOT_USER}
      NESSIE_CATALOG_SERVICE_S3_DEFAULT_OPTIONS_SECRET_KEY: ${MINIO_ROOT_PASSWORD}
    depends_on:
      postgres:
        condition: service_healthy
      minio:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:19120/api/v2/config"]
      interval: 30s
      timeout: 20s
      retries: 3
    networks:
      - minio-nessie

networks:
  minio-nessie:
    external: true
EOF

    chmod 644 "$COMPOSE_FILE"
    log "INFO" "Docker Compose configuration created"
}

create_minio_init_script() {
    log "INFO" "Creating MinIO initialization script..."
    
    cat > /opt/minio-nessie/init-minio.sh << EOF
#!/bin/bash
# MinIO initialization script

# Wait for MinIO to be ready
echo "Waiting for MinIO to be ready..."
until curl -sf http://localhost:${MINIO_PORT}/minio/health/live; do
    sleep 2
done

# Configure MinIO client
export MC_HOST_minio=http://${MINIO_ROOT_USER}:${MINIO_ROOT_PASSWORD}@localhost:${MINIO_PORT}

# Create warehouse bucket for Nessie
docker run --rm --network minio-nessie \\
    -e MC_HOST_minio=http://${MINIO_ROOT_USER}:${MINIO_ROOT_PASSWORD}@minio:9000 \\
    minio/mc mb minio/warehouse || true

# Set bucket policy
docker run --rm --network minio-nessie \\
    -e MC_HOST_minio=http://${MINIO_ROOT_USER}:${MINIO_ROOT_PASSWORD}@minio:9000 \\
    minio/mc policy set public minio/warehouse || true

echo "MinIO initialization completed"
EOF

    chmod +x /opt/minio-nessie/init-minio.sh
    log "INFO" "MinIO initialization script created"
}

start_services() {
    log "INFO" "Starting services..."
    
    cd /opt/minio-nessie
    
    # Start services
    docker-compose up -d
    
    # Wait for services to be ready
    log "INFO" "Waiting for services to start..."
    sleep 10
    
    # Initialize MinIO
    log "INFO" "Initializing MinIO..."
    /opt/minio-nessie/init-minio.sh
    
    log "INFO" "Services started successfully"
}

verify_installation() {
    log "INFO" "Verifying installation..."
    
    # Check MinIO
    if curl -sf http://localhost:${MINIO_PORT}/minio/health/live; then
        log "INFO" "MinIO is running and healthy"
    else
        error_exit "MinIO health check failed"
    fi
    
    # Check Nessie
    if curl -sf http://localhost:${NESSIE_PORT}/api/v2/config; then
        log "INFO" "Nessie is running and healthy"
    else
        error_exit "Nessie health check failed"
    fi
    
    # Check containers
    local running_containers=$(docker-compose -f "$COMPOSE_FILE" ps --services --filter "status=running" | wc -l)
    if [[ $running_containers -eq 3 ]]; then
        log "INFO" "All containers are running"
    else
        error_exit "Not all containers are running (expected 3, found $running_containers)"
    fi
    
    log "INFO" "Installation verified successfully"
}

create_management_scripts() {
    log "INFO" "Creating management scripts..."
    
    # Create status script
    cat > /usr/local/bin/minio-nessie-status << EOF
#!/bin/bash
cd /opt/minio-nessie
docker-compose ps
echo ""
echo "MinIO Console: http://localhost:${MINIO_CONSOLE_PORT}"
echo "MinIO API: http://localhost:${MINIO_PORT}"
echo "Nessie API: http://localhost:${NESSIE_PORT}/api/v1"
EOF
    chmod +x /usr/local/bin/minio-nessie-status
    
    # Create stop script
    cat > /usr/local/bin/minio-nessie-stop << EOF
#!/bin/bash
cd /opt/minio-nessie
docker-compose down
EOF
    chmod +x /usr/local/bin/minio-nessie-stop
    
    # Create start script
    cat > /usr/local/bin/minio-nessie-start << EOF
#!/bin/bash
cd /opt/minio-nessie
docker-compose up -d
EOF
    chmod +x /usr/local/bin/minio-nessie-start
    
    # Create logs script
    cat > /usr/local/bin/minio-nessie-logs << EOF
#!/bin/bash
cd /opt/minio-nessie
docker-compose logs -f "\$@"
EOF
    chmod +x /usr/local/bin/minio-nessie-logs
    
    log "INFO" "Management scripts created"
}

save_credentials() {
    local creds_file="/root/.minio-nessie-credentials"
    
    cat > "$creds_file" << EOF
# MinIO and Nessie Installation Credentials
# Generated on $(date)

## MinIO Credentials
MinIO Root User: ${MINIO_ROOT_USER}
MinIO Root Password: ${MINIO_ROOT_PASSWORD}
MinIO API URL: http://localhost:${MINIO_PORT}
MinIO Console URL: http://localhost:${MINIO_CONSOLE_PORT}

## Nessie Configuration
Nessie API URL: http://localhost:${NESSIE_PORT}/api/v1
Nessie Catalog: ${NESSIE_CATALOG}

## PostgreSQL (Nessie Backend)
PostgreSQL Database: ${POSTGRES_DB}
PostgreSQL User: ${POSTGRES_USER}
PostgreSQL Password: ${POSTGRES_PASSWORD}

## S3 Configuration for Applications
Endpoint: http://localhost:${MINIO_PORT}
Access Key: ${MINIO_ROOT_USER}
Secret Key: ${MINIO_ROOT_PASSWORD}
Path Style Access: true
Default Bucket: warehouse

## Management Commands
Status: minio-nessie-status
Logs: minio-nessie-logs
Stop: minio-nessie-stop
Start: minio-nessie-start

## Example MinIO Client Usage
docker run --rm -it --network host \\
  -e MC_HOST_minio=http://${MINIO_ROOT_USER}:${MINIO_ROOT_PASSWORD}@localhost:${MINIO_PORT} \\
  minio/mc ls minio/
EOF

    chmod 600 "$creds_file"
    log "INFO" "Credentials saved to $creds_file"
}

usage() {
    grep "^#" "$0" | grep -E "^# (Usage|Options|Examples):" -A 20 | grep -E "^#( |$)" | sed 's/^# //'
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --minio-user)
                MINIO_ROOT_USER="$2"
                shift 2
                ;;
            --minio-password)
                MINIO_ROOT_PASSWORD="$2"
                shift 2
                ;;
            --minio-port)
                MINIO_PORT="$2"
                shift 2
                ;;
            --minio-console-port)
                MINIO_CONSOLE_PORT="$2"
                shift 2
                ;;
            --nessie-port)
                NESSIE_PORT="$2"
                shift 2
                ;;
            --data-dir)
                DATA_BASE_DIR="$2"
                MINIO_DATA_DIR="${DATA_BASE_DIR}/minio/data"
                POSTGRES_DATA_DIR="${DATA_BASE_DIR}/postgres/data"
                shift 2
                ;;
            *)
                error_exit "Unknown option: $1"
                ;;
        esac
    done
}

main() {
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    
    log "INFO" "Starting MinIO and Nessie installation"
    
    parse_args "$@"
    check_root
    detect_os
    check_system_requirements 2048 10
    
    # Check Docker installation
    if ! command -v docker &>/dev/null; then
        log "INFO" "Docker not found. Installing Docker..."
        "${PARENT_DIR}/utilities/install-docker.sh"
    fi
    
    # Install docker-compose if not present
    if ! command -v docker-compose &>/dev/null; then
        log "INFO" "Installing docker-compose..."
        install_packages curl
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    fi
    
    generate_passwords
    create_docker_network
    create_directories
    create_docker_compose
    create_minio_init_script
    start_services
    verify_installation
    create_management_scripts
    save_credentials
    
    log "INFO" "MinIO and Nessie installation completed successfully"
    
    echo -e "\n${GREEN}Installation Summary:${NC}"
    echo "- MinIO object storage installed and running"
    echo "  - API: http://localhost:${MINIO_PORT}"
    echo "  - Console: http://localhost:${MINIO_CONSOLE_PORT}"
    echo "- Nessie data catalog installed and running"
    echo "  - API: http://localhost:${NESSIE_PORT}/api/v1"
    echo "- Data directories:"
    echo "  - MinIO: ${MINIO_DATA_DIR}"
    echo "  - PostgreSQL: ${POSTGRES_DATA_DIR}"
    echo "- Configuration: /opt/minio-nessie/docker-compose.yml"
    echo "- Credentials saved to: /root/.minio-nessie-credentials"
    echo ""
    echo "Management commands:"
    echo "  - minio-nessie-status: Check service status"
    echo "  - minio-nessie-logs: View service logs"
    echo "  - minio-nessie-stop: Stop all services"
    echo "  - minio-nessie-start: Start all services"
}

main "$@"