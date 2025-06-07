#!/bin/bash

# Script: install-postgresql.sh
# Purpose: Install and configure PostgreSQL database server with security hardening
# Author: Server Automation Library
# Date: 2025-01-06
# Version: 1.0

# Documentation
# =============
# Description:
#   Installs PostgreSQL database server with secure default configuration.
#   Creates a database user, configures authentication, and sets up basic monitoring.
#
# Dependencies:
#   - wget: For downloading PostgreSQL repository configuration
#   - systemd: For service management
#   - locale support: For UTF-8 encoding
#
# System Requirements:
#   - Supported OS: Ubuntu 20.04+, Debian 10+, CentOS 8+, RHEL 8+
#   - Required packages: postgresql, postgresql-contrib
#   - Minimum RAM: 1GB (2GB recommended)
#   - Disk space: 1GB minimum (varies with data)
#
# Configuration Variables:
#   - PG_VERSION: PostgreSQL version to install (default: latest)
#   - PG_DATA_DIR: Data directory location (default: /var/lib/postgresql/VERSION/main)
#   - PG_PORT: PostgreSQL port (default: 5432)
#   - DB_NAME: Initial database name (default: appdb)
#   - DB_USER: Database user (default: appuser)
#   - DB_PASS: Database password (auto-generated if not provided)
#   - ENABLE_REMOTE: Allow remote connections (default: false)
#
# Usage:
#   sudo ./install-postgresql.sh [options]
#
# Options:
#   -h, --help         Show this help message
#   -v, --verbose      Enable verbose output
#   -d, --dbname       Database name to create
#   -u, --user         Database user to create
#   -p, --password     Database user password (auto-generated if not provided)
#   -r, --remote       Enable remote connections
#   --port             Custom PostgreSQL port (default: 5432)
#
# Examples:
#   sudo ./install-postgresql.sh
#   sudo ./install-postgresql.sh --dbname myapp --user myuser
#   sudo ./install-postgresql.sh --remote --port 5433
#
# Post-Installation:
#   1. Test connection: psql -U postgres -c "\\l"
#   2. Configuration files: /etc/postgresql/VERSION/main/
#   3. Start/stop: systemctl start/stop postgresql
#   4. Logs: /var/log/postgresql/

set -euo pipefail

# Script variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/postgresql-install.log"
VERBOSE=false
PG_VERSION=""
PG_PORT=5432
DB_NAME="appdb"
DB_USER="appuser"
DB_PASS=""
ENABLE_REMOTE=false

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

generate_password() {
    if [[ -z "$DB_PASS" ]]; then
        DB_PASS=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
        log "INFO" "Generated database password"
    fi
}

install_postgresql() {
    log "INFO" "Installing PostgreSQL..."
    
    case $OS in
        ubuntu|debian)
            # Add PostgreSQL official repository
            apt-get update
            apt-get install -y wget ca-certificates
            
            # Add PostgreSQL GPG key
            wget -qO - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
            
            # Add repository
            echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
            
            apt-get update
            apt-get install -y postgresql postgresql-contrib
            
            # Get installed version
            PG_VERSION=$(psql --version | awk '{print $3}' | sed 's/\..*//')
            ;;
            
        centos|rhel|fedora)
            # Install PostgreSQL repository
            if [[ "$OS" == "centos" || "$OS" == "rhel" ]]; then
                yum install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-${OS_VERSION%%.*}-x86_64/pgdg-redhat-repo-latest.noarch.rpm
            else
                dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/F-${OS_VERSION}-x86_64/pgdg-fedora-repo-latest.noarch.rpm
            fi
            
            # Disable built-in PostgreSQL module
            if [[ "$OS" == "centos" || "$OS" == "rhel" ]] && [[ ${OS_VERSION%%.*} -ge 8 ]]; then
                dnf -qy module disable postgresql
            fi
            
            # Install PostgreSQL
            yum install -y postgresql-server postgresql-contrib
            
            # Initialize database
            /usr/pgsql-*/bin/postgresql-*-setup initdb
            
            # Get installed version
            PG_VERSION=$(ls /usr/pgsql-* | grep -oE '[0-9]+' | head -1)
            ;;
            
        *)
            error_exit "Unsupported OS: $OS"
            ;;
    esac
    
    log "INFO" "PostgreSQL $PG_VERSION installed successfully"
}

configure_postgresql() {
    log "INFO" "Configuring PostgreSQL..."
    
    # Find PostgreSQL config directory
    if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
        PG_CONFIG_DIR="/etc/postgresql/$PG_VERSION/main"
        PG_DATA_DIR="/var/lib/postgresql/$PG_VERSION/main"
    else
        PG_CONFIG_DIR="/var/lib/pgsql/$PG_VERSION/data"
        PG_DATA_DIR="$PG_CONFIG_DIR"
    fi
    
    # Backup original configurations
    cp "$PG_CONFIG_DIR/postgresql.conf" "$PG_CONFIG_DIR/postgresql.conf.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$PG_CONFIG_DIR/pg_hba.conf" "$PG_CONFIG_DIR/pg_hba.conf.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Configure postgresql.conf
    cat >> "$PG_CONFIG_DIR/postgresql.conf" << EOF

# Custom Configuration
listen_addresses = '$(if [[ "$ENABLE_REMOTE" == "true" ]]; then echo "*"; else echo "localhost"; fi)'
port = $PG_PORT
max_connections = 100
shared_buffers = 256MB
effective_cache_size = 1GB
maintenance_work_mem = 64MB
checkpoint_completion_target = 0.7
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 1.1
effective_io_concurrency = 200
work_mem = 4MB
min_wal_size = 1GB
max_wal_size = 4GB

# Logging
log_destination = 'stderr'
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_file_mode = 0600
log_truncate_on_rotation = off
log_rotation_age = 1d
log_rotation_size = 100MB
log_line_prefix = '%m [%p] %q%u@%d '
log_timezone = 'UTC'

# Security
ssl = on
ssl_cert_file = 'server.crt'
ssl_key_file = 'server.key'
EOF

    # Configure pg_hba.conf for authentication
    if [[ "$ENABLE_REMOTE" == "true" ]]; then
        # Allow remote connections with password authentication
        echo "# Allow remote connections" >> "$PG_CONFIG_DIR/pg_hba.conf"
        echo "host    all             all             0.0.0.0/0               md5" >> "$PG_CONFIG_DIR/pg_hba.conf"
        echo "host    all             all             ::/0                    md5" >> "$PG_CONFIG_DIR/pg_hba.conf"
    fi
    
    # Ensure local connections use peer authentication for postgres user
    sed -i 's/local   all             postgres                                peer/local   all             postgres                                peer/' "$PG_CONFIG_DIR/pg_hba.conf"
    
    log "INFO" "PostgreSQL configuration completed"
}

create_database_user() {
    log "INFO" "Creating database and user..."
    
    # Start PostgreSQL service
    systemctl enable postgresql
    systemctl restart postgresql
    
    # Wait for PostgreSQL to be ready
    sleep 3
    
    # Create user and database
    sudo -u postgres psql << EOF
-- Create user
CREATE USER $DB_USER WITH ENCRYPTED PASSWORD '$DB_PASS';

-- Create database
CREATE DATABASE $DB_NAME OWNER $DB_USER;

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;

-- Create monitoring user (read-only)
CREATE USER monitoring WITH ENCRYPTED PASSWORD 'monitoring_pass_$(openssl rand -hex 8)';
GRANT pg_monitor TO monitoring;
GRANT CONNECT ON DATABASE $DB_NAME TO monitoring;
GRANT USAGE ON SCHEMA public TO monitoring;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO monitoring;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO monitoring;
EOF

    log "INFO" "Database '$DB_NAME' and user '$DB_USER' created successfully"
}

setup_firewall() {
    if [[ "$ENABLE_REMOTE" == "true" ]]; then
        log "INFO" "Configuring firewall for remote access..."
        
        if command -v ufw &> /dev/null; then
            ufw allow $PG_PORT/tcp
            log "INFO" "UFW firewall rule added for port $PG_PORT"
        elif command -v firewall-cmd &> /dev/null; then
            firewall-cmd --permanent --add-port=$PG_PORT/tcp
            firewall-cmd --reload
            log "INFO" "Firewalld rule added for port $PG_PORT"
        else
            log "WARN" "No supported firewall found"
        fi
    fi
}

create_backup_script() {
    log "INFO" "Creating backup script..."
    
    mkdir -p /usr/local/bin
    
    cat > /usr/local/bin/backup-postgresql.sh << 'EOF'
#!/bin/bash
# PostgreSQL backup script

BACKUP_DIR="/var/backups/postgresql"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DB_NAME="${1:-all}"

mkdir -p "$BACKUP_DIR"

if [[ "$DB_NAME" == "all" ]]; then
    sudo -u postgres pg_dumpall | gzip > "$BACKUP_DIR/all_databases_$TIMESTAMP.sql.gz"
else
    sudo -u postgres pg_dump "$DB_NAME" | gzip > "$BACKUP_DIR/${DB_NAME}_$TIMESTAMP.sql.gz"
fi

# Keep only last 7 days of backups
find "$BACKUP_DIR" -name "*.sql.gz" -mtime +7 -delete

echo "Backup completed: $BACKUP_DIR"
EOF

    chmod +x /usr/local/bin/backup-postgresql.sh
    
    log "INFO" "Backup script created at /usr/local/bin/backup-postgresql.sh"
}

verify_installation() {
    log "INFO" "Verifying installation..."
    
    # Check if PostgreSQL is running
    if systemctl is-active --quiet postgresql; then
        log "INFO" "PostgreSQL service is running"
    else
        error_exit "PostgreSQL service is not running"
    fi
    
    # Test database connection
    if sudo -u postgres psql -c "\\l" | grep -q "$DB_NAME"; then
        log "INFO" "Database '$DB_NAME' exists"
    else
        error_exit "Database '$DB_NAME' was not created"
    fi
    
    # Test user connection
    if PGPASSWORD="$DB_PASS" psql -h localhost -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" &>/dev/null; then
        log "INFO" "User '$DB_USER' can connect to database"
    else
        log "WARN" "Could not verify user connection"
    fi
    
    log "INFO" "Installation verified successfully"
}

save_credentials() {
    local creds_file="/root/.postgresql_credentials"
    
    cat > "$creds_file" << EOF
# PostgreSQL Installation Credentials
# Generated on $(date)

Database Name: $DB_NAME
Database User: $DB_USER
Database Password: $DB_PASS
Database Port: $PG_PORT
Connection String: postgresql://$DB_USER:$DB_PASS@localhost:$PG_PORT/$DB_NAME

# Example connection:
# psql -h localhost -p $PG_PORT -U $DB_USER -d $DB_NAME

# Backup command:
# /usr/local/bin/backup-postgresql.sh $DB_NAME
EOF

    chmod 600 "$creds_file"
    log "INFO" "Credentials saved to $creds_file"
}

usage() {
    grep "^#" "$0" | grep -E "^# (Usage|Options|Examples):" -A 15 | grep -E "^#( |$)" | sed 's/^# //'
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
            -d|--dbname)
                DB_NAME="$2"
                shift 2
                ;;
            -u|--user)
                DB_USER="$2"
                shift 2
                ;;
            -p|--password)
                DB_PASS="$2"
                shift 2
                ;;
            -r|--remote)
                ENABLE_REMOTE=true
                shift
                ;;
            --port)
                PG_PORT="$2"
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
    
    log "INFO" "Starting PostgreSQL installation"
    
    parse_args "$@"
    check_root
    detect_os
    generate_password
    
    install_postgresql
    configure_postgresql
    create_database_user
    setup_firewall
    create_backup_script
    verify_installation
    save_credentials
    
    log "INFO" "PostgreSQL installation completed successfully"
    
    echo -e "\n${GREEN}Installation Summary:${NC}"
    echo "- PostgreSQL $PG_VERSION installed and running"
    echo "- Database: $DB_NAME"
    echo "- User: $DB_USER"
    echo "- Port: $PG_PORT"
    echo "- Configuration: $PG_CONFIG_DIR"
    echo "- Data directory: $PG_DATA_DIR"
    echo "- Logs: /var/log/postgresql/"
    echo "- Credentials saved to: /root/.postgresql_credentials"
    echo "- Backup script: /usr/local/bin/backup-postgresql.sh"
    
    if [[ "$ENABLE_REMOTE" == "true" ]]; then
        echo -e "\n${YELLOW}[WARNING]${NC} Remote connections enabled. Ensure firewall is properly configured!"
    fi
}

main "$@"