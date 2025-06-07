#!/bin/bash

# Script: install-nginx.sh
# Purpose: Install and configure Nginx web server with basic security settings
# Author: Server Automation Library
# Date: 2025-01-06
# Version: 1.0

# Documentation
# =============
# Description:
#   Installs Nginx web server with optimized configuration for production use.
#   Includes basic security headers, SSL configuration templates, and performance tuning.
#
# Dependencies:
#   - curl: For downloading additional resources
#   - openssl: For generating self-signed certificates (optional)
#   - systemd: For service management
#
# System Requirements:
#   - Supported OS: Ubuntu 20.04+, Debian 10+, CentOS 8+, RHEL 8+
#   - Required packages: nginx, curl, openssl
#   - Minimum RAM: 512MB
#   - Disk space: 100MB
#
# Configuration Variables:
#   - NGINX_USER: User to run Nginx (default: www-data or nginx)
#   - NGINX_PORT: Default HTTP port (default: 80)
#   - ENABLE_SSL: Enable SSL configuration (default: false)
#   - SSL_CERT_PATH: Path to SSL certificate (default: /etc/nginx/ssl)
#
# Usage:
#   sudo ./install-nginx.sh [options]
#
# Options:
#   -h, --help     Show this help message
#   -v, --verbose  Enable verbose output
#   -s, --ssl      Enable SSL configuration
#   -p, --port     Set custom port (default: 80)
#
# Examples:
#   sudo ./install-nginx.sh
#   sudo ./install-nginx.sh --ssl
#   sudo ./install-nginx.sh --port 8080
#
# Post-Installation:
#   1. Test configuration: nginx -t
#   2. Configuration files: /etc/nginx/nginx.conf, /etc/nginx/sites-available/
#   3. Start/stop: systemctl start/stop nginx
#   4. Logs: /var/log/nginx/access.log, /var/log/nginx/error.log

set -euo pipefail

# Script variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/nginx-install.log"
VERBOSE=false
ENABLE_SSL=false
NGINX_PORT=80

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logging function
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

install_nginx() {
    log "INFO" "Installing Nginx..."
    
    case $OS in
        ubuntu|debian)
            apt-get update
            apt-get install -y nginx curl openssl
            NGINX_USER="www-data"
            ;;
        centos|rhel|fedora)
            yum install -y epel-release
            yum install -y nginx curl openssl
            NGINX_USER="nginx"
            ;;
        *)
            error_exit "Unsupported OS: $OS"
            ;;
    esac
    
    log "INFO" "Nginx installed successfully"
}

configure_nginx() {
    log "INFO" "Configuring Nginx..."
    
    # Backup original configuration
    cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup.$(date +%Y%m%d_%H%M%S)
    
    # Create optimized nginx.conf
    cat > /etc/nginx/nginx.conf << 'EOF'
user NGINX_USER;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /run/nginx.pid;

events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Logging
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    access_log /var/log/nginx/access.log main;

    # Performance
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 20M;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/json application/javascript application/xml+rss;

    # Hide nginx version
    server_tokens off;

    # Include configs
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF

    # Replace NGINX_USER placeholder
    sed -i "s/NGINX_USER/$NGINX_USER/g" /etc/nginx/nginx.conf
    
    # Create default site configuration
    mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
    
    cat > /etc/nginx/sites-available/default << EOF
server {
    listen $NGINX_PORT default_server;
    listen [::]:$NGINX_PORT default_server;
    
    root /var/www/html;
    index index.html index.htm index.nginx-debian.html;
    
    server_name _;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    # Security
    location ~ /\\.ht {
        deny all;
    }
    
    # Logging
    access_log /var/log/nginx/default-access.log;
    error_log /var/log/nginx/default-error.log;
}
EOF

    # Enable default site
    ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
    
    # Remove default config if exists
    rm -f /etc/nginx/sites-enabled/default.conf
    
    log "INFO" "Nginx configuration completed"
}

setup_ssl() {
    if [[ "$ENABLE_SSL" == "true" ]]; then
        log "INFO" "Setting up SSL configuration..."
        
        mkdir -p /etc/nginx/ssl
        
        # Generate self-signed certificate for testing
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout /etc/nginx/ssl/selfsigned.key \
            -out /etc/nginx/ssl/selfsigned.crt \
            -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"
        
        # Create SSL configuration
        cat > /etc/nginx/sites-available/default-ssl << 'EOF'
server {
    listen 443 ssl http2 default_server;
    listen [::]:443 ssl http2 default_server;
    
    ssl_certificate /etc/nginx/ssl/selfsigned.crt;
    ssl_certificate_key /etc/nginx/ssl/selfsigned.key;
    
    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # HSTS
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    
    root /var/www/html;
    index index.html index.htm;
    
    server_name _;
    
    location / {
        try_files $uri $uri/ =404;
    }
}

# HTTP to HTTPS redirect
server {
    listen 80;
    listen [::]:80;
    server_name _;
    return 301 https://$host$request_uri;
}
EOF
        
        ln -sf /etc/nginx/sites-available/default-ssl /etc/nginx/sites-enabled/default-ssl
        
        log "INFO" "SSL configuration completed (using self-signed certificate)"
    fi
}

setup_firewall() {
    log "INFO" "Configuring firewall..."
    
    if command -v ufw &> /dev/null; then
        ufw allow $NGINX_PORT/tcp
        if [[ "$ENABLE_SSL" == "true" ]]; then
            ufw allow 443/tcp
        fi
        log "INFO" "UFW firewall rules added"
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port=$NGINX_PORT/tcp
        if [[ "$ENABLE_SSL" == "true" ]]; then
            firewall-cmd --permanent --add-port=443/tcp
        fi
        firewall-cmd --reload
        log "INFO" "Firewalld rules added"
    else
        log "WARN" "No supported firewall found"
    fi
}

start_nginx() {
    log "INFO" "Starting Nginx service..."
    
    # Test configuration
    nginx -t || error_exit "Nginx configuration test failed"
    
    # Enable and start service
    systemctl enable nginx
    systemctl restart nginx
    
    log "INFO" "Nginx service started"
}

verify_installation() {
    log "INFO" "Verifying installation..."
    
    # Check if nginx is running
    if systemctl is-active --quiet nginx; then
        log "INFO" "Nginx is running"
    else
        error_exit "Nginx is not running"
    fi
    
    # Test HTTP response
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:$NGINX_PORT | grep -q "200\|301"; then
        log "INFO" "Nginx is responding on port $NGINX_PORT"
    else
        log "WARN" "Nginx may not be responding correctly on port $NGINX_PORT"
    fi
    
    log "INFO" "Installation verified successfully"
}

usage() {
    grep "^#" "$0" | grep -E "^# (Usage|Options|Examples):" -A 10 | grep -E "^#( |$)" | sed 's/^# //'
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
            -s|--ssl)
                ENABLE_SSL=true
                shift
                ;;
            -p|--port)
                NGINX_PORT="$2"
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
    
    log "INFO" "Starting Nginx installation"
    
    parse_args "$@"
    check_root
    detect_os
    
    install_nginx
    configure_nginx
    setup_ssl
    setup_firewall
    start_nginx
    verify_installation
    
    log "INFO" "Nginx installation completed successfully"
    echo -e "\n${GREEN}Installation Summary:${NC}"
    echo "- Nginx installed and running on port $NGINX_PORT"
    echo "- Configuration: /etc/nginx/nginx.conf"
    echo "- Sites: /etc/nginx/sites-available/"
    echo "- Logs: /var/log/nginx/"
    echo "- Service: systemctl status nginx"
    
    if [[ "$ENABLE_SSL" == "true" ]]; then
        echo "- SSL enabled with self-signed certificate"
        echo "- Replace certificates in /etc/nginx/ssl/ for production"
    fi
}

main "$@"