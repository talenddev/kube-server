#!/bin/bash

# Script: install-development-containers.sh
# Purpose: Install and configure development containers (LocalStack, Docker Registry)
# Author: Server Automation Library
# Date: 2025-01-06
# Version: 1.0

# Documentation
# =============
# Description:
#   Installs and configures common development containers including LocalStack for AWS service
#   emulation and Docker Registry for local container image storage. These containers provide
#   essential infrastructure for local development and testing.
#
# Dependencies:
#   - docker: Container runtime for running services
#   - docker-compose: For orchestrating multiple containers (optional)
#   - curl: For downloading configuration files
#   - jq: For JSON processing
#
# System Requirements:
#   - Supported OS: Ubuntu 20.04+, Debian 10+, CentOS 8+, RHEL 8+
#   - Docker installed and running
#   - Minimum RAM: 4GB (8GB recommended for full LocalStack)
#   - Disk space: 20GB minimum
#   - Available ports: 4566 (LocalStack), 5000 (Registry)
#
# Configuration Variables:
#   - LOCALSTACK_VERSION: LocalStack version to install (default: latest)
#   - LOCALSTACK_DATA_DIR: LocalStack data directory (default: /var/lib/localstack)
#   - LOCALSTACK_SERVICES: AWS services to enable (default: all core services)
#   - REGISTRY_VERSION: Docker Registry version (default: 2)
#   - REGISTRY_DATA_DIR: Registry data directory (default: /var/lib/docker-registry)
#   - REGISTRY_PORT: Registry port (default: 5000)
#   - ENABLE_UI: Enable Registry UI (default: true)
#   - REGISTRY_UI_PORT: Registry UI port (default: 8080)
#
# Usage:
#   sudo ./install-development-containers.sh [options]
#
# Options:
#   -h, --help           Show this help message
#   -v, --verbose        Enable verbose output
#   -l, --localstack     Install only LocalStack
#   -r, --registry       Install only Docker Registry
#   --no-ui              Don't install Registry UI
#   --localstack-pro     Use LocalStack Pro (requires API key)
#
# Examples:
#   sudo ./install-development-containers.sh
#   sudo ./install-development-containers.sh --localstack
#   sudo ./install-development-containers.sh --registry --no-ui
#
# Post-Installation:
#   1. LocalStack: http://localhost:4566
#   2. Docker Registry: http://localhost:5000
#   3. Registry UI: http://localhost:8080 (if enabled)
#   4. Check status: docker ps
#   5. View logs: docker logs localstack / docker logs registry

set -euo pipefail

# Script variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/development-containers-install.log"
VERBOSE=false

# LocalStack configuration
LOCALSTACK_VERSION="latest"
LOCALSTACK_DATA_DIR="/var/lib/localstack"
LOCALSTACK_SERVICES="s3,dynamodb,lambda,sqs,sns,kinesis,secretsmanager,ssm"
LOCALSTACK_PRO=false
LOCALSTACK_API_KEY=""

# Docker Registry configuration
REGISTRY_VERSION="2"
REGISTRY_DATA_DIR="/var/lib/docker-registry"
REGISTRY_PORT="5000"
ENABLE_UI=true
REGISTRY_UI_PORT="8080"

# Installation flags
INSTALL_LOCALSTACK=true
INSTALL_REGISTRY=true

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Source common functions if available
if [[ -f "${SCRIPT_DIR}/../utilities/common-functions.sh" ]]; then
    source "${SCRIPT_DIR}/../utilities/common-functions.sh"
else
    # Define minimal required functions
    log() {
        local level=$1
        shift
        local message="$@"
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        
        case $level in
            "INFO")
                echo -e "${GREEN}[INFO]${NC} $message"
                ;;
            "WARN")
                echo -e "${YELLOW}[WARN]${NC} $message"
                ;;
            "ERROR")
                echo -e "${RED}[ERROR]${NC} $message"
                ;;
        esac
        
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    }
    
    error_exit() {
        log "ERROR" "$1"
        exit 1
    }
    
    check_root() {
        if [[ $EUID -ne 0 ]]; then
            error_exit "This script must be run as root (use sudo)"
        fi
    }
    
    detect_os() {
        if [[ -f /etc/os-release ]]; then
            . /etc/os-release
            OS=$ID
            OS_VERSION=$VERSION_ID
        else
            error_exit "Cannot detect OS version"
        fi
        
        log "INFO" "Detected OS: $OS $OS_VERSION"
    }
fi

# Check Docker installation
check_docker() {
    log "INFO" "Checking Docker installation..."
    
    if ! command -v docker &>/dev/null; then
        error_exit "Docker is not installed. Please install Docker first."
    fi
    
    if ! docker info &>/dev/null; then
        error_exit "Docker is not running. Please start Docker service."
    fi
    
    log "INFO" "Docker is installed and running"
}

# Create necessary directories
create_directories() {
    log "INFO" "Creating necessary directories..."
    
    if [[ "$INSTALL_LOCALSTACK" == "true" ]]; then
        mkdir -p "$LOCALSTACK_DATA_DIR"
        chmod 755 "$LOCALSTACK_DATA_DIR"
    fi
    
    if [[ "$INSTALL_REGISTRY" == "true" ]]; then
        mkdir -p "$REGISTRY_DATA_DIR"
        mkdir -p "$REGISTRY_DATA_DIR/certs"
        chmod 755 "$REGISTRY_DATA_DIR"
    fi
}

# Install LocalStack
install_localstack() {
    log "INFO" "Installing LocalStack..."
    
    # Create LocalStack configuration
    mkdir -p /etc/localstack
    
    # Clean up any existing LocalStack temp directories
    log "INFO" "Cleaning up old LocalStack temp directories..."
    find /tmp -maxdepth 1 -name "localstack-*" -type d -mtime +1 -exec rm -rf {} \; 2>/dev/null || true
    
    # Create LocalStack temp directory with unique subdirectory
    LOCALSTACK_TMP_DIR="/tmp/localstack-${RANDOM}"
    mkdir -p "$LOCALSTACK_TMP_DIR"
    chmod 777 "$LOCALSTACK_TMP_DIR"
    
    # Create docker-compose file for LocalStack
    cat > /etc/localstack/docker-compose.yml << EOF
version: '3.8'

services:
  localstack:
    container_name: localstack
    image: localstack/localstack:${LOCALSTACK_VERSION}
    ports:
      - "4566:4566"
      - "4571:4571"
    environment:
      - SERVICES=${LOCALSTACK_SERVICES}
      - DEBUG=0
      - DATA_DIR=/var/lib/localstack
      - LAMBDA_EXECUTOR=docker
      - DOCKER_HOST=unix:///var/run/docker.sock
      - HOST_TMP_FOLDER=${LOCALSTACK_TMP_DIR}
      - DISABLE_CORS_CHECKS=0
      - PERSISTENCE=1
EOF

    # Add Pro configuration if enabled
    if [[ "$LOCALSTACK_PRO" == "true" ]]; then
        cat >> /etc/localstack/docker-compose.yml << EOF
      - LOCALSTACK_API_KEY=${LOCALSTACK_API_KEY}
EOF
    fi

    # Complete the docker-compose file
    cat >> /etc/localstack/docker-compose.yml << EOF
    volumes:
      - "${LOCALSTACK_DATA_DIR}:/var/lib/localstack"
      - "/var/run/docker.sock:/var/run/docker.sock"
      - "${LOCALSTACK_TMP_DIR}:${LOCALSTACK_TMP_DIR}"
    networks:
      - localstack-net
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4566/_localstack/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

networks:
  localstack-net:
    driver: bridge
    name: localstack-net
EOF

    # Create LocalStack initialization script
    cat > /usr/local/bin/localstack-init << 'EOF'
#!/bin/bash
# LocalStack initialization script

echo "Waiting for LocalStack to be ready..."
until curl -f http://localhost:4566/_localstack/health 2>/dev/null; do
    sleep 2
done

echo "LocalStack is ready!"

# Add any initialization commands here
# Example: Create S3 bucket
# aws --endpoint-url=http://localhost:4566 s3 mb s3://test-bucket

echo "LocalStack initialization completed"
EOF

    chmod +x /usr/local/bin/localstack-init

    # Create AWS CLI configuration for LocalStack
    mkdir -p /root/.aws
    cat > /root/.aws/config << 'EOF'
[default]
region = us-east-1
output = json

[profile localstack]
region = us-east-1
output = json
EOF

    cat > /root/.aws/credentials << 'EOF'
[default]
aws_access_key_id = test
aws_secret_access_key = test

[localstack]
aws_access_key_id = test
aws_secret_access_key = test
EOF

    # Create helper script for LocalStack AWS CLI
    cat > /usr/local/bin/awslocal << 'EOF'
#!/bin/bash
# Wrapper for AWS CLI with LocalStack endpoint

aws --endpoint-url=http://localhost:4566 "$@"
EOF

    chmod +x /usr/local/bin/awslocal

    # Start LocalStack
    log "INFO" "Starting LocalStack..."
    cd /etc/localstack
    if command -v docker-compose &>/dev/null; then
        docker-compose up -d
    else
        docker compose up -d
    fi

    # Wait for LocalStack to be healthy
    log "INFO" "Waiting for LocalStack to be ready..."
    local max_attempts=30
    for ((i=1; i<=max_attempts; i++)); do
        if docker exec localstack curl -f http://localhost:4566/_localstack/health &>/dev/null; then
            log "INFO" "LocalStack is ready"
            break
        fi
        if [[ $i -eq $max_attempts ]]; then
            error_exit "LocalStack failed to start"
        fi
        sleep 2
    done
    
    log "INFO" "LocalStack installed successfully"
}

# Install Docker Registry
install_docker_registry() {
    log "INFO" "Installing Docker Registry..."
    
    # Generate self-signed certificates for registry
    log "INFO" "Generating self-signed certificates..."
    
    mkdir -p "$REGISTRY_DATA_DIR/certs"
    
    openssl req -newkey rsa:4096 -nodes -sha256 -keyout "$REGISTRY_DATA_DIR/certs/domain.key" \
        -x509 -days 365 -out "$REGISTRY_DATA_DIR/certs/domain.crt" \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost" \
        -addext "subjectAltName=DNS:localhost,DNS:registry.local,IP:127.0.0.1" 2>/dev/null

    # Create registry configuration
    mkdir -p "$REGISTRY_DATA_DIR/config"
    cat > "$REGISTRY_DATA_DIR/config/config.yml" << EOF
version: 0.1
log:
  fields:
    service: registry
storage:
  cache:
    blobdescriptor: inmemory
  filesystem:
    rootdirectory: /var/lib/registry
http:
  addr: :5000
  headers:
    X-Content-Type-Options: [nosniff]
health:
  storagedriver:
    enabled: true
    interval: 10s
    threshold: 3
EOF

    # Create docker-compose file for registry
    cat > /etc/docker/registry-compose.yml << EOF
version: '3.8'

services:
  registry:
    container_name: registry
    image: registry:${REGISTRY_VERSION}
    ports:
      - "${REGISTRY_PORT}:5000"
    environment:
      REGISTRY_HTTP_TLS_CERTIFICATE: /certs/domain.crt
      REGISTRY_HTTP_TLS_KEY: /certs/domain.key
      REGISTRY_AUTH: htpasswd
      REGISTRY_AUTH_HTPASSWD_PATH: /auth/htpasswd
      REGISTRY_AUTH_HTPASSWD_REALM: Registry Realm
    volumes:
      - "${REGISTRY_DATA_DIR}/data:/var/lib/registry"
      - "${REGISTRY_DATA_DIR}/certs:/certs"
      - "${REGISTRY_DATA_DIR}/auth:/auth"
      - "${REGISTRY_DATA_DIR}/config/config.yml:/etc/docker/registry/config.yml"
    networks:
      - registry-net
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "https://localhost:5000/v2/"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF

    # Add Registry UI if enabled
    if [[ "$ENABLE_UI" == "true" ]]; then
        cat >> /etc/docker/registry-compose.yml << EOF

  registry-ui:
    container_name: registry-ui
    image: joxit/docker-registry-ui:latest
    ports:
      - "${REGISTRY_UI_PORT}:80"
    environment:
      - REGISTRY_TITLE=Local Docker Registry
      - REGISTRY_URL=https://registry:5000
      - SINGLE_REGISTRY=true
      - DELETE_IMAGES=true
      - SHOW_CONTENT_DIGEST=true
      - NGINX_PROXY_PASS_URL=https://registry:5000
      - SHOW_CATALOG_NB_TAGS=true
      - CATALOG_MIN_BRANCHES=1
      - CATALOG_MAX_BRANCHES=1
      - TAGLIST_PAGE_SIZE=100
      - REGISTRY_SECURED=true
      - CATALOG_ELEMENTS_LIMIT=1000
    depends_on:
      - registry
    networks:
      - registry-net
    restart: unless-stopped
EOF
    fi

    # Complete docker-compose file
    cat >> /etc/docker/registry-compose.yml << EOF

networks:
  registry-net:
    driver: bridge
    name: registry-net
EOF

    # Create default htpasswd file (username: admin, password: admin)
    mkdir -p "$REGISTRY_DATA_DIR/auth"
    
    # Install htpasswd if not available
    if ! command -v htpasswd &>/dev/null; then
        log "INFO" "Installing htpasswd utility..."
        case $OS in
            ubuntu|debian)
                apt-get update -qq
                apt-get install -y apache2-utils
                ;;
            centos|rhel|fedora)
                yum install -y httpd-tools
                ;;
            *)
                log "WARN" "Cannot install htpasswd automatically, using Docker instead"
                ;;
        esac
    fi
    
    # Generate htpasswd file
    if command -v htpasswd &>/dev/null; then
        htpasswd -Bbn admin admin > "$REGISTRY_DATA_DIR/auth/htpasswd"
    else
        # Fallback to using Docker registry image
        docker run --rm --entrypoint htpasswd registry:2.7 -Bbn admin admin > "$REGISTRY_DATA_DIR/auth/htpasswd"
    fi

    # Configure Docker to trust the registry certificate
    mkdir -p /etc/docker/certs.d/localhost:${REGISTRY_PORT}
    cp "$REGISTRY_DATA_DIR/certs/domain.crt" /etc/docker/certs.d/localhost:${REGISTRY_PORT}/ca.crt

    # Start registry
    log "INFO" "Starting Docker Registry..."
    cd /etc/docker
    if command -v docker-compose &>/dev/null; then
        docker-compose -f registry-compose.yml up -d
    else
        docker compose -f registry-compose.yml up -d
    fi

    # Wait for registry to be healthy
    log "INFO" "Waiting for Docker Registry to be ready..."
    local max_attempts=30
    for ((i=1; i<=max_attempts; i++)); do
        if curl -k -u admin:admin https://localhost:${REGISTRY_PORT}/v2/ &>/dev/null; then
            log "INFO" "Docker Registry is ready"
            break
        fi
        if [[ $i -eq $max_attempts ]]; then
            error_exit "Docker Registry failed to start"
        fi
        sleep 2
    done

    # Create helper scripts
    cat > /usr/local/bin/registry-push << EOF
#!/bin/bash
# Helper script to push images to local registry

if [[ \$# -ne 1 ]]; then
    echo "Usage: registry-push <image:tag>"
    exit 1
fi

IMAGE=\$1
LOCAL_IMAGE="localhost:${REGISTRY_PORT}/\${IMAGE}"

echo "Tagging \${IMAGE} as \${LOCAL_IMAGE}..."
docker tag "\${IMAGE}" "\${LOCAL_IMAGE}"

echo "Pushing to local registry..."
docker push "\${LOCAL_IMAGE}"

echo "Image pushed successfully!"
echo "Pull with: docker pull \${LOCAL_IMAGE}"
EOF

    chmod +x /usr/local/bin/registry-push

    cat > /usr/local/bin/registry-list << EOF
#!/bin/bash
# List images in local registry

echo "Images in local registry:"
curl -k -s -u admin:admin https://localhost:${REGISTRY_PORT}/v2/_catalog | jq -r '.repositories[]' 2>/dev/null || echo "No images found"
EOF

    chmod +x /usr/local/bin/registry-list

    log "INFO" "Docker Registry installed successfully"
}

# Create management scripts
create_management_scripts() {
    log "INFO" "Creating management scripts..."

    # Create status check script
    cat > /usr/local/bin/dev-containers-status << 'EOF'
#!/bin/bash
# Check status of development containers

echo "Development Containers Status"
echo "============================"

# LocalStack status
if docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -q localstack; then
    echo -e "\nLocalStack:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep localstack
    echo "Health: $(docker inspect localstack --format='{{.State.Health.Status}}' 2>/dev/null || echo 'N/A')"
    echo "Endpoint: http://localhost:4566"
else
    echo -e "\nLocalStack: Not running"
fi

# Registry status
if docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "registry|registry-ui"; then
    echo -e "\nDocker Registry:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "registry|registry-ui"
    echo "Registry endpoint: https://localhost:5000"
    if docker ps | grep -q registry-ui; then
        echo "Registry UI: http://localhost:8080"
    fi
else
    echo -e "\nDocker Registry: Not running"
fi

echo -e "\nUseful commands:"
echo "- LocalStack AWS: awslocal <command>"
echo "- Push to registry: registry-push <image:tag>"
echo "- List registry images: registry-list"
EOF

    chmod +x /usr/local/bin/dev-containers-status

    # Create restart script
    cat > /usr/local/bin/dev-containers-restart << 'EOF'
#!/bin/bash
# Restart development containers

echo "Restarting development containers..."

# Restart LocalStack
if [[ -f /etc/localstack/docker-compose.yml ]]; then
    echo "Restarting LocalStack..."
    cd /etc/localstack
    docker-compose restart
fi

# Restart Registry
if [[ -f /etc/docker/registry-compose.yml ]]; then
    echo "Restarting Docker Registry..."
    cd /etc/docker
    docker-compose -f registry-compose.yml restart
fi

echo "Development containers restarted"
EOF

    chmod +x /usr/local/bin/dev-containers-restart

    # Create stop script
    cat > /usr/local/bin/dev-containers-stop << 'EOF'
#!/bin/bash
# Stop development containers

echo "Stopping development containers..."

# Stop LocalStack
if [[ -f /etc/localstack/docker-compose.yml ]]; then
    echo "Stopping LocalStack..."
    cd /etc/localstack
    docker-compose down
fi

# Stop Registry
if [[ -f /etc/docker/registry-compose.yml ]]; then
    echo "Stopping Docker Registry..."
    cd /etc/docker
    docker-compose -f registry-compose.yml down
fi

echo "Development containers stopped"
EOF

    chmod +x /usr/local/bin/dev-containers-stop

    log "INFO" "Management scripts created"
}

# Configure Docker daemon for insecure registry (optional)
configure_docker_daemon() {
    log "INFO" "Configuring Docker daemon..."
    
    # Add insecure registry to Docker daemon config
    local daemon_config="/etc/docker/daemon.json"
    
    if [[ -f "$daemon_config" ]]; then
        # Backup existing config
        cp "$daemon_config" "$daemon_config.bak"
        
        # Add insecure registries using jq
        if command -v jq &>/dev/null; then
            jq --arg reg "localhost:${REGISTRY_PORT}" '. + {"insecure-registries": ((.["insecure-registries"] // []) + [$reg] | unique)}' "$daemon_config" > "$daemon_config.tmp"
            mv "$daemon_config.tmp" "$daemon_config"
        else
            log "WARN" "jq not found, skipping daemon.json update"
        fi
    else
        # Create new daemon.json
        cat > "$daemon_config" << EOF
{
    "insecure-registries": ["localhost:${REGISTRY_PORT}"]
}
EOF
    fi
    
    # Restart Docker daemon
    systemctl daemon-reload
    systemctl restart docker
    
    log "INFO" "Docker daemon configured"
}

# Print summary
print_summary() {
    echo -e "\n${GREEN}Development Containers Installation Summary:${NC}"
    echo "============================================"
    
    if [[ "$INSTALL_LOCALSTACK" == "true" ]]; then
        echo -e "\n${GREEN}LocalStack:${NC}"
        echo "- Status: $(docker ps --filter name=localstack --format '{{.Status}}' || echo 'Not running')"
        echo "- Endpoint: http://localhost:4566"
        echo "- Services: ${LOCALSTACK_SERVICES}"
        echo "- Data directory: ${LOCALSTACK_DATA_DIR}"
        echo "- AWS CLI wrapper: awslocal"
        echo "- Health check: curl http://localhost:4566/_localstack/health"
    fi
    
    if [[ "$INSTALL_REGISTRY" == "true" ]]; then
        echo -e "\n${GREEN}Docker Registry:${NC}"
        echo "- Status: $(docker ps --filter name=registry --format '{{.Status}}' || echo 'Not running')"
        echo "- Endpoint: https://localhost:${REGISTRY_PORT}"
        echo "- Username: admin"
        echo "- Password: admin"
        echo "- Data directory: ${REGISTRY_DATA_DIR}"
        echo "- Push helper: registry-push <image:tag>"
        echo "- List images: registry-list"
        
        if [[ "$ENABLE_UI" == "true" ]]; then
            echo "- Registry UI: http://localhost:${REGISTRY_UI_PORT}"
        fi
    fi
    
    echo -e "\n${GREEN}Management Commands:${NC}"
    echo "- Check status: dev-containers-status"
    echo "- Restart containers: dev-containers-restart"
    echo "- Stop containers: dev-containers-stop"
    
    echo -e "\n${GREEN}Example Usage:${NC}"
    if [[ "$INSTALL_LOCALSTACK" == "true" ]]; then
        echo "- Create S3 bucket: awslocal s3 mb s3://test-bucket"
        echo "- List S3 buckets: awslocal s3 ls"
    fi
    
    if [[ "$INSTALL_REGISTRY" == "true" ]]; then
        echo "- Login to registry: docker login localhost:${REGISTRY_PORT} -u admin -p admin"
        echo "- Push image: registry-push ubuntu:latest"
    fi
}

# Usage function
usage() {
    grep "^#" "$0" | grep -E "^# (Usage|Options|Examples):" -A 20 | grep -E "^#( |$)" | sed 's/^# //'
}

# Parse command line arguments
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
            -l|--localstack)
                INSTALL_LOCALSTACK=true
                INSTALL_REGISTRY=false
                shift
                ;;
            -r|--registry)
                INSTALL_LOCALSTACK=false
                INSTALL_REGISTRY=true
                shift
                ;;
            --no-ui)
                ENABLE_UI=false
                shift
                ;;
            --localstack-pro)
                LOCALSTACK_PRO=true
                if [[ -n "${2:-}" && ! "${2:-}" =~ ^- ]]; then
                    LOCALSTACK_API_KEY="$2"
                    shift 2
                else
                    error_exit "LocalStack Pro requires API key"
                fi
                ;;
            *)
                error_exit "Unknown option: $1"
                ;;
        esac
    done
}

# Main function
main() {
    # Initialize log file
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    
    log "INFO" "Starting development containers installation"
    
    # Parse arguments
    parse_args "$@"
    
    # Check prerequisites
    check_root
    detect_os
    check_docker
    
    # Create directories
    create_directories
    
    # Install containers
    if [[ "$INSTALL_LOCALSTACK" == "true" ]]; then
        install_localstack
    fi
    
    if [[ "$INSTALL_REGISTRY" == "true" ]]; then
        install_docker_registry
        configure_docker_daemon
    fi
    
    # Create management scripts
    create_management_scripts
    
    # Print summary
    print_summary
    
    log "INFO" "Development containers installation completed successfully"
}

# Run main function
main "$@"