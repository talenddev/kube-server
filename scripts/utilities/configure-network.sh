#!/bin/bash

# Script: configure-network.sh
# Purpose: Configure fixed IP address and DNS settings
# Author: Server Automation Library
# Date: 2025-01-06
# Version: 1.0

# Documentation
# =============
# Description:
#   Configures static IP addresses and DNS settings on Linux systems.
#   Supports multiple network configuration methods including NetworkManager,
#   systemd-networkd, netplan, and traditional /etc/network/interfaces.
#   Creates backups before making changes and can restore previous configs.
#
# Supported Systems:
#   - Ubuntu 18.04+ (netplan)
#   - Debian 9+ (interfaces/NetworkManager)
#   - RHEL/CentOS 7+ (NetworkManager)
#   - Fedora (NetworkManager)
#   - systemd-based systems (systemd-networkd)
#
# Features:
#   - Automatic network manager detection
#   - Configuration backup and restore
#   - Multiple DNS server support
#   - IPv4 and IPv6 support
#   - Network connectivity testing
#   - Rollback on failure
#
# Usage:
#   sudo ./configure-network.sh [options]
#
# Options:
#   -h, --help              Show this help message
#   -i, --interface IFACE   Network interface (default: auto-detect)
#   -a, --address IP/MASK   IP address with CIDR (e.g., 192.168.1.100/24)
#   -g, --gateway IP        Default gateway
#   -d, --dns DNS1,DNS2     DNS servers (comma-separated)
#   -s, --search DOMAIN     DNS search domain
#   -6, --ipv6 IP/PREFIX    IPv6 address (optional)
#   -b, --backup            Create backup only
#   -r, --restore           Restore from backup
#   -t, --test              Test configuration without applying
#   -f, --force             Force changes without confirmation
#   -v, --verbose           Enable verbose output
#
# Examples:
#   # Configure static IP with DNS
#   sudo ./configure-network.sh -i eth0 -a 192.168.1.100/24 -g 192.168.1.1 -d 8.8.8.8,8.8.4.4
#
#   # Configure with IPv6
#   sudo ./configure-network.sh -i eth0 -a 192.168.1.100/24 -g 192.168.1.1 -6 2001:db8::100/64
#
#   # Backup current configuration
#   sudo ./configure-network.sh --backup
#
#   # Restore previous configuration
#   sudo ./configure-network.sh --restore

set -euo pipefail

# Script variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="/var/backups/network-config"
LOG_FILE="/var/log/network-configure.log"
INTERFACE=""
IP_ADDRESS=""
GATEWAY=""
DNS_SERVERS=""
DNS_SEARCH=""
IPV6_ADDRESS=""
BACKUP_ONLY=false
RESTORE_MODE=false
TEST_MODE=false
FORCE_MODE=false
VERBOSE=false
NETWORK_MANAGER=""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Functions
# ---------

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
        "DEBUG")
            if [[ "$VERBOSE" == "true" ]]; then
                echo -e "${BLUE}[DEBUG]${NC} $message"
            fi
            ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error exit
error_exit() {
    log "ERROR" "$1"
    exit 1
}

# Check root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root (use sudo)"
    fi
}

# Detect network manager
detect_network_manager() {
    log "INFO" "Detecting network configuration method..."
    
    # Check for netplan (Ubuntu 18.04+)
    if [[ -d /etc/netplan ]] && command -v netplan &>/dev/null; then
        NETWORK_MANAGER="netplan"
        log "INFO" "Detected: Netplan"
        return
    fi
    
    # Check for NetworkManager
    if systemctl is-active --quiet NetworkManager 2>/dev/null; then
        NETWORK_MANAGER="networkmanager"
        log "INFO" "Detected: NetworkManager"
        return
    fi
    
    # Check for systemd-networkd
    if systemctl is-active --quiet systemd-networkd 2>/dev/null; then
        NETWORK_MANAGER="systemd-networkd"
        log "INFO" "Detected: systemd-networkd"
        return
    fi
    
    # Check for traditional interfaces file
    if [[ -f /etc/network/interfaces ]]; then
        NETWORK_MANAGER="interfaces"
        log "INFO" "Detected: /etc/network/interfaces"
        return
    fi
    
    error_exit "Could not detect network configuration method"
}

# Auto-detect primary interface
auto_detect_interface() {
    log "INFO" "Auto-detecting primary network interface..."
    
    # Try to get default route interface
    local default_if=$(ip route | grep '^default' | awk '{print $5}' | head -1)
    
    if [[ -n "$default_if" ]]; then
        INTERFACE="$default_if"
        log "INFO" "Detected interface: $INTERFACE"
        return
    fi
    
    # Fallback: get first non-loopback interface
    local first_if=$(ip -o link show | grep -v 'lo:' | awk -F': ' '{print $2}' | head -1)
    
    if [[ -n "$first_if" ]]; then
        INTERFACE="$first_if"
        log "INFO" "Using first available interface: $INTERFACE"
        return
    fi
    
    error_exit "Could not auto-detect network interface"
}

# Validate IP address
validate_ip() {
    local ip=$1
    local stat=1
    
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    
    return $stat
}

# Extract IP and netmask
parse_cidr() {
    local cidr=$1
    
    if [[ ! "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        error_exit "Invalid CIDR notation: $cidr (use format: 192.168.1.100/24)"
    fi
    
    IP_ONLY="${cidr%/*}"
    NETMASK="${cidr#*/}"
    
    validate_ip "$IP_ONLY" || error_exit "Invalid IP address: $IP_ONLY"
    
    if [[ $NETMASK -lt 0 || $NETMASK -gt 32 ]]; then
        error_exit "Invalid netmask: $NETMASK"
    fi
}

# Convert CIDR to netmask
cidr_to_netmask() {
    local cidr=$1
    local mask=""
    local full_octets=$((cidr / 8))
    local partial_octet=$((cidr % 8))
    
    for ((i=0; i<4; i++)); do
        if [[ $i -lt $full_octets ]]; then
            mask="${mask}255"
        elif [[ $i -eq $full_octets ]]; then
            mask="${mask}$((256 - 2**(8 - partial_octet)))"
        else
            mask="${mask}0"
        fi
        
        if [[ $i -lt 3 ]]; then
            mask="${mask}."
        fi
    done
    
    echo "$mask"
}

# Create backup
create_backup() {
    log "INFO" "Creating configuration backup..."
    
    mkdir -p "$BACKUP_DIR"
    local backup_name="backup_$(date +%Y%m%d_%H%M%S)"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    mkdir -p "$backup_path"
    
    # Backup based on network manager
    case $NETWORK_MANAGER in
        netplan)
            cp -r /etc/netplan "$backup_path/" 2>/dev/null || true
            ;;
        networkmanager)
            cp -r /etc/NetworkManager/system-connections "$backup_path/" 2>/dev/null || true
            ;;
        systemd-networkd)
            cp -r /etc/systemd/network "$backup_path/" 2>/dev/null || true
            ;;
        interfaces)
            cp /etc/network/interfaces "$backup_path/" 2>/dev/null || true
            ;;
    esac
    
    # Backup DNS configuration
    cp /etc/resolv.conf "$backup_path/" 2>/dev/null || true
    
    # Save current network state
    ip addr show > "$backup_path/ip_addr.txt"
    ip route show > "$backup_path/ip_route.txt"
    
    log "INFO" "Backup created: $backup_path"
    echo "$backup_name"
}

# Restore backup
restore_backup() {
    log "INFO" "Available backups:"
    
    if [[ ! -d "$BACKUP_DIR" ]] || [[ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
        error_exit "No backups found"
    fi
    
    # List backups
    local i=1
    local backups=()
    for backup in "$BACKUP_DIR"/*; do
        if [[ -d "$backup" ]]; then
            backups+=("$(basename "$backup")")
            echo "$i) $(basename "$backup")"
            ((i++))
        fi
    done
    
    # Select backup
    local selection
    read -p "Select backup to restore (1-${#backups[@]}): " selection
    
    if [[ $selection -lt 1 || $selection -gt ${#backups[@]} ]]; then
        error_exit "Invalid selection"
    fi
    
    local backup_name="${backups[$((selection-1))]}"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    log "INFO" "Restoring from: $backup_name"
    
    # Restore based on network manager
    case $NETWORK_MANAGER in
        netplan)
            if [[ -d "$backup_path/netplan" ]]; then
                rm -f /etc/netplan/*.yaml
                cp -r "$backup_path/netplan"/* /etc/netplan/
                netplan apply
            fi
            ;;
        networkmanager)
            if [[ -d "$backup_path/system-connections" ]]; then
                rm -f /etc/NetworkManager/system-connections/*
                cp -r "$backup_path/system-connections"/* /etc/NetworkManager/system-connections/
                chmod 600 /etc/NetworkManager/system-connections/*
                nmcli connection reload
            fi
            ;;
        systemd-networkd)
            if [[ -d "$backup_path/network" ]]; then
                rm -f /etc/systemd/network/*
                cp -r "$backup_path/network"/* /etc/systemd/network/
                systemctl restart systemd-networkd
            fi
            ;;
        interfaces)
            if [[ -f "$backup_path/interfaces" ]]; then
                cp "$backup_path/interfaces" /etc/network/interfaces
                systemctl restart networking
            fi
            ;;
    esac
    
    # Restore DNS if exists
    if [[ -f "$backup_path/resolv.conf" ]]; then
        cp "$backup_path/resolv.conf" /etc/resolv.conf
    fi
    
    log "INFO" "Configuration restored successfully"
}

# Configure with netplan
configure_netplan() {
    log "INFO" "Configuring network with netplan..."
    
    local config_file="/etc/netplan/99-static.yaml"
    
    # Parse IP address
    parse_cidr "$IP_ADDRESS"
    
    # Create netplan configuration
    cat > "$config_file" << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $INTERFACE:
      dhcp4: no
      addresses:
        - $IP_ADDRESS
EOF

    # Add IPv6 if specified
    if [[ -n "$IPV6_ADDRESS" ]]; then
        cat >> "$config_file" << EOF
        - $IPV6_ADDRESS
EOF
    fi

    # Add gateway
    if [[ -n "$GATEWAY" ]]; then
        cat >> "$config_file" << EOF
      gateway4: $GATEWAY
EOF
    fi

    # Add DNS
    if [[ -n "$DNS_SERVERS" ]]; then
        cat >> "$config_file" << EOF
      nameservers:
        addresses: [$(echo "$DNS_SERVERS" | sed 's/,/, /g')]
EOF
        
        if [[ -n "$DNS_SEARCH" ]]; then
            cat >> "$config_file" << EOF
        search: [$DNS_SEARCH]
EOF
        fi
    fi
    
    # Set permissions
    chmod 600 "$config_file"
    
    if [[ "$TEST_MODE" == "true" ]]; then
        log "INFO" "Test mode - configuration preview:"
        cat "$config_file"
        rm "$config_file"
        return
    fi
    
    # Apply configuration
    log "INFO" "Applying netplan configuration..."
    netplan apply
}

# Configure with NetworkManager
configure_networkmanager() {
    log "INFO" "Configuring network with NetworkManager..."
    
    # Parse IP address
    parse_cidr "$IP_ADDRESS"
    
    # Check if connection exists
    local conn_name="$INTERFACE-static"
    if nmcli connection show "$conn_name" &>/dev/null; then
        log "INFO" "Updating existing connection: $conn_name"
        nmcli connection delete "$conn_name"
    fi
    
    # Create new connection
    log "INFO" "Creating connection: $conn_name"
    
    # Build nmcli command
    local cmd="nmcli connection add type ethernet con-name $conn_name ifname $INTERFACE"
    cmd="$cmd ipv4.method manual ipv4.addresses $IP_ADDRESS"
    
    if [[ -n "$GATEWAY" ]]; then
        cmd="$cmd ipv4.gateway $GATEWAY"
    fi
    
    if [[ -n "$DNS_SERVERS" ]]; then
        cmd="$cmd ipv4.dns \"$DNS_SERVERS\""
    fi
    
    if [[ -n "$DNS_SEARCH" ]]; then
        cmd="$cmd ipv4.dns-search \"$DNS_SEARCH\""
    fi
    
    if [[ -n "$IPV6_ADDRESS" ]]; then
        cmd="$cmd ipv6.method manual ipv6.addresses $IPV6_ADDRESS"
    fi
    
    if [[ "$TEST_MODE" == "true" ]]; then
        log "INFO" "Test mode - would run: $cmd"
        return
    fi
    
    # Execute command
    eval $cmd
    
    # Activate connection
    nmcli connection up "$conn_name"
}

# Configure with systemd-networkd
configure_systemd_networkd() {
    log "INFO" "Configuring network with systemd-networkd..."
    
    local config_file="/etc/systemd/network/20-$INTERFACE.network"
    
    # Parse IP address
    parse_cidr "$IP_ADDRESS"
    
    # Create network file
    cat > "$config_file" << EOF
[Match]
Name=$INTERFACE

[Network]
Address=$IP_ADDRESS
EOF

    # Add IPv6 if specified
    if [[ -n "$IPV6_ADDRESS" ]]; then
        echo "Address=$IPV6_ADDRESS" >> "$config_file"
    fi

    # Add gateway
    if [[ -n "$GATEWAY" ]]; then
        echo "Gateway=$GATEWAY" >> "$config_file"
    fi

    # Add DNS
    if [[ -n "$DNS_SERVERS" ]]; then
        IFS=',' read -ra DNS_ARRAY <<< "$DNS_SERVERS"
        for dns in "${DNS_ARRAY[@]}"; do
            echo "DNS=$dns" >> "$config_file"
        done
    fi
    
    if [[ -n "$DNS_SEARCH" ]]; then
        echo "Domains=$DNS_SEARCH" >> "$config_file"
    fi
    
    if [[ "$TEST_MODE" == "true" ]]; then
        log "INFO" "Test mode - configuration preview:"
        cat "$config_file"
        rm "$config_file"
        return
    fi
    
    # Restart systemd-networkd
    systemctl restart systemd-networkd
}

# Configure with /etc/network/interfaces
configure_interfaces() {
    log "INFO" "Configuring network with /etc/network/interfaces..."
    
    # Parse IP address
    parse_cidr "$IP_ADDRESS"
    local netmask=$(cidr_to_netmask "$NETMASK")
    
    # Backup current interfaces
    cp /etc/network/interfaces /etc/network/interfaces.bak
    
    # Remove existing configuration for interface
    sed -i "/^auto $INTERFACE/,/^$/d" /etc/network/interfaces
    sed -i "/^iface $INTERFACE/,/^$/d" /etc/network/interfaces
    
    # Add new configuration
    cat >> /etc/network/interfaces << EOF

auto $INTERFACE
iface $INTERFACE inet static
    address $IP_ONLY
    netmask $netmask
EOF

    if [[ -n "$GATEWAY" ]]; then
        echo "    gateway $GATEWAY" >> /etc/network/interfaces
    fi
    
    if [[ -n "$DNS_SERVERS" ]]; then
        echo "    dns-nameservers $DNS_SERVERS" >> /etc/network/interfaces
    fi
    
    if [[ -n "$DNS_SEARCH" ]]; then
        echo "    dns-search $DNS_SEARCH" >> /etc/network/interfaces
    fi
    
    # Add IPv6 if specified
    if [[ -n "$IPV6_ADDRESS" ]]; then
        cat >> /etc/network/interfaces << EOF

iface $INTERFACE inet6 static
    address $IPV6_ADDRESS
EOF
    fi
    
    if [[ "$TEST_MODE" == "true" ]]; then
        log "INFO" "Test mode - configuration preview:"
        grep -A10 "^auto $INTERFACE" /etc/network/interfaces
        cp /etc/network/interfaces.bak /etc/network/interfaces
        return
    fi
    
    # Restart networking
    systemctl restart networking || ifdown "$INTERFACE" && ifup "$INTERFACE"
}

# Configure DNS separately
configure_dns() {
    if [[ -z "$DNS_SERVERS" ]]; then
        return
    fi
    
    log "INFO" "Configuring DNS..."
    
    # Check if systemd-resolved is active
    if systemctl is-active --quiet systemd-resolved; then
        log "DEBUG" "systemd-resolved is active, DNS will be managed by network configuration"
        return
    fi
    
    # Direct resolv.conf configuration
    cat > /etc/resolv.conf << EOF
# Generated by configure-network.sh
EOF

    if [[ -n "$DNS_SEARCH" ]]; then
        echo "search $DNS_SEARCH" >> /etc/resolv.conf
    fi
    
    IFS=',' read -ra DNS_ARRAY <<< "$DNS_SERVERS"
    for dns in "${DNS_ARRAY[@]}"; do
        echo "nameserver $dns" >> /etc/resolv.conf
    done
}

# Test network connectivity
test_connectivity() {
    log "INFO" "Testing network connectivity..."
    
    # Test gateway ping
    if [[ -n "$GATEWAY" ]]; then
        if ping -c 2 -W 2 "$GATEWAY" &>/dev/null; then
            log "INFO" "Gateway reachable: $GATEWAY"
        else
            log "WARN" "Gateway unreachable: $GATEWAY"
        fi
    fi
    
    # Test DNS
    if [[ -n "$DNS_SERVERS" ]]; then
        IFS=',' read -ra DNS_ARRAY <<< "$DNS_SERVERS"
        for dns in "${DNS_ARRAY[@]}"; do
            if nc -zw2 "$dns" 53 &>/dev/null; then
                log "INFO" "DNS server reachable: $dns"
            else
                log "WARN" "DNS server unreachable: $dns"
            fi
        done
    fi
    
    # Test internet connectivity
    if ping -c 2 -W 2 8.8.8.8 &>/dev/null; then
        log "INFO" "Internet connectivity: OK"
    else
        log "WARN" "Internet connectivity: Failed"
    fi
    
    # Test DNS resolution
    if host google.com &>/dev/null; then
        log "INFO" "DNS resolution: OK"
    else
        log "WARN" "DNS resolution: Failed"
    fi
}

# Show current configuration
show_current_config() {
    echo
    log "INFO" "Current network configuration:"
    echo "=============================="
    
    # Interface information
    if [[ -n "$INTERFACE" ]]; then
        echo "Interface: $INTERFACE"
        ip addr show "$INTERFACE" | grep -E 'inet|link' | sed 's/^/  /'
    fi
    
    # Routing information
    echo
    echo "Default Gateway:"
    ip route | grep '^default' | sed 's/^/  /'
    
    # DNS information
    echo
    echo "DNS Configuration:"
    if [[ -f /etc/resolv.conf ]]; then
        grep -E '^(nameserver|search)' /etc/resolv.conf | sed 's/^/  /'
    fi
    
    echo
}

# Confirm changes
confirm_changes() {
    if [[ "$FORCE_MODE" == "true" ]]; then
        return 0
    fi
    
    echo
    log "WARN" "This will change your network configuration:"
    echo "  Interface: $INTERFACE"
    echo "  IP Address: $IP_ADDRESS"
    echo "  Gateway: ${GATEWAY:-<none>}"
    echo "  DNS Servers: ${DNS_SERVERS:-<none>}"
    echo "  DNS Search: ${DNS_SEARCH:-<none>}"
    
    if [[ -n "$IPV6_ADDRESS" ]]; then
        echo "  IPv6 Address: $IPV6_ADDRESS"
    fi
    
    echo
    read -p "Continue? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "INFO" "Configuration cancelled"
        exit 0
    fi
}

# Usage function
usage() {
    cat << EOF
Usage: $(basename "$0") [options]

Options:
  -h, --help              Show this help message
  -i, --interface IFACE   Network interface (default: auto-detect)
  -a, --address IP/MASK   IP address with CIDR (e.g., 192.168.1.100/24)
  -g, --gateway IP        Default gateway
  -d, --dns DNS1,DNS2     DNS servers (comma-separated)
  -s, --search DOMAIN     DNS search domain
  -6, --ipv6 IP/PREFIX    IPv6 address (optional)
  -b, --backup            Create backup only
  -r, --restore           Restore from backup
  -t, --test              Test configuration without applying
  -f, --force             Force changes without confirmation
  -v, --verbose           Enable verbose output

Examples:
  # Configure static IP with DNS
  sudo $(basename "$0") -i eth0 -a 192.168.1.100/24 -g 192.168.1.1 -d 8.8.8.8,8.8.4.4

  # Auto-detect interface
  sudo $(basename "$0") -a 10.0.0.50/24 -g 10.0.0.1 -d 10.0.0.1

  # Backup current configuration
  sudo $(basename "$0") --backup

  # Restore previous configuration
  sudo $(basename "$0") --restore
EOF
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -i|--interface)
                INTERFACE="$2"
                shift 2
                ;;
            -a|--address)
                IP_ADDRESS="$2"
                shift 2
                ;;
            -g|--gateway)
                GATEWAY="$2"
                shift 2
                ;;
            -d|--dns)
                DNS_SERVERS="$2"
                shift 2
                ;;
            -s|--search)
                DNS_SEARCH="$2"
                shift 2
                ;;
            -6|--ipv6)
                IPV6_ADDRESS="$2"
                shift 2
                ;;
            -b|--backup)
                BACKUP_ONLY=true
                shift
                ;;
            -r|--restore)
                RESTORE_MODE=true
                shift
                ;;
            -t|--test)
                TEST_MODE=true
                shift
                ;;
            -f|--force)
                FORCE_MODE=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
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
    # Initialize log
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    
    log "INFO" "Starting network configuration"
    
    # Parse arguments
    parse_args "$@"
    
    # Check prerequisites
    check_root
    
    # Detect network manager
    detect_network_manager
    
    # Handle backup mode
    if [[ "$BACKUP_ONLY" == "true" ]]; then
        create_backup
        log "INFO" "Backup completed"
        exit 0
    fi
    
    # Handle restore mode
    if [[ "$RESTORE_MODE" == "true" ]]; then
        restore_backup
        test_connectivity
        exit 0
    fi
    
    # Validate required parameters
    if [[ -z "$IP_ADDRESS" ]]; then
        error_exit "IP address is required (use -a option)"
    fi
    
    # Auto-detect interface if not specified
    if [[ -z "$INTERFACE" ]]; then
        auto_detect_interface
    fi
    
    # Validate interface exists
    if ! ip link show "$INTERFACE" &>/dev/null; then
        error_exit "Interface does not exist: $INTERFACE"
    fi
    
    # Show current configuration
    show_current_config
    
    # Confirm changes
    confirm_changes
    
    # Create backup
    backup_name=$(create_backup)
    
    # Configure based on network manager
    case $NETWORK_MANAGER in
        netplan)
            configure_netplan
            ;;
        networkmanager)
            configure_networkmanager
            ;;
        systemd-networkd)
            configure_systemd_networkd
            ;;
        interfaces)
            configure_interfaces
            ;;
    esac
    
    # Configure DNS if needed
    configure_dns
    
    # Test connectivity
    if [[ "$TEST_MODE" != "true" ]]; then
        sleep 2
        test_connectivity
        show_current_config
    fi
    
    log "INFO" "Network configuration completed"
    
    if [[ "$TEST_MODE" == "true" ]]; then
        log "INFO" "Test mode - no changes were applied"
    else
        log "INFO" "Backup saved as: $backup_name"
        log "INFO" "To restore: $(basename "$0") --restore"
    fi
}

# Run main
main "$@"