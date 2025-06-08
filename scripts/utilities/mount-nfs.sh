#!/bin/bash

# Script: mount-nfs.sh
# Purpose: Mount NFS shares with comprehensive configuration and error handling
# Author: Server Automation Library
# Date: 2025-01-06
# Version: 1.0

# Documentation
# =============
# Description:
#   A comprehensive script for mounting NFS shares with automatic dependency
#   installation, configuration validation, performance optimization, and
#   persistent mount setup via /etc/fstab.
#
# Features:
#   - Automatic NFS client installation
#   - NFS server connectivity testing
#   - Mount point creation and validation
#   - Performance optimization options
#   - Persistent mounting via /etc/fstab
#   - Mount option customization
#   - Security configurations
#   - Backup and rollback functionality
#   - Comprehensive logging and error handling
#
# System Requirements:
#   - Linux with systemd
#   - Root privileges for mounting
#   - Network connectivity to NFS server
#
# Usage:
#   ./mount-nfs.sh [options] nfs-server:/path local-mount-point
#
# Options:
#   -h, --help              Show this help message
#   -o, --options OPTIONS   NFS mount options (default: rw,hard,intr)
#   -t, --type TYPE         NFS version (nfs, nfs4) (default: nfs4)
#   -p, --persistent        Add to /etc/fstab for persistent mounting
#   -f, --force             Force mount even if target exists
#   --no-install            Don't install NFS client packages
#   --no-test               Don't test NFS server connectivity
#   --backup                Backup /etc/fstab before modification
#   --uid UID               User ID for mount (default: current user)
#   --gid GID               Group ID for mount (default: current group)
#   --mode MODE             Directory permissions (default: 755)
#   --timeout SECONDS       NFS timeout in seconds (default: 30)
#   --retrans COUNT         Number of retransmissions (default: 3)
#   --rsize SIZE            Read buffer size (default: 32768)
#   --wsize SIZE            Write buffer size (default: 32768)
#   --soft                  Use soft mount (default: hard)
#   --readonly              Mount as read-only
#   --noexec                Mount with noexec option
#   --nosuid                Mount with nosuid option
#   --nodev                 Mount with nodev option
#   -v, --verbose           Verbose output
#   --dry-run               Show what would be done without executing
#
# NFS Versions:
#   nfs4       - NFSv4 (recommended, default)
#   nfs        - NFSv3 (legacy compatibility)
#
# Common Mount Options:
#   rw/ro      - Read-write/read-only
#   hard/soft  - Hard/soft mount
#   intr       - Allow interruption
#   bg         - Retry in background
#   tcp/udp    - Transport protocol
#   sec        - Security flavor
#
# Examples:
#   # Basic NFS mount
#   sudo ./mount-nfs.sh 192.168.1.100:/exports/data /mnt/nfs-data
#
#   # Persistent mount with custom options
#   sudo ./mount-nfs.sh --persistent --options "rw,hard,intr,tcp" \
#        nfs-server.local:/shared /mnt/shared
#
#   # Read-only mount with security options
#   sudo ./mount-nfs.sh --readonly --nosuid --nodev --noexec \
#        192.168.1.100:/public /mnt/public
#
#   # High-performance mount
#   sudo ./mount-nfs.sh --rsize 65536 --wsize 65536 --persistent \
#        nfs-server:/fast-storage /mnt/fast
#
#   # Test connectivity without mounting
#   ./mount-nfs.sh --dry-run --no-install 192.168.1.100:/exports /mnt/test
#
# Troubleshooting:
#   - Check network connectivity: ping nfs-server
#   - Test NFS service: showmount -e nfs-server
#   - Check mount status: mount | grep nfs
#   - View NFS statistics: nfsstat
#   - Check logs: journalctl -u rpc-statd

set -euo pipefail

# Script variables
SCRIPT_NAME=$(basename "$0")
NFS_SERVER=""
NFS_PATH=""
LOCAL_MOUNT=""
NFS_TYPE="nfs4"
MOUNT_OPTIONS="rw,hard,intr"
PERSISTENT=false
FORCE=false
INSTALL_CLIENT=true
TEST_CONNECTIVITY=true
BACKUP_FSTAB=false
MOUNT_UID=""
MOUNT_GID=""
MOUNT_MODE="755"
NFS_TIMEOUT="30"
NFS_RETRANS="3"
READ_SIZE="32768"
WRITE_SIZE="32768"
SOFT_MOUNT=false
READONLY=false
NO_EXEC=false
NO_SUID=false
NO_DEV=false
VERBOSE=false
DRY_RUN=false

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Functions
# ---------

# Source common functions if available
if [[ -f "$(dirname "$0")/common-functions.sh" ]]; then
    source "$(dirname "$0")/common-functions.sh"
else
    # Basic logging functions if common-functions.sh not available
    log() {
        local level=$1
        shift
        local message="$@"
        case $level in
            "INFO") echo -e "${GREEN}[INFO]${NC} $message" ;;
            "WARN") echo -e "${YELLOW}[WARN]${NC} $message" ;;
            "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
            "DEBUG") [[ "$VERBOSE" == "true" ]] && echo -e "${BLUE}[DEBUG]${NC} $message" ;;
        esac
    }
    
    error_exit() {
        log "ERROR" "$1"
        exit "${2:-1}"
    }
fi

# Show usage
usage() {
    grep "^#" "$0" | grep -E "^# (Usage|Options|Examples):" -A 40 | grep -E "^#( |$)" | sed 's/^# //'
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root for mounting operations"
    fi
}

# Detect package manager and install NFS client
install_nfs_client() {
    if [[ "$INSTALL_CLIENT" != "true" ]]; then
        return 0
    fi
    
    log "INFO" "Installing NFS client packages..."
    
    # Detect package manager
    if command -v apt-get &>/dev/null; then
        log "DEBUG" "Using apt package manager"
        apt-get update
        apt-get install -y nfs-common nfs4-acl-tools
    elif command -v yum &>/dev/null; then
        log "DEBUG" "Using yum package manager"
        yum install -y nfs-utils nfs4-acl-tools
    elif command -v dnf &>/dev/null; then
        log "DEBUG" "Using dnf package manager"
        dnf install -y nfs-utils nfs4-acl-tools
    elif command -v zypper &>/dev/null; then
        log "DEBUG" "Using zypper package manager"
        zypper install -y nfs-client nfs4-acl-tools
    elif command -v pacman &>/dev/null; then
        log "DEBUG" "Using pacman package manager"
        pacman -S --noconfirm nfs-utils
    else
        log "WARN" "No supported package manager found. Please install NFS client manually."
        return 1
    fi
    
    # Start and enable RPC services
    log "INFO" "Starting NFS client services..."
    systemctl enable rpc-statd 2>/dev/null || true
    systemctl start rpc-statd 2>/dev/null || true
    
    if [[ "$NFS_TYPE" == "nfs4" ]]; then
        systemctl enable nfs-client.target 2>/dev/null || true
        systemctl start nfs-client.target 2>/dev/null || true
    fi
}

# Parse NFS server and path
parse_nfs_target() {
    local nfs_target="$1"
    
    if [[ "$nfs_target" =~ ^([^:]+):(.+)$ ]]; then
        NFS_SERVER="${BASH_REMATCH[1]}"
        NFS_PATH="${BASH_REMATCH[2]}"
    else
        error_exit "Invalid NFS target format. Use: server:/path"
    fi
    
    log "DEBUG" "NFS Server: $NFS_SERVER"
    log "DEBUG" "NFS Path: $NFS_PATH"
}

# Test NFS server connectivity
test_nfs_connectivity() {
    if [[ "$TEST_CONNECTIVITY" != "true" ]]; then
        return 0
    fi
    
    log "INFO" "Testing connectivity to NFS server: $NFS_SERVER"
    
    # Test basic network connectivity
    if ! ping -c 1 -W 5 "$NFS_SERVER" &>/dev/null; then
        error_exit "Cannot reach NFS server: $NFS_SERVER"
    fi
    
    # Test NFS service
    log "DEBUG" "Testing NFS service availability..."
    if command -v showmount &>/dev/null; then
        if ! timeout 10 showmount -e "$NFS_SERVER" &>/dev/null; then
            log "WARN" "Cannot query NFS exports from $NFS_SERVER"
            log "WARN" "This might be normal if exports are restricted"
        else
            log "DEBUG" "NFS exports available from $NFS_SERVER"
        fi
    fi
    
    # Test specific NFS version
    log "DEBUG" "Testing $NFS_TYPE connectivity..."
    if [[ "$NFS_TYPE" == "nfs4" ]]; then
        # Test NFSv4 port (2049)
        if ! timeout 5 bash -c "</dev/tcp/$NFS_SERVER/2049" 2>/dev/null; then
            log "WARN" "NFSv4 port (2049) may not be accessible on $NFS_SERVER"
        fi
    else
        # Test NFSv3 ports (111, 2049)
        if ! timeout 5 bash -c "</dev/tcp/$NFS_SERVER/111" 2>/dev/null; then
            log "WARN" "NFS portmapper (111) may not be accessible on $NFS_SERVER"
        fi
    fi
}

# Create and validate mount point
setup_mount_point() {
    log "INFO" "Setting up mount point: $LOCAL_MOUNT"
    
    # Check if mount point already exists and is mounted
    if mountpoint -q "$LOCAL_MOUNT" 2>/dev/null; then
        if [[ "$FORCE" == "true" ]]; then
            log "WARN" "Mount point is already mounted, unmounting..."
            umount "$LOCAL_MOUNT" || error_exit "Failed to unmount $LOCAL_MOUNT"
        else
            error_exit "Mount point $LOCAL_MOUNT is already mounted. Use --force to override."
        fi
    fi
    
    # Create mount point if it doesn't exist
    if [[ ! -d "$LOCAL_MOUNT" ]]; then
        log "DEBUG" "Creating mount point directory..."
        mkdir -p "$LOCAL_MOUNT"
    elif [[ "$(ls -A "$LOCAL_MOUNT" 2>/dev/null)" ]] && [[ "$FORCE" != "true" ]]; then
        error_exit "Mount point $LOCAL_MOUNT is not empty. Use --force to override."
    fi
    
    # Set ownership and permissions
    if [[ -n "$MOUNT_UID" || -n "$MOUNT_GID" ]]; then
        local chown_target=""
        if [[ -n "$MOUNT_UID" && -n "$MOUNT_GID" ]]; then
            chown_target="$MOUNT_UID:$MOUNT_GID"
        elif [[ -n "$MOUNT_UID" ]]; then
            chown_target="$MOUNT_UID"
        else
            chown_target=":$MOUNT_GID"
        fi
        
        log "DEBUG" "Setting ownership: $chown_target"
        chown "$chown_target" "$LOCAL_MOUNT"
    fi
    
    if [[ -n "$MOUNT_MODE" ]]; then
        log "DEBUG" "Setting permissions: $MOUNT_MODE"
        chmod "$MOUNT_MODE" "$LOCAL_MOUNT"
    fi
}

# Build mount options string
build_mount_options() {
    local options=()
    
    # Start with base options
    IFS=',' read -ra base_opts <<< "$MOUNT_OPTIONS"
    options+=("${base_opts[@]}")
    
    # Add version-specific options
    if [[ "$NFS_TYPE" == "nfs4" ]]; then
        options+=("vers=4")
    else
        options+=("vers=3")
    fi
    
    # Add performance options
    options+=("rsize=$READ_SIZE")
    options+=("wsize=$WRITE_SIZE")
    options+=("timeo=$NFS_TIMEOUT")
    options+=("retrans=$NFS_RETRANS")
    
    # Add mount type options
    if [[ "$SOFT_MOUNT" == "true" ]]; then
        # Remove hard option and add soft
        options=($(printf '%s\n' "${options[@]}" | grep -v '^hard$'))
        options+=("soft")
    fi
    
    if [[ "$READONLY" == "true" ]]; then
        options=($(printf '%s\n' "${options[@]}" | grep -v '^rw$'))
        options+=("ro")
    fi
    
    # Add security options
    if [[ "$NO_EXEC" == "true" ]]; then
        options+=("noexec")
    fi
    
    if [[ "$NO_SUID" == "true" ]]; then
        options+=("nosuid")
    fi
    
    if [[ "$NO_DEV" == "true" ]]; then
        options+=("nodev")
    fi
    
    # Remove duplicates and join
    local unique_options=($(printf '%s\n' "${options[@]}" | sort -u))
    local final_options=$(IFS=,; echo "${unique_options[*]}")
    
    log "DEBUG" "Final mount options: $final_options"
    echo "$final_options"
}

# Perform the NFS mount
mount_nfs() {
    local mount_options=$(build_mount_options)
    local nfs_source="$NFS_SERVER:$NFS_PATH"
    
    log "INFO" "Mounting NFS share: $nfs_source -> $LOCAL_MOUNT"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would execute: mount -t $NFS_TYPE -o $mount_options $nfs_source $LOCAL_MOUNT"
        return 0
    fi
    
    # Attempt the mount
    if ! mount -t "$NFS_TYPE" -o "$mount_options" "$nfs_source" "$LOCAL_MOUNT"; then
        error_exit "Failed to mount NFS share"
    fi
    
    log "INFO" "Successfully mounted NFS share"
    
    # Verify mount
    if ! mountpoint -q "$LOCAL_MOUNT"; then
        error_exit "Mount verification failed"
    fi
    
    # Display mount information
    log "INFO" "Mount details:"
    mount | grep "$LOCAL_MOUNT" | while read -r line; do
        log "INFO" "  $line"
    done
}

# Add entry to /etc/fstab for persistent mounting
add_to_fstab() {
    if [[ "$PERSISTENT" != "true" ]]; then
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would add to /etc/fstab for persistent mounting"
        return 0
    fi
    
    local nfs_source="$NFS_SERVER:$NFS_PATH"
    local mount_options=$(build_mount_options)
    local fstab_entry="$nfs_source $LOCAL_MOUNT $NFS_TYPE $mount_options 0 0"
    
    # Backup fstab if requested
    if [[ "$BACKUP_FSTAB" == "true" ]]; then
        local backup_file="/etc/fstab.backup.$(date +%Y%m%d_%H%M%S)"
        log "INFO" "Backing up /etc/fstab to $backup_file"
        cp /etc/fstab "$backup_file"
    fi
    
    # Check if entry already exists
    if grep -q "$nfs_source.*$LOCAL_MOUNT" /etc/fstab; then
        log "WARN" "Similar entry already exists in /etc/fstab"
        if [[ "$FORCE" != "true" ]]; then
            log "WARN" "Skipping fstab modification. Use --force to override."
            return 0
        fi
        
        # Remove existing entry
        log "INFO" "Removing existing fstab entry..."
        sed -i "\|$nfs_source.*$LOCAL_MOUNT|d" /etc/fstab
    fi
    
    # Add new entry
    log "INFO" "Adding entry to /etc/fstab for persistent mounting"
    echo "$fstab_entry" >> /etc/fstab
    
    log "DEBUG" "Added fstab entry: $fstab_entry"
    
    # Test fstab entry
    log "INFO" "Testing fstab entry..."
    if ! mount -a --fake; then
        log "ERROR" "fstab syntax error detected!"
        log "ERROR" "Please check /etc/fstab manually"
    fi
}

# Display mount information
show_mount_info() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    log "INFO" "NFS mount information:"
    echo
    echo "  Source: $NFS_SERVER:$NFS_PATH"
    echo "  Mount Point: $LOCAL_MOUNT"
    echo "  NFS Type: $NFS_TYPE"
    echo "  Options: $(build_mount_options)"
    echo "  Persistent: $PERSISTENT"
    echo
    
    # Show disk usage
    if command -v df &>/dev/null; then
        echo "Disk Usage:"
        df -h "$LOCAL_MOUNT" 2>/dev/null || true
        echo
    fi
    
    # Show NFS statistics if available
    if command -v nfsstat &>/dev/null; then
        echo "NFS Statistics:"
        nfsstat -c 2>/dev/null | head -10 || true
    fi
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -o|--options)
                MOUNT_OPTIONS="$2"
                shift 2
                ;;
            -t|--type)
                NFS_TYPE="$2"
                shift 2
                ;;
            -p|--persistent)
                PERSISTENT=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            --no-install)
                INSTALL_CLIENT=false
                shift
                ;;
            --no-test)
                TEST_CONNECTIVITY=false
                shift
                ;;
            --backup)
                BACKUP_FSTAB=true
                shift
                ;;
            --uid)
                MOUNT_UID="$2"
                shift 2
                ;;
            --gid)
                MOUNT_GID="$2"
                shift 2
                ;;
            --mode)
                MOUNT_MODE="$2"
                shift 2
                ;;
            --timeout)
                NFS_TIMEOUT="$2"
                shift 2
                ;;
            --retrans)
                NFS_RETRANS="$2"
                shift 2
                ;;
            --rsize)
                READ_SIZE="$2"
                shift 2
                ;;
            --wsize)
                WRITE_SIZE="$2"
                shift 2
                ;;
            --soft)
                SOFT_MOUNT=true
                shift
                ;;
            --readonly)
                READONLY=true
                shift
                ;;
            --noexec)
                NO_EXEC=true
                shift
                ;;
            --nosuid)
                NO_SUID=true
                shift
                ;;
            --nodev)
                NO_DEV=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -*)
                error_exit "Unknown option: $1"
                ;;
            *)
                if [[ -z "$NFS_SERVER" ]]; then
                    # First positional argument is NFS target
                    parse_nfs_target "$1"
                elif [[ -z "$LOCAL_MOUNT" ]]; then
                    # Second positional argument is local mount point
                    LOCAL_MOUNT="$1"
                else
                    error_exit "Too many arguments. Usage: $SCRIPT_NAME [options] nfs-server:/path local-mount-point"
                fi
                shift
                ;;
        esac
    done
    
    # Validate required arguments
    if [[ -z "$NFS_SERVER" || -z "$LOCAL_MOUNT" ]]; then
        error_exit "Both NFS server and local mount point are required"
    fi
    
    # Convert relative path to absolute
    LOCAL_MOUNT=$(realpath -m "$LOCAL_MOUNT")
    
    # Validate NFS type
    if [[ "$NFS_TYPE" != "nfs" && "$NFS_TYPE" != "nfs4" ]]; then
        error_exit "Invalid NFS type: $NFS_TYPE. Must be 'nfs' or 'nfs4'"
    fi
}

# Main function
main() {
    log "INFO" "Starting NFS mount process"
    
    # Parse arguments
    parse_args "$@"
    
    # Check if dry run
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "DRY RUN MODE - No changes will be made"
    fi
    
    # Check root privileges (only if not dry run)
    if [[ "$DRY_RUN" != "true" ]]; then
        check_root
    fi
    
    # Install NFS client if needed
    if [[ "$DRY_RUN" != "true" ]]; then
        install_nfs_client
    fi
    
    # Test connectivity
    test_nfs_connectivity
    
    # Setup mount point
    if [[ "$DRY_RUN" != "true" ]]; then
        setup_mount_point
    fi
    
    # Perform mount
    mount_nfs
    
    # Add to fstab if requested
    add_to_fstab
    
    # Show mount information
    show_mount_info
    
    log "INFO" "NFS mount process completed successfully"
}

# Run main function
main "$@"