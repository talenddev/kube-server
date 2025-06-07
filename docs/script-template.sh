#!/bin/bash

# Script: script-name.sh
# Purpose: Brief description of what this script does
# Author: Your Name
# Date: $(date +%Y-%m-%d)
# Version: 1.0

# Documentation
# =============
# Description:
#   Detailed description of what this script accomplishes
#
# Dependencies:
#   - dependency1: Description of why needed
#   - dependency2: Description of why needed
#
# System Requirements:
#   - Supported OS: Ubuntu 20.04+, Debian 10+, CentOS 8+, RHEL 8+
#   - Required packages: package1, package2
#   - Minimum RAM: 1GB
#   - Disk space: 10GB
#
# Configuration Variables:
#   - VAR1: Description (default: value)
#   - VAR2: Description (default: value)
#
# Usage:
#   sudo ./script-name.sh [options]
#
# Options:
#   -h, --help     Show this help message
#   -v, --verbose  Enable verbose output
#   -d, --dry-run  Show what would be done without making changes
#
# Examples:
#   sudo ./script-name.sh
#   sudo ./script-name.sh --verbose
#
# Post-Installation:
#   1. Step to verify installation
#   2. Configuration files location
#   3. How to start/stop services
#   4. Log file locations

# Exit on error, undefined variable, or pipe failure
set -euo pipefail

# Script variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/$(basename "$0" .sh).log"
VERBOSE=false
DRY_RUN=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

# Error handling
error_exit() {
    log "ERROR" "$1"
    exit 1
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root (use sudo)"
    fi
}

# Detect OS and version
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

# Install dependencies based on OS
install_dependencies() {
    log "INFO" "Installing dependencies..."
    
    case $OS in
        ubuntu|debian)
            apt-get update
            apt-get install -y package1 package2
            ;;
        centos|rhel|fedora)
            yum install -y package1 package2
            ;;
        *)
            error_exit "Unsupported OS: $OS"
            ;;
    esac
    
    log "INFO" "Dependencies installed successfully"
}

# Main installation function
main_install() {
    log "INFO" "Starting main installation..."
    
    # Add your installation steps here
    
    log "INFO" "Installation completed successfully"
}

# Verify installation
verify_installation() {
    log "INFO" "Verifying installation..."
    
    # Add verification steps here
    
    log "INFO" "Verification completed"
}

# Print usage
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
            -d|--dry-run)
                DRY_RUN=true
                log "INFO" "Running in dry-run mode"
                shift
                ;;
            *)
                error_exit "Unknown option: $1"
                ;;
        esac
    done
}

# Main execution
main() {
    # Initialize log file
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    
    log "INFO" "Starting script execution"
    
    # Parse arguments
    parse_args "$@"
    
    # Check prerequisites
    check_root
    detect_os
    
    # Perform installation
    if [[ "$DRY_RUN" == "false" ]]; then
        install_dependencies
        main_install
        verify_installation
    else
        log "INFO" "Dry run - no changes made"
    fi
    
    log "INFO" "Script execution completed"
}

# Run main function
main "$@"