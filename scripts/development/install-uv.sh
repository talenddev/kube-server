#!/bin/bash

# Script: install-uv.sh
# Purpose: Install uv - An extremely fast Python package installer and resolver
# Author: Server Automation Library
# Date: 2025-01-06
# Version: 1.0

# Documentation
# =============
# Description:
#   Installs uv, a fast Python package installer and resolver written in Rust.
#   uv is a drop-in replacement for pip and pip-tools that's 10-100x faster.
#   It supports pip-compatible commands and can manage Python versions.
#
# Features:
#   - 10-100x faster than pip
#   - Drop-in replacement for pip and pip-tools
#   - Built-in support for Python version management
#   - Disk and network caching for fast re-installs
#   - Supports requirements.txt, pyproject.toml, and more
#   - Compatible with virtual environments
#
# System Requirements:
#   - Linux (x86_64 or aarch64) or macOS
#   - curl or wget for downloading
#   - No Python required for installation
#
# Usage:
#   ./install-uv.sh [options]
#
# Options:
#   -h, --help              Show this help message
#   -v, --version VERSION   Install specific version (default: latest)
#   -p, --path PATH         Install to specific path (default: /usr/local/bin)
#   -u, --user              Install for current user only (~/.local/bin)
#   --no-modify-path        Don't modify PATH in shell configs
#   --preview               Install preview/beta version
#   -V, --verbose           Enable verbose output
#
# Examples:
#   # Install latest version system-wide
#   sudo ./install-uv.sh
#
#   # Install for current user only
#   ./install-uv.sh --user
#
#   # Install specific version
#   sudo ./install-uv.sh --version 0.1.0
#
# Post-Installation:
#   - Verify: uv --version
#   - Install package: uv pip install requests
#   - Install from requirements: uv pip install -r requirements.txt
#   - Create venv: uv venv
#   - Sync project: uv pip sync requirements.txt

set -euo pipefail

# Script variables
SCRIPT_NAME=$(basename "$0")
INSTALL_VERSION="latest"
INSTALL_PATH="/usr/local/bin"
USER_INSTALL=false
MODIFY_PATH=true
PREVIEW=false
VERBOSE=false
GITHUB_API="https://api.github.com/repos/astral-sh/uv"
DOWNLOAD_BASE="https://github.com/astral-sh/uv/releases/download"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Functions
# ---------

# Print colored output
print_color() {
    echo -e "$1$2${NC}"
}

# Logging functions
log_info() {
    print_color "$GREEN" "[INFO] $1"
}

log_warn() {
    print_color "$YELLOW" "[WARN] $1"
}

log_error() {
    print_color "$RED" "[ERROR] $1"
}

log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        print_color "$BLUE" "[DEBUG] $1"
    fi
}

# Error exit
error_exit() {
    log_error "$1"
    exit 1
}

# Check system compatibility
check_system() {
    # Detect OS and architecture
    local os=""
    local arch=""
    
    case "$(uname -s)" in
        Linux)
            os="linux"
            ;;
        Darwin)
            os="macos"
            ;;
        *)
            error_exit "Unsupported operating system: $(uname -s)"
            ;;
    esac
    
    case "$(uname -m)" in
        x86_64|amd64)
            arch="x86_64"
            ;;
        aarch64|arm64)
            arch="aarch64"
            ;;
        *)
            error_exit "Unsupported architecture: $(uname -m)"
            ;;
    esac
    
    # Check for required tools
    if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
        error_exit "Either curl or wget is required for downloading"
    fi
    
    echo "$os-$arch"
}

# Get latest version from GitHub
get_latest_version() {
    local api_url="$GITHUB_API/releases/latest"
    local version=""
    
    if command -v curl &>/dev/null; then
        version=$(curl -s "$api_url" | grep '"tag_name"' | cut -d'"' -f4)
    else
        version=$(wget -qO- "$api_url" | grep '"tag_name"' | cut -d'"' -f4)
    fi
    
    if [[ -z "$version" ]]; then
        error_exit "Failed to fetch latest version"
    fi
    
    echo "$version"
}

# Download and install uv
install_uv() {
    local platform="$1"
    local version="$2"
    
    # Determine download URL
    local filename=""
    case "$platform" in
        linux-x86_64)
            filename="uv-x86_64-unknown-linux-gnu.tar.gz"
            ;;
        linux-aarch64)
            filename="uv-aarch64-unknown-linux-gnu.tar.gz"
            ;;
        macos-x86_64)
            filename="uv-x86_64-apple-darwin.tar.gz"
            ;;
        macos-aarch64)
            filename="uv-aarch64-apple-darwin.tar.gz"
            ;;
    esac
    
    local download_url="$DOWNLOAD_BASE/$version/$filename"
    log_info "Downloading uv $version for $platform..."
    log_debug "Download URL: $download_url"
    
    # Create temporary directory
    local temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT
    
    # Download
    if command -v curl &>/dev/null; then
        curl -L -f -o "$temp_dir/$filename" "$download_url" || error_exit "Download failed"
    else
        wget -O "$temp_dir/$filename" "$download_url" || error_exit "Download failed"
    fi
    
    # Extract
    log_info "Extracting uv..."
    tar -xzf "$temp_dir/$filename" -C "$temp_dir" || error_exit "Extraction failed"
    
    # Find the binary
    local binary_path=$(find "$temp_dir" -name "uv" -type f -executable | head -1)
    if [[ -z "$binary_path" ]]; then
        error_exit "uv binary not found in archive"
    fi
    
    # Install
    log_info "Installing uv to $INSTALL_PATH..."
    
    # Create install directory if needed
    mkdir -p "$INSTALL_PATH"
    
    # Copy binary
    if [[ -w "$INSTALL_PATH" ]]; then
        cp "$binary_path" "$INSTALL_PATH/uv"
        chmod +x "$INSTALL_PATH/uv"
    else
        error_exit "Cannot write to $INSTALL_PATH. Try running with sudo or use --user flag."
    fi
    
    log_info "uv installed successfully!"
}

# Setup user installation
setup_user_install() {
    INSTALL_PATH="$HOME/.local/bin"
    log_info "Setting up user installation to $INSTALL_PATH"
    
    # Create directory if it doesn't exist
    mkdir -p "$INSTALL_PATH"
}

# Add to PATH
add_to_path() {
    if [[ "$MODIFY_PATH" != "true" ]]; then
        return
    fi
    
    log_info "Checking PATH configuration..."
    
    # Check if already in PATH
    if echo "$PATH" | grep -q "$INSTALL_PATH"; then
        log_debug "$INSTALL_PATH is already in PATH"
        return
    fi
    
    # Add to shell configs
    local shell_configs=()
    
    # Determine shell config files
    if [[ -f "$HOME/.bashrc" ]]; then
        shell_configs+=("$HOME/.bashrc")
    fi
    
    if [[ -f "$HOME/.zshrc" ]]; then
        shell_configs+=("$HOME/.zshrc")
    fi
    
    if [[ "$USER_INSTALL" == "true" ]] && [[ ${#shell_configs[@]} -gt 0 ]]; then
        log_info "Adding $INSTALL_PATH to PATH in shell configuration..."
        
        local path_line='export PATH="$HOME/.local/bin:$PATH"'
        
        for config in "${shell_configs[@]}"; do
            if ! grep -q "$INSTALL_PATH" "$config"; then
                echo "" >> "$config"
                echo "# Added by uv installer" >> "$config"
                echo "$path_line" >> "$config"
                log_debug "Updated $config"
            fi
        done
        
        log_warn "PATH has been updated. Run 'source ~/.bashrc' or start a new shell to use uv."
    fi
}

# Verify installation
verify_installation() {
    log_info "Verifying installation..."
    
    # Check if uv is accessible
    if ! "$INSTALL_PATH/uv" --version &>/dev/null; then
        error_exit "Installation verification failed"
    fi
    
    local installed_version=$("$INSTALL_PATH/uv" --version | cut -d' ' -f2)
    log_info "uv $installed_version installed successfully!"
}

# Print usage examples
print_examples() {
    echo
    print_color "$GREEN" "Installation Complete!"
    echo
    echo "Quick Start Guide:"
    echo "=================="
    echo
    echo "# Check version"
    echo "uv --version"
    echo
    echo "# Install a package"
    echo "uv pip install requests"
    echo
    echo "# Install from requirements.txt"
    echo "uv pip install -r requirements.txt"
    echo
    echo "# Create a virtual environment"
    echo "uv venv"
    echo
    echo "# Install packages in isolated environment"
    echo "uv pip install --isolated requests"
    echo
    echo "# Compile requirements"
    echo "uv pip compile requirements.in -o requirements.txt"
    echo
    echo "# Sync environment to match requirements"
    echo "uv pip sync requirements.txt"
    echo
    echo "# Install Python (if Python management is enabled)"
    echo "uv python install 3.12"
    echo
    echo "For more information: https://github.com/astral-sh/uv"
    
    if [[ "$USER_INSTALL" == "true" ]] && ! echo "$PATH" | grep -q "$INSTALL_PATH"; then
        echo
        print_color "$YELLOW" "Note: Run 'source ~/.bashrc' or start a new shell to use uv"
    fi
}

# Show usage
usage() {
    cat << EOF
Usage: $SCRIPT_NAME [options]

Options:
  -h, --help              Show this help message
  -v, --version VERSION   Install specific version (default: latest)
  -p, --path PATH         Install to specific path (default: /usr/local/bin)
  -u, --user              Install for current user only (~/.local/bin)
  --no-modify-path        Don't modify PATH in shell configs
  --preview               Install preview/beta version
  -V, --verbose           Enable verbose output

Examples:
  # Install latest version system-wide
  sudo $SCRIPT_NAME

  # Install for current user only
  $SCRIPT_NAME --user

  # Install specific version
  sudo $SCRIPT_NAME --version 0.1.0
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -v|--version)
                INSTALL_VERSION="$2"
                shift 2
                ;;
            -p|--path)
                INSTALL_PATH="$2"
                shift 2
                ;;
            -u|--user)
                USER_INSTALL=true
                shift
                ;;
            --no-modify-path)
                MODIFY_PATH=false
                shift
                ;;
            --preview)
                PREVIEW=true
                shift
                ;;
            -V|--verbose)
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
    log_info "Starting uv installation"
    
    # Parse arguments
    parse_args "$@"
    
    # Setup user installation if requested
    if [[ "$USER_INSTALL" == "true" ]]; then
        setup_user_install
    fi
    
    # Check system compatibility
    log_info "Checking system compatibility..."
    local platform=$(check_system)
    log_debug "Detected platform: $platform"
    
    # Get version
    local version="$INSTALL_VERSION"
    if [[ "$version" == "latest" ]]; then
        log_info "Fetching latest version information..."
        version=$(get_latest_version)
        log_debug "Latest version: $version"
    fi
    
    # Install uv
    install_uv "$platform" "$version"
    
    # Add to PATH
    add_to_path
    
    # Verify installation
    verify_installation
    
    # Print examples
    print_examples
}

# Run main
main "$@"