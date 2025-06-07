#!/bin/bash

# Script: common-functions.sh
# Purpose: Common utility functions for server installation scripts
# Author: Server Automation Library
# Date: 2025-01-06
# Version: 1.0

# Documentation
# =============
# Description:
#   Provides reusable functions for server installation scripts including:
#   - OS detection and package management
#   - Service management
#   - Network configuration helpers
#   - Security utilities
#   - Logging and error handling
#
# Usage:
#   Source this file in your scripts:
#   source /path/to/common-functions.sh

# Color codes for output
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m' # No Color

# Global variables
export OS=""
export OS_VERSION=""
export OS_CODENAME=""
export PACKAGE_MANAGER=""
export SERVICE_MANAGER=""

# ============================================================================
# Logging Functions
# ============================================================================

# Enhanced logging function with levels
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
        "DEBUG")
            if [[ "${DEBUG:-false}" == "true" ]]; then
                echo -e "${BLUE}[DEBUG]${NC} $message"
            fi
            ;;
    esac
    
    # Log to file if LOG_FILE is set
    if [[ -n "${LOG_FILE:-}" ]]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    fi
}

# Error exit function
error_exit() {
    log "ERROR" "$1"
    exit "${2:-1}"
}

# ============================================================================
# System Detection Functions
# ============================================================================

# Detect operating system and version
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
        OS_CODENAME="${VERSION_CODENAME:-}"
    elif [[ -f /etc/redhat-release ]]; then
        OS="rhel"
        OS_VERSION=$(rpm -q --queryformat '%{VERSION}' redhat-release)
    else
        error_exit "Cannot detect operating system"
    fi
    
    # Normalize OS names
    case $OS in
        ubuntu|debian)
            PACKAGE_MANAGER="apt"
            SERVICE_MANAGER="systemctl"
            ;;
        centos|rhel|fedora|rocky|almalinux)
            PACKAGE_MANAGER="yum"
            if [[ ${OS_VERSION%%.*} -ge 8 ]]; then
                PACKAGE_MANAGER="dnf"
            fi
            SERVICE_MANAGER="systemctl"
            ;;
        *)
            error_exit "Unsupported operating system: $OS"
            ;;
    esac
    
    log "INFO" "Detected: $OS $OS_VERSION (Package Manager: $PACKAGE_MANAGER)"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root (use sudo)"
    fi
}

# Check minimum system requirements
check_system_requirements() {
    local min_ram_mb=${1:-512}
    local min_disk_gb=${2:-10}
    
    # Check RAM
    local total_ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_ram_mb=$((total_ram_kb / 1024))
    
    if [[ $total_ram_mb -lt $min_ram_mb ]]; then
        error_exit "Insufficient RAM: ${total_ram_mb}MB available, ${min_ram_mb}MB required"
    fi
    
    # Check disk space
    local available_disk_gb=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
    
    if [[ $available_disk_gb -lt $min_disk_gb ]]; then
        error_exit "Insufficient disk space: ${available_disk_gb}GB available, ${min_disk_gb}GB required"
    fi
    
    log "INFO" "System requirements met (RAM: ${total_ram_mb}MB, Disk: ${available_disk_gb}GB)"
}

# ============================================================================
# Package Management Functions
# ============================================================================

# Update package manager cache
update_package_cache() {
    log "INFO" "Updating package cache..."
    
    case $PACKAGE_MANAGER in
        apt)
            apt-get update || error_exit "Failed to update package cache"
            ;;
        yum|dnf)
            $PACKAGE_MANAGER makecache || error_exit "Failed to update package cache"
            ;;
    esac
}

# Install packages
install_packages() {
    local packages=("$@")
    
    if [[ ${#packages[@]} -eq 0 ]]; then
        return 0
    fi
    
    log "INFO" "Installing packages: ${packages[*]}"
    
    case $PACKAGE_MANAGER in
        apt)
            apt-get install -y "${packages[@]}" || error_exit "Failed to install packages"
            ;;
        yum|dnf)
            $PACKAGE_MANAGER install -y "${packages[@]}" || error_exit "Failed to install packages"
            ;;
    esac
}

# Check if package is installed
is_package_installed() {
    local package=$1
    
    case $PACKAGE_MANAGER in
        apt)
            dpkg -l "$package" 2>/dev/null | grep -q "^ii"
            ;;
        yum|dnf)
            rpm -q "$package" &>/dev/null
            ;;
    esac
}

# Remove packages
remove_packages() {
    local packages=("$@")
    
    if [[ ${#packages[@]} -eq 0 ]]; then
        return 0
    fi
    
    log "INFO" "Removing packages: ${packages[*]}"
    
    case $PACKAGE_MANAGER in
        apt)
            apt-get remove -y "${packages[@]}"
            apt-get autoremove -y
            ;;
        yum|dnf)
            $PACKAGE_MANAGER remove -y "${packages[@]}"
            ;;
    esac
}

# ============================================================================
# Service Management Functions
# ============================================================================

# Enable service
enable_service() {
    local service=$1
    
    log "INFO" "Enabling service: $service"
    systemctl enable "$service" || error_exit "Failed to enable $service"
}

# Start service
start_service() {
    local service=$1
    
    log "INFO" "Starting service: $service"
    systemctl start "$service" || error_exit "Failed to start $service"
}

# Restart service
restart_service() {
    local service=$1
    
    log "INFO" "Restarting service: $service"
    systemctl restart "$service" || error_exit "Failed to restart $service"
}

# Check if service is running
is_service_running() {
    local service=$1
    systemctl is-active --quiet "$service"
}

# Wait for service to be ready
wait_for_service() {
    local service=$1
    local max_attempts=${2:-30}
    local wait_time=${3:-2}
    
    log "INFO" "Waiting for $service to be ready..."
    
    for ((i=1; i<=max_attempts; i++)); do
        if is_service_running "$service"; then
            log "INFO" "$service is ready"
            return 0
        fi
        sleep "$wait_time"
    done
    
    error_exit "$service failed to start within $((max_attempts * wait_time)) seconds"
}

# ============================================================================
# Network Functions
# ============================================================================

# Get primary IP address
get_primary_ip() {
    ip route get 1.1.1.1 | awk '{print $7; exit}'
}

# Check if port is open
is_port_open() {
    local port=$1
    local host=${2:-localhost}
    
    nc -z -w5 "$host" "$port" &>/dev/null
}

# Wait for port to be available
wait_for_port() {
    local port=$1
    local host=${2:-localhost}
    local max_attempts=${3:-30}
    local wait_time=${4:-2}
    
    log "INFO" "Waiting for port $port on $host..."
    
    for ((i=1; i<=max_attempts; i++)); do
        if is_port_open "$port" "$host"; then
            log "INFO" "Port $port is available"
            return 0
        fi
        sleep "$wait_time"
    done
    
    error_exit "Port $port not available within $((max_attempts * wait_time)) seconds"
}

# Configure firewall rules
configure_firewall() {
    local port=$1
    local protocol=${2:-tcp}
    
    if command -v ufw &>/dev/null; then
        log "INFO" "Adding UFW rule for port $port/$protocol"
        ufw allow "$port/$protocol"
    elif command -v firewall-cmd &>/dev/null; then
        log "INFO" "Adding firewalld rule for port $port/$protocol"
        firewall-cmd --permanent --add-port="$port/$protocol"
        firewall-cmd --reload
    else
        log "WARN" "No supported firewall found"
    fi
}

# ============================================================================
# Security Functions
# ============================================================================

# Generate secure password
generate_password() {
    local length=${1:-20}
    openssl rand -base64 48 | tr -d "=+/" | cut -c1-"$length"
}

# Create system user
create_system_user() {
    local username=$1
    local home_dir=${2:-/var/lib/$username}
    local shell=${3:-/bin/false}
    
    if id "$username" &>/dev/null; then
        log "INFO" "User $username already exists"
        return 0
    fi
    
    log "INFO" "Creating system user: $username"
    useradd --system --home-dir "$home_dir" --shell "$shell" "$username"
}

# Set secure file permissions
set_secure_permissions() {
    local path=$1
    local owner=${2:-root}
    local group=${3:-root}
    local mode=${4:-640}
    
    chown "$owner:$group" "$path"
    chmod "$mode" "$path"
}

# Backup file with timestamp
backup_file() {
    local file=$1
    local backup_dir=${2:-$(dirname "$file")}
    
    if [[ -f "$file" ]]; then
        local backup_name="${backup_dir}/$(basename "$file").backup.$(date +%Y%m%d_%H%M%S)"
        cp "$file" "$backup_name"
        log "INFO" "Backed up $file to $backup_name"
    fi
}

# ============================================================================
# Validation Functions
# ============================================================================

# Validate IP address
is_valid_ip() {
    local ip=$1
    local valid_regex="^([0-9]{1,3}\.){3}[0-9]{1,3}$"
    
    if [[ $ip =~ $valid_regex ]]; then
        for octet in $(echo "$ip" | tr '.' ' '); do
            if [[ $octet -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# Validate port number
is_valid_port() {
    local port=$1
    
    if [[ $port =~ ^[0-9]+$ ]] && [[ $port -ge 1 ]] && [[ $port -le 65535 ]]; then
        return 0
    fi
    return 1
}

# Validate domain name
is_valid_domain() {
    local domain=$1
    local valid_regex="^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$"
    
    [[ $domain =~ $valid_regex ]]
}

# ============================================================================
# Utility Functions
# ============================================================================

# Create directory if not exists
ensure_directory() {
    local dir=$1
    local owner=${2:-root}
    local group=${3:-root}
    local mode=${4:-755}
    
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        chown "$owner:$group" "$dir"
        chmod "$mode" "$dir"
        log "INFO" "Created directory: $dir"
    fi
}

# Download file with retry
download_file() {
    local url=$1
    local destination=$2
    local max_attempts=${3:-3}
    
    for ((i=1; i<=max_attempts; i++)); do
        if wget -q -O "$destination" "$url"; then
            log "INFO" "Downloaded: $url"
            return 0
        fi
        log "WARN" "Download attempt $i failed"
        sleep 2
    done
    
    error_exit "Failed to download $url after $max_attempts attempts"
}

# Create self-signed SSL certificate
create_self_signed_cert() {
    local cert_dir=$1
    local domain=${2:-localhost}
    local days=${3:-365}
    
    ensure_directory "$cert_dir"
    
    openssl req -x509 -nodes -days "$days" -newkey rsa:2048 \
        -keyout "$cert_dir/server.key" \
        -out "$cert_dir/server.crt" \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=$domain" \
        2>/dev/null
    
    set_secure_permissions "$cert_dir/server.key" root root 600
    set_secure_permissions "$cert_dir/server.crt" root root 644
    
    log "INFO" "Created self-signed certificate for $domain"
}

# Check command availability
require_command() {
    local cmd=$1
    
    if ! command -v "$cmd" &>/dev/null; then
        error_exit "Required command not found: $cmd"
    fi
}

# Run command with timeout
run_with_timeout() {
    local timeout=$1
    shift
    
    timeout "$timeout" "$@"
    local exit_code=$?
    
    if [[ $exit_code -eq 124 ]]; then
        error_exit "Command timed out after ${timeout}s: $*"
    fi
    
    return $exit_code
}

# ============================================================================
# Initialization
# ============================================================================

# Auto-detect OS if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    detect_os
fi