#!/bin/bash

# Script: install-docker.sh
# Purpose: Install and configure Docker CE (Community Edition) with security best practices
# Author: Server Automation Library
# Date: 2025-01-06
# Version: 1.0

# Documentation
# =============
# Description:
#   Installs Docker CE from official Docker repositories with proper configuration.
#   Sets up Docker daemon with security options, logging, and resource limits.
#   Optionally configures Docker Compose and user permissions.
#
# Dependencies:
#   - curl: For downloading Docker GPG keys and installation scripts
#   - apt-transport-https/yum-utils: For HTTPS repository access
#   - ca-certificates: For SSL certificate validation
#   - gnupg/gpg: For GPG key management
#
# System Requirements:
#   - Supported OS: Ubuntu 20.04+, Debian 10+, CentOS 8+, RHEL 8+
#   - Required packages: curl, ca-certificates, gnupg
#   - Minimum RAM: 2GB (4GB recommended)
#   - Disk space: 20GB minimum (for images and containers)
#   - 64-bit system with compatible kernel (3.10+)
#
# Configuration Variables:
#   - DOCKER_USER: User to add to docker group (default: none)
#   - INSTALL_COMPOSE: Install Docker Compose (default: true)
#   - DOCKER_DATA_ROOT: Docker data directory (default: /var/lib/docker)
#   - ENABLE_USERNS: Enable user namespace remapping (default: false)
#   - STORAGE_DRIVER: Storage driver (default: overlay2)
#   - LOG_DRIVER: Logging driver (default: json-file)
#   - MAX_LOG_SIZE: Maximum log file size (default: 10m)
#   - MAX_LOG_FILES: Maximum number of log files (default: 3)
#
# Usage:
#   sudo ./install-docker.sh [options]
#
# Options:
#   -h, --help           Show this help message
#   -v, --verbose        Enable verbose output
#   -u, --user           Add user to docker group
#   -c, --compose        Install Docker Compose (default: yes)
#   -n, --no-compose     Don't install Docker Compose
#   --data-root          Custom Docker data directory
#   --userns-remap       Enable user namespace remapping for security
#
# Examples:
#   sudo ./install-docker.sh
#   sudo ./install-docker.sh --user john
#   sudo ./install-docker.sh --data-root /data/docker --userns-remap
#
# Post-Installation:
#   1. Verify installation: docker version
#   2. Test Docker: docker run hello-world
#   3. Configuration: /etc/docker/daemon.json
#   4. Service management: systemctl status docker
#   5. Logs: journalctl -u docker
#   6. If user added to docker group: logout and login for changes to take effect

set -euo pipefail

# Script variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/docker-install.log"
VERBOSE=false
DOCKER_USER=""
INSTALL_COMPOSE=true
DOCKER_DATA_ROOT="/var/lib/docker"
ENABLE_USERNS=false
STORAGE_DRIVER="overlay2"
LOG_DRIVER="json-file"
MAX_LOG_SIZE="10m"
MAX_LOG_FILES="3"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Source common functions if available
if [[ -f "${SCRIPT_DIR}/common-functions.sh" ]]; then
    source "${SCRIPT_DIR}/common-functions.sh"
else
    # Define minimal required functions if common-functions.sh not available
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

# Check system requirements
check_system_compatibility() {
    log "INFO" "Checking system compatibility..."
    
    # Check architecture
    local arch=$(uname -m)
    case $arch in
        x86_64|amd64)
            log "INFO" "Architecture: $arch (supported)"
            ;;
        aarch64|arm64)
            log "INFO" "Architecture: $arch (supported)"
            ;;
        *)
            error_exit "Unsupported architecture: $arch"
            ;;
    esac
    
    # Check kernel version
    local kernel_version=$(uname -r | cut -d. -f1,2)
    local min_kernel="3.10"
    
    if [[ $(echo -e "$kernel_version\n$min_kernel" | sort -V | head -1) != "$min_kernel" ]]; then
        error_exit "Kernel version $kernel_version is too old. Minimum required: $min_kernel"
    fi
    
    log "INFO" "Kernel version: $(uname -r) (supported)"
}

# Remove old Docker versions
remove_old_docker() {
    log "INFO" "Removing old Docker installations if present..."
    
    local old_packages=(
        docker
        docker-client
        docker-client-latest
        docker-common
        docker-latest
        docker-latest-logrotate
        docker-logrotate
        docker-engine
        docker.io
        containerd
        runc
    )
    
    case $OS in
        ubuntu|debian)
            for pkg in "${old_packages[@]}"; do
                apt-get remove -y "$pkg" 2>/dev/null || true
            done
            ;;
        centos|rhel|fedora)
            for pkg in "${old_packages[@]}"; do
                yum remove -y "$pkg" 2>/dev/null || true
            done
            ;;
    esac
}

# Install Docker CE
install_docker_ce() {
    log "INFO" "Installing Docker CE..."
    
    case $OS in
        ubuntu|debian)
            # Install prerequisites
            apt-get update
            apt-get install -y \
                ca-certificates \
                curl \
                gnupg \
                lsb-release
            
            # Add Docker's official GPG key
            mkdir -p /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            chmod a+r /etc/apt/keyrings/docker.gpg
            
            # Add Docker repository
            echo \
                "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS \
                $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            
            # Install Docker
            apt-get update
            apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
            
        centos|rhel|fedora)
            # Install prerequisites
            yum install -y yum-utils device-mapper-persistent-data lvm2
            
            # Add Docker repository
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            
            # Install Docker
            yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
            
        *)
            error_exit "Unsupported OS: $OS"
            ;;
    esac
    
    log "INFO" "Docker CE installed successfully"
}

# Configure Docker daemon
configure_docker() {
    log "INFO" "Configuring Docker daemon..."
    
    # Create Docker configuration directory
    mkdir -p /etc/docker
    
    # Create daemon.json with security and performance settings
    cat > /etc/docker/daemon.json << EOF
{
    "data-root": "$DOCKER_DATA_ROOT",
    "storage-driver": "$STORAGE_DRIVER",
    "log-driver": "$LOG_DRIVER",
    "log-opts": {
        "max-size": "$MAX_LOG_SIZE",
        "max-file": "$MAX_LOG_FILES"
    },
    "default-ulimits": {
        "nofile": {
            "Name": "nofile",
            "Hard": 64000,
            "Soft": 64000
        }
    },
    "live-restore": true,
    "userland-proxy": false,
    "no-new-privileges": true,
    "experimental": false,
    "features": {
        "buildkit": true
    }
}
EOF

    # Add user namespace remapping if enabled
    if [[ "$ENABLE_USERNS" == "true" ]]; then
        log "INFO" "Configuring user namespace remapping..."
        
        # Create dockremap user and group
        useradd -r -s /bin/false dockremap || true
        echo "dockremap:100000:65536" >> /etc/subuid
        echo "dockremap:100000:65536" >> /etc/subgid
        
        # Update daemon.json
        local tmp_config=$(mktemp)
        jq '. + {"userns-remap": "default"}' /etc/docker/daemon.json > "$tmp_config"
        mv "$tmp_config" /etc/docker/daemon.json
    fi
    
    # Create Docker data directory if custom
    if [[ "$DOCKER_DATA_ROOT" != "/var/lib/docker" ]]; then
        mkdir -p "$DOCKER_DATA_ROOT"
        chmod 711 "$DOCKER_DATA_ROOT"
    fi
    
    # Configure Docker systemd service
    mkdir -p /etc/systemd/system/docker.service.d
    cat > /etc/systemd/system/docker.service.d/override.conf << 'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd
# Restart policy
Restart=always
RestartSec=5s
# Resource limits
LimitNOFILE=1048576
LimitNPROC=1048576
LimitCORE=infinity
# Security
NoNewPrivileges=true
EOF

    systemctl daemon-reload
    
    log "INFO" "Docker daemon configuration completed"
}

# Setup Docker Compose
install_docker_compose() {
    if [[ "$INSTALL_COMPOSE" == "true" ]]; then
        log "INFO" "Installing Docker Compose..."
        
        # Check if Docker Compose plugin is already installed
        if docker compose version &>/dev/null; then
            log "INFO" "Docker Compose plugin already installed: $(docker compose version)"
        else
            # Install standalone Docker Compose as fallback
            local compose_version=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep -Po '"tag_name": "\K.*?(?=")')
            local compose_url="https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-$(uname -s)-$(uname -m)"
            
            curl -L "$compose_url" -o /usr/local/bin/docker-compose
            chmod +x /usr/local/bin/docker-compose
            
            log "INFO" "Docker Compose ${compose_version} installed to /usr/local/bin/docker-compose"
        fi
    fi
}

# Add user to docker group
setup_docker_user() {
    if [[ -n "$DOCKER_USER" ]]; then
        log "INFO" "Adding user '$DOCKER_USER' to docker group..."
        
        # Check if user exists
        if ! id "$DOCKER_USER" &>/dev/null; then
            error_exit "User '$DOCKER_USER' does not exist"
        fi
        
        # Add user to docker group
        usermod -aG docker "$DOCKER_USER"
        
        log "INFO" "User '$DOCKER_USER' added to docker group"
        log "WARN" "User must logout and login for group changes to take effect"
    fi
}

# Configure Docker logging
setup_docker_logging() {
    log "INFO" "Configuring Docker logging..."
    
    # Create rsyslog configuration for Docker
    cat > /etc/rsyslog.d/30-docker.conf << 'EOF'
# Docker logging configuration
:syslogtag, startswith, "docker" /var/log/docker/docker.log
& stop
EOF

    # Create log directory
    mkdir -p /var/log/docker
    
    # Restart rsyslog
    systemctl restart rsyslog || true
}

# Setup Docker networks
create_default_networks() {
    log "INFO" "Creating default Docker networks..."
    
    # Wait for Docker to be ready
    sleep 5
    
    # Create custom bridge network with DNS
    docker network create \
        --driver bridge \
        --subnet=172.20.0.0/16 \
        --ip-range=172.20.240.0/20 \
        --opt com.docker.network.bridge.name=docker1 \
        app-network 2>/dev/null || true
    
    log "INFO" "Default networks created"
}

# Configure firewall for Docker
setup_docker_firewall() {
    log "INFO" "Configuring firewall for Docker..."
    
    # Docker manages its own iptables rules
    # Just ensure Docker's rules are not blocked
    
    if command -v ufw &>/dev/null; then
        # For UFW, we need to configure it to not interfere with Docker
        if [[ -f /etc/ufw/after.rules ]]; then
            if ! grep -q "DOCKER" /etc/ufw/after.rules; then
                log "WARN" "UFW detected. Docker requires specific UFW configuration."
                log "WARN" "See: https://docs.docker.com/network/iptables/#docker-and-ufw"
            fi
        fi
    fi
    
    log "INFO" "Firewall configuration completed"
}

# Start and enable Docker service
start_docker() {
    log "INFO" "Starting Docker service..."
    
    systemctl enable docker
    systemctl start docker
    
    # Wait for Docker to be ready
    local max_attempts=30
    for ((i=1; i<=max_attempts; i++)); do
        if docker version &>/dev/null; then
            log "INFO" "Docker service started successfully"
            return 0
        fi
        sleep 1
    done
    
    error_exit "Docker service failed to start"
}

# Verify Docker installation
verify_installation() {
    log "INFO" "Verifying Docker installation..."
    
    # Check Docker version
    if docker version &>/dev/null; then
        log "INFO" "Docker version: $(docker version --format '{{.Server.Version}}')"
    else
        error_exit "Docker is not working properly"
    fi
    
    # Test Docker with hello-world
    log "INFO" "Running Docker hello-world test..."
    if docker run --rm hello-world &>/dev/null; then
        log "INFO" "Docker hello-world test passed"
    else
        error_exit "Docker hello-world test failed"
    fi
    
    # Check Docker Compose
    if [[ "$INSTALL_COMPOSE" == "true" ]]; then
        if docker compose version &>/dev/null; then
            log "INFO" "Docker Compose is working"
        elif command -v docker-compose &>/dev/null; then
            log "INFO" "Docker Compose standalone is working"
        else
            log "WARN" "Docker Compose not found"
        fi
    fi
    
    # Display Docker info
    docker info --format 'Storage Driver: {{.Driver}}
Docker Root Dir: {{.DockerRootDir}}
Total Memory: {{.MemTotal}}
Operating System: {{.OperatingSystem}}
Kernel Version: {{.KernelVersion}}'
    
    log "INFO" "Docker installation verified successfully"
}

# Create helpful scripts
create_helper_scripts() {
    log "INFO" "Creating helper scripts..."
    
    # Docker cleanup script
    cat > /usr/local/bin/docker-cleanup << 'EOF'
#!/bin/bash
# Docker cleanup script - removes unused containers, images, and volumes

echo "Cleaning up Docker resources..."

# Remove stopped containers
docker container prune -f

# Remove unused images
docker image prune -a -f

# Remove unused volumes
docker volume prune -f

# Remove unused networks
docker network prune -f

# Show disk usage
echo -e "\nDocker disk usage:"
docker system df

echo -e "\nCleanup completed!"
EOF

    chmod +x /usr/local/bin/docker-cleanup
    
    # Docker stats script
    cat > /usr/local/bin/docker-stats << 'EOF'
#!/bin/bash
# Show Docker resource usage

docker stats --no-stream --format "table {{.Container}}\t{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"
EOF

    chmod +x /usr/local/bin/docker-stats
    
    log "INFO" "Helper scripts created in /usr/local/bin/"
}

# Print summary
print_summary() {
    echo -e "\n${GREEN}Docker Installation Summary:${NC}"
    echo "=============================="
    echo "Docker CE Version: $(docker version --format '{{.Server.Version}}')"
    echo "Storage Driver: $STORAGE_DRIVER"
    echo "Data Root: $DOCKER_DATA_ROOT"
    echo "Log Driver: $LOG_DRIVER"
    echo "Configuration: /etc/docker/daemon.json"
    echo "Service: systemctl status docker"
    
    if [[ "$INSTALL_COMPOSE" == "true" ]]; then
        echo "Docker Compose: $(docker compose version 2>/dev/null || echo 'Installed')"
    fi
    
    if [[ -n "$DOCKER_USER" ]]; then
        echo -e "\n${YELLOW}Important:${NC} User '$DOCKER_USER' has been added to the docker group."
        echo "They must logout and login again to use Docker without sudo."
    fi
    
    echo -e "\n${GREEN}Useful Commands:${NC}"
    echo "- Test Docker: docker run hello-world"
    echo "- View logs: journalctl -u docker -f"
    echo "- Cleanup: docker-cleanup"
    echo "- Stats: docker-stats"
    
    if [[ "$ENABLE_USERNS" == "true" ]]; then
        echo -e "\n${YELLOW}Security:${NC} User namespace remapping is enabled"
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
            -u|--user)
                DOCKER_USER="$2"
                shift 2
                ;;
            -c|--compose)
                INSTALL_COMPOSE=true
                shift
                ;;
            -n|--no-compose)
                INSTALL_COMPOSE=false
                shift
                ;;
            --data-root)
                DOCKER_DATA_ROOT="$2"
                shift 2
                ;;
            --userns-remap)
                ENABLE_USERNS=true
                shift
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
    
    log "INFO" "Starting Docker CE installation"
    
    # Parse arguments
    parse_args "$@"
    
    # Check prerequisites
    check_root
    detect_os
    check_system_compatibility
    
    # Install Docker
    remove_old_docker
    install_docker_ce
    configure_docker
    install_docker_compose
    setup_docker_logging
    
    # Start Docker
    start_docker
    
    # Post-installation setup
    setup_docker_user
    create_default_networks
    setup_docker_firewall
    create_helper_scripts
    
    # Verify installation
    verify_installation
    
    # Print summary
    print_summary
    
    log "INFO" "Docker CE installation completed successfully"
}

# Run main function
main "$@"