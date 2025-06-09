#!/bin/bash

# Script: install-postgres-iceberg.sh
# Purpose: Install and configure PostgreSQL as Iceberg catalog with MinIO object storage using Docker
# Author: Server Automation Library
# Date: 2025-01-09
# Version: 1.0

# Documentation
# =============
# Description:
#   Installs MinIO (S3-compatible object storage) and PostgreSQL as Iceberg catalog
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
#   - POSTGRES_PORT: PostgreSQL port (default: 5432)
#   - POSTGRES_DB: PostgreSQL database for Iceberg (default: iceberg)
#   - POSTGRES_USER: PostgreSQL user (default: iceberg)
#   - POSTGRES_PASSWORD: PostgreSQL password (auto-generated if not provided)
#
# Usage:
#   sudo ./install-postgres-iceberg.sh [options]
#
# Options:
#   -h, --help              Show this help message
#   -v, --verbose           Enable verbose output
#   --minio-user            MinIO root username
#   --minio-password        MinIO root password (auto-generated if not provided)
#   --minio-port            MinIO API port (default: 9000)
#   --minio-console-port    MinIO console port (default: 9001)
#   --postgres-port         PostgreSQL port (default: 5432)
#   --data-dir              Base data directory for storage
#
# Examples:
#   sudo ./install-postgres-iceberg.sh
#   sudo ./install-postgres-iceberg.sh --minio-user admin --minio-password secretpass
#   sudo ./install-postgres-iceberg.sh --data-dir /data/storage
#
# Post-Installation:
#   1. MinIO Console: http://localhost:9001
#   2. MinIO API: http://localhost:9000
#   3. PostgreSQL: localhost:5432
#   4. Docker logs: docker-compose logs -f
#   5. Stop services: docker-compose down
#   6. Start services: docker-compose up -d

set -euo pipefail

# Script variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="/var/log/postgres-iceberg-install.log"
VERBOSE=false

# Service configuration
MINIO_ROOT_USER="minioadmin"
MINIO_ROOT_PASSWORD=""
MINIO_PORT=9000
MINIO_CONSOLE_PORT=9001
POSTGRES_PORT=5432
POSTGRES_DB="iceberg"
POSTGRES_USER="iceberg"
POSTGRES_PASSWORD=""
DATA_BASE_DIR="/var/lib"
MINIO_DATA_DIR="${DATA_BASE_DIR}/minio/data"
POSTGRES_DATA_DIR="${DATA_BASE_DIR}/postgres/data"
COMPOSE_FILE="/opt/postgres-iceberg/docker-compose.yml"

# Source common functions
source "${PARENT_DIR}/utilities/common-functions.sh"

# Additional functions specific to this installation
create_docker_network() {
    log "INFO" "Creating Docker network for services..."
    
    if ! docker network inspect postgres-iceberg &>/dev/null; then
        docker network create postgres-iceberg
        log "INFO" "Docker network 'postgres-iceberg' created"
    else
        log "INFO" "Docker network 'postgres-iceberg' already exists"
    fi
}

generate_passwords() {
    if [[ -z "$MINIO_ROOT_PASSWORD" ]]; then
        MINIO_ROOT_PASSWORD=$(generate_password 32)
        log "INFO" "Generated MinIO root password"
    fi
    
    if [[ -z "$POSTGRES_PASSWORD" ]]; then
        POSTGRES_PASSWORD=$(generate_password 25)
        log "INFO" "Generated PostgreSQL password for Iceberg"
    fi
}

create_directories() {
    log "INFO" "Creating data directories..."
    
    # Create directories with proper permissions
    ensure_directory "${MINIO_DATA_DIR}" 1000 1000 755
    ensure_directory "${POSTGRES_DATA_DIR}" 999 999 700
    ensure_directory "/opt/postgres-iceberg" root root 755
    
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
      - postgres-iceberg

  postgres:
    image: postgres:15-alpine
    container_name: iceberg-postgres
    restart: unless-stopped
    ports:
      - "${POSTGRES_PORT}:5432"
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - ${POSTGRES_DATA_DIR}:/var/lib/postgresql/data
      - ./init-iceberg.sql:/docker-entrypoint-initdb.d/init-iceberg.sql
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 30s
      timeout: 20s
      retries: 3
    networks:
      - postgres-iceberg

networks:
  postgres-iceberg:
    external: true
EOF

    chmod 644 "$COMPOSE_FILE"
    log "INFO" "Docker Compose configuration created"
}

create_iceberg_init_script() {
    log "INFO" "Creating Iceberg catalog initialization script..."
    
    cat > /opt/postgres-iceberg/init-iceberg.sql << 'EOF'
-- Initialize Iceberg catalog tables
-- This script creates the basic schema for Apache Iceberg catalog

-- Create Iceberg catalog tables
CREATE TABLE IF NOT EXISTS iceberg_tables (
    catalog_name VARCHAR(255) NOT NULL,
    table_namespace VARCHAR(255) NOT NULL,
    table_name VARCHAR(255) NOT NULL,
    metadata_location VARCHAR(1000),
    previous_metadata_location VARCHAR(1000),
    PRIMARY KEY (catalog_name, table_namespace, table_name)
);

CREATE TABLE IF NOT EXISTS iceberg_namespace_properties (
    catalog_name VARCHAR(255) NOT NULL,
    namespace VARCHAR(255) NOT NULL,
    property_key VARCHAR(255) NOT NULL,
    property_value VARCHAR(1000),
    PRIMARY KEY (catalog_name, namespace, property_key)
);

-- Create indices for better performance
CREATE INDEX IF NOT EXISTS iceberg_tables_namespace_idx ON iceberg_tables (catalog_name, table_namespace);
CREATE INDEX IF NOT EXISTS iceberg_namespace_properties_namespace_idx ON iceberg_namespace_properties (catalog_name, namespace);

-- Insert default namespace
INSERT INTO iceberg_namespace_properties (catalog_name, namespace, property_key, property_value)
VALUES ('iceberg', 'default', 'location', 's3://warehouse/default')
ON CONFLICT (catalog_name, namespace, property_key) DO NOTHING;

-- Create a simple view for easier catalog browsing
CREATE OR REPLACE VIEW catalog_summary AS
SELECT 
    catalog_name,
    table_namespace,
    table_name,
    metadata_location
FROM iceberg_tables
ORDER BY catalog_name, table_namespace, table_name;
EOF

    log "INFO" "Iceberg catalog initialization script created"
}

create_minio_init_script() {
    log "INFO" "Creating MinIO initialization script..."
    
    cat > /opt/postgres-iceberg/init-minio.sh << EOF
#!/bin/bash
# MinIO initialization script

# Wait for MinIO to be ready
echo "Waiting for MinIO to be ready..."
until curl -sf http://localhost:${MINIO_PORT}/minio/health/live; do
    sleep 2
done

# Configure MinIO client
export MC_HOST_minio=http://${MINIO_ROOT_USER}:${MINIO_ROOT_PASSWORD}@localhost:${MINIO_PORT}

# Create warehouse bucket for Iceberg
docker run --rm --network postgres-iceberg \\
    -e MC_HOST_minio=http://${MINIO_ROOT_USER}:${MINIO_ROOT_PASSWORD}@minio:9000 \\
    minio/mc mb minio/warehouse || true

# Set bucket policy
docker run --rm --network postgres-iceberg \\
    -e MC_HOST_minio=http://${MINIO_ROOT_USER}:${MINIO_ROOT_PASSWORD}@minio:9000 \\
    minio/mc policy set public minio/warehouse || true

echo "MinIO initialization completed"
EOF

    chmod +x /opt/postgres-iceberg/init-minio.sh
    log "INFO" "MinIO initialization script created"
}

start_services() {
    log "INFO" "Starting services..."
    
    cd /opt/postgres-iceberg
    
    # Start services
    docker-compose up -d
    
    # Wait for services to be ready
    log "INFO" "Waiting for services to start..."
    sleep 10
    
    # Initialize MinIO
    log "INFO" "Initializing MinIO..."
    /opt/postgres-iceberg/init-minio.sh
    
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
    
    # Check PostgreSQL
    if docker exec iceberg-postgres pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB} &>/dev/null; then
        log "INFO" "PostgreSQL is running and healthy"
    else
        error_exit "PostgreSQL health check failed"
    fi
    
    # Check containers
    local running_containers=$(docker-compose -f "$COMPOSE_FILE" ps --services --filter "status=running" | wc -l)
    if [[ $running_containers -eq 2 ]]; then
        log "INFO" "All containers are running"
    else
        error_exit "Not all containers are running (expected 2, found $running_containers)"
    fi
    
    log "INFO" "Installation verified successfully"
}

create_management_scripts() {
    log "INFO" "Creating management scripts..."
    
    # Create status script
    cat > /usr/local/bin/postgres-iceberg-status << EOF
#!/bin/bash
cd /opt/postgres-iceberg
docker-compose ps
echo ""
echo "MinIO Console: http://localhost:${MINIO_CONSOLE_PORT}"
echo "MinIO API: http://localhost:${MINIO_PORT}"
echo "PostgreSQL: localhost:${POSTGRES_PORT}"
echo ""
echo "Iceberg Catalog Connection:"
echo "  Host: localhost"
echo "  Port: ${POSTGRES_PORT}"
echo "  Database: ${POSTGRES_DB}"
echo "  User: ${POSTGRES_USER}"
EOF
    chmod +x /usr/local/bin/postgres-iceberg-status
    
    # Create stop script
    cat > /usr/local/bin/postgres-iceberg-stop << EOF
#!/bin/bash
cd /opt/postgres-iceberg
docker-compose down
EOF
    chmod +x /usr/local/bin/postgres-iceberg-stop
    
    # Create start script
    cat > /usr/local/bin/postgres-iceberg-start << EOF
#!/bin/bash
cd /opt/postgres-iceberg
docker-compose up -d
EOF
    chmod +x /usr/local/bin/postgres-iceberg-start
    
    # Create logs script
    cat > /usr/local/bin/postgres-iceberg-logs << EOF
#!/bin/bash
cd /opt/postgres-iceberg
docker-compose logs -f "\$@"
EOF
    chmod +x /usr/local/bin/postgres-iceberg-logs
    
    # Create psql connection script
    cat > /usr/local/bin/postgres-iceberg-psql << EOF
#!/bin/bash
docker exec -it iceberg-postgres psql -U ${POSTGRES_USER} -d ${POSTGRES_DB}
EOF
    chmod +x /usr/local/bin/postgres-iceberg-psql
    
    log "INFO" "Management scripts created"
}

save_credentials() {
    local creds_file="/root/.postgres-iceberg-credentials"
    
    cat > "$creds_file" << EOF
# PostgreSQL Iceberg Catalog Installation Credentials
# Generated on $(date)

## MinIO Credentials
MinIO Root User: ${MINIO_ROOT_USER}
MinIO Root Password: ${MINIO_ROOT_PASSWORD}
MinIO API URL: http://localhost:${MINIO_PORT}
MinIO Console URL: http://localhost:${MINIO_CONSOLE_PORT}

## PostgreSQL Iceberg Catalog
PostgreSQL Host: localhost
PostgreSQL Port: ${POSTGRES_PORT}
PostgreSQL Database: ${POSTGRES_DB}
PostgreSQL User: ${POSTGRES_USER}
PostgreSQL Password: ${POSTGRES_PASSWORD}

## S3 Configuration for Applications
Endpoint: http://localhost:${MINIO_PORT}
Access Key: ${MINIO_ROOT_USER}
Secret Key: ${MINIO_ROOT_PASSWORD}
Path Style Access: true
Default Bucket: warehouse

## JDBC Connection String
jdbc:postgresql://localhost:${POSTGRES_PORT}/${POSTGRES_DB}

## Management Commands
Status: postgres-iceberg-status
Logs: postgres-iceberg-logs
Stop: postgres-iceberg-stop
Start: postgres-iceberg-start
PostgreSQL CLI: postgres-iceberg-psql

## Example MinIO Client Usage
docker run --rm -it --network host \\
  -e MC_HOST_minio=http://${MINIO_ROOT_USER}:${MINIO_ROOT_PASSWORD}@localhost:${MINIO_PORT} \\
  minio/mc ls minio/

## Example Iceberg Configuration (Python/PySpark)
catalog_properties = {
    "type": "jdbc",
    "uri": "jdbc:postgresql://localhost:${POSTGRES_PORT}/${POSTGRES_DB}",
    "jdbc.user": "${POSTGRES_USER}",
    "jdbc.password": "${POSTGRES_PASSWORD}",
    "warehouse": "s3://warehouse",
    "s3.endpoint": "http://localhost:${MINIO_PORT}",
    "s3.access-key-id": "${MINIO_ROOT_USER}",
    "s3.secret-access-key": "${MINIO_ROOT_PASSWORD}",
    "s3.path-style-access": "true"
}
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
            --postgres-port)
                POSTGRES_PORT="$2"
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
    
    log "INFO" "Starting PostgreSQL Iceberg Catalog and MinIO installation"
    
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
    create_iceberg_init_script
    create_docker_compose
    create_minio_init_script
    start_services
    verify_installation
    create_management_scripts
    save_credentials
    
    log "INFO" "PostgreSQL Iceberg Catalog and MinIO installation completed successfully"
    
    echo -e "\n${GREEN}Installation Summary:${NC}"
    echo "- MinIO object storage installed and running"
    echo "  - API: http://localhost:${MINIO_PORT}"
    echo "  - Console: http://localhost:${MINIO_CONSOLE_PORT}"
    echo "- PostgreSQL Iceberg catalog installed and running"
    echo "  - Host: localhost:${POSTGRES_PORT}"
    echo "  - Database: ${POSTGRES_DB}"
    echo "- Data directories:"
    echo "  - MinIO: ${MINIO_DATA_DIR}"
    echo "  - PostgreSQL: ${POSTGRES_DATA_DIR}"
    echo "- Configuration: /opt/postgres-iceberg/docker-compose.yml"
    echo "- Credentials saved to: /root/.postgres-iceberg-credentials"
    echo ""
    echo "Management commands:"
    echo "  - postgres-iceberg-status: Check service status"
    echo "  - postgres-iceberg-logs: View service logs"
    echo "  - postgres-iceberg-stop: Stop all services"
    echo "  - postgres-iceberg-start: Start all services"
    echo "  - postgres-iceberg-psql: Connect to PostgreSQL"
}

main "$@"