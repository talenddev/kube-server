#!/bin/bash

# Script: install-claude-code.sh
# Purpose: Install Claude Code - Anthropic's official CLI for Claude
# Author: Server Automation Library
# Date: 2025-01-06
# Version: 1.0

# Documentation
# =============
# Description:
#   Installs Claude Code, Anthropic's official command-line interface for Claude.
#   Claude Code allows you to interact with Claude AI directly from your terminal
#   for coding assistance, file manipulation, and development tasks.
#
# Features:
#   - Interactive AI-powered coding assistance
#   - File reading and editing capabilities
#   - Project context awareness
#   - Multiple conversation modes
#   - Tool use for system interactions
#   - Git integration
#   - Web search capabilities
#
# Requirements:
#   - Linux or macOS (x86_64 or arm64)
#   - Internet connection for API access
#   - Anthropic API key (will be prompted during setup)
#
# Usage:
#   ./install-claude-code.sh [options]
#
# Options:
#   -h, --help              Show this help message
#   -v, --version VERSION   Install specific version (default: latest)
#   -p, --path PATH         Install to specific path (default: /usr/local/bin)
#   -u, --user              Install for current user only (~/.local/bin)
#   -k, --api-key KEY       Set API key during installation
#   --no-modify-path        Don't modify PATH in shell configs
#   --preview               Install preview/beta version
#   -V, --verbose           Enable verbose output
#
# Examples:
#   # Install latest version system-wide
#   sudo ./install-claude-code.sh
#
#   # Install for current user with API key
#   ./install-claude-code.sh --user --api-key sk-ant-xxxxx
#
#   # Install specific version
#   sudo ./install-claude-code.sh --version 0.1.15
#
# Post-Installation:
#   - Start Claude Code: claude
#   - Get help: claude --help
#   - Set API key: claude --api-key YOUR_KEY
#   - Start coding: claude "help me write a Python script"

set -euo pipefail

# Script variables
SCRIPT_NAME=$(basename "$0")
INSTALL_VERSION="latest"
INSTALL_PATH="/usr/local/bin"
USER_INSTALL=false
API_KEY=""
MODIFY_PATH=true
PREVIEW=false
VERBOSE=false
GITHUB_API="https://api.github.com/repos/anthropics/claude-code"
DOWNLOAD_BASE="https://github.com/anthropics/claude-code/releases/download"

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
    log_info "Checking system compatibility..."
    
    # Detect OS and architecture
    local os=""
    local arch=""
    
    case "$(uname -s)" in
        Linux)
            os="linux"
            ;;
        Darwin)
            os="darwin"
            ;;
        *)
            error_exit "Unsupported operating system: $(uname -s)"
            ;;
    esac
    
    case "$(uname -m)" in
        x86_64|amd64)
            arch="amd64"
            ;;
        aarch64|arm64)
            arch="arm64"
            ;;
        *)
            error_exit "Unsupported architecture: $(uname -m)"
            ;;
    esac
    
    log_debug "Detected: $os-$arch"
    
    # Check for required tools
    if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
        error_exit "Either curl or wget is required for downloading"
    fi
    
    echo "$os-$arch"
}

# Get latest version from GitHub
get_latest_version() {
    log_info "Fetching latest version information..."
    
    local api_url="$GITHUB_API/releases/latest"
    local version=""
    
    if command -v curl &>/dev/null; then
        version=$(curl -s "$api_url" | grep '"tag_name"' | cut -d'"' -f4 | sed 's/^v//')
    else
        version=$(wget -qO- "$api_url" | grep '"tag_name"' | cut -d'"' -f4 | sed 's/^v//')
    fi
    
    if [[ -z "$version" ]]; then
        # Fallback to npm registry if GitHub API fails
        log_debug "GitHub API failed, trying npm registry..."
        if command -v curl &>/dev/null; then
            version=$(curl -s https://registry.npmjs.org/@anthropic/claude-code | grep '"latest"' | cut -d'"' -f4)
        fi
    fi
    
    if [[ -z "$version" ]]; then
        error_exit "Failed to fetch latest version"
    fi
    
    echo "$version"
}

# Download and install Claude Code
install_claude_code() {
    local platform="$1"
    local version="$2"
    
    log_info "Installing Claude Code $version for $platform..."
    
    # Create temporary directory
    local temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT
    
    # Method 1: Try npx first (most reliable)
    if command -v npx &>/dev/null; then
        log_info "Installing via npx..."
        
        cd "$temp_dir"
        if npx -y @anthropic/claude-code@$version --help &>/dev/null; then
            # Find the installed binary
            local npx_bin=$(which claude 2>/dev/null || find ~/.npm/_npx -name "claude" -type f 2>/dev/null | head -1)
            
            if [[ -n "$npx_bin" && -f "$npx_bin" ]]; then
                log_info "Copying Claude Code to $INSTALL_PATH..."
                cp "$npx_bin" "$INSTALL_PATH/claude"
                chmod +x "$INSTALL_PATH/claude"
                return 0
            fi
        fi
        
        log_warn "npx installation failed, trying alternative method..."
    fi
    
    # Method 2: Try direct binary download
    # Construct download URL (this assumes binaries are published)
    local filename=""
    case "$platform" in
        linux-amd64)
            filename="claude-linux-amd64"
            ;;
        linux-arm64)
            filename="claude-linux-arm64"
            ;;
        darwin-amd64)
            filename="claude-darwin-amd64"
            ;;
        darwin-arm64)
            filename="claude-darwin-arm64"
            ;;
    esac
    
    local download_url="$DOWNLOAD_BASE/v$version/$filename"
    log_debug "Trying direct download from: $download_url"
    
    # Try to download binary directly
    if command -v curl &>/dev/null; then
        if curl -L -f -o "$temp_dir/claude" "$download_url" 2>/dev/null; then
            chmod +x "$temp_dir/claude"
            cp "$temp_dir/claude" "$INSTALL_PATH/claude"
            return 0
        fi
    fi
    
    # Method 3: Install via npm globally
    if command -v npm &>/dev/null; then
        log_info "Installing via npm..."
        
        if [[ "$USER_INSTALL" == "true" ]]; then
            npm install -g @anthropic/claude-code@$version --prefix="$HOME/.local"
            
            # Find and copy the binary
            local npm_bin="$HOME/.local/bin/claude"
            if [[ -f "$npm_bin" ]]; then
                if [[ "$INSTALL_PATH" != "$HOME/.local/bin" ]]; then
                    cp "$npm_bin" "$INSTALL_PATH/claude"
                fi
                chmod +x "$INSTALL_PATH/claude"
                return 0
            fi
        else
            # System-wide npm install
            if npm install -g @anthropic/claude-code@$version; then
                # Find the installed binary
                local npm_bin=$(which claude 2>/dev/null)
                if [[ -n "$npm_bin" && -f "$npm_bin" ]]; then
                    if [[ "$INSTALL_PATH" != "$(dirname "$npm_bin")" ]]; then
                        cp "$npm_bin" "$INSTALL_PATH/claude"
                        chmod +x "$INSTALL_PATH/claude"
                    fi
                    return 0
                fi
            fi
        fi
    fi
    
    error_exit "Failed to install Claude Code. Please ensure Node.js and npm are installed."
}

# Setup user installation
setup_user_install() {
    INSTALL_PATH="$HOME/.local/bin"
    log_info "Setting up user installation to $INSTALL_PATH"
    
    # Create directory if it doesn't exist
    mkdir -p "$INSTALL_PATH"
}

# Configure API key
configure_api_key() {
    if [[ -n "$API_KEY" ]]; then
        log_info "Configuring API key..."
        
        # Create config directory
        local config_dir="$HOME/.claude"
        mkdir -p "$config_dir"
        
        # Write API key to config
        echo "ANTHROPIC_API_KEY=$API_KEY" > "$config_dir/.env"
        chmod 600 "$config_dir/.env"
        
        log_info "API key configured successfully"
    else
        log_warn "No API key provided. You'll need to set it later with:"
        log_warn "  claude --api-key YOUR_KEY"
        log_warn "Or set the ANTHROPIC_API_KEY environment variable"
    fi
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
                echo "# Added by Claude Code installer" >> "$config"
                echo "$path_line" >> "$config"
                log_debug "Updated $config"
            fi
        done
        
        log_warn "PATH has been updated. Run 'source ~/.bashrc' or start a new shell to use claude."
    fi
}

# Check Node.js installation
check_nodejs() {
    if ! command -v node &>/dev/null && ! command -v npm &>/dev/null; then
        log_warn "Node.js is not installed. Claude Code works best with Node.js."
        log_warn "Install Node.js with:"
        log_warn "  curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -"
        log_warn "  sudo apt-get install -y nodejs"
        log_warn ""
        log_warn "Or use your system's package manager."
        return 1
    fi
    return 0
}

# Verify installation
verify_installation() {
    log_info "Verifying installation..."
    
    # Check if claude is accessible
    if ! "$INSTALL_PATH/claude" --version &>/dev/null; then
        # Try without version flag
        if ! "$INSTALL_PATH/claude" --help &>/dev/null; then
            error_exit "Installation verification failed"
        fi
    fi
    
    log_info "Claude Code installed successfully!"
}

# Print usage examples
print_examples() {
    echo
    print_color "$GREEN" "Installation Complete!"
    echo
    echo "Quick Start Guide:"
    echo "=================="
    echo
    
    if [[ -z "$API_KEY" ]]; then
        echo "# First, set your API key:"
        echo "claude --api-key YOUR_ANTHROPIC_API_KEY"
        echo
        echo "# Or export it:"
        echo "export ANTHROPIC_API_KEY=your_key_here"
        echo
    fi
    
    echo "# Start Claude Code"
    echo "claude"
    echo
    echo "# Get help"
    echo "claude --help"
    echo
    echo "# Ask a question"
    echo 'claude "How do I create a Python virtual environment?"'
    echo
    echo "# Work with files"
    echo 'claude "analyze the code in main.py and suggest improvements"'
    echo
    echo "# Generate code"
    echo 'claude "create a REST API with FastAPI for a todo list"'
    echo
    echo "# Use specific model"
    echo 'claude --model claude-3-opus-20240229 "complex coding task"'
    echo
    echo "# Continue previous conversation"
    echo "claude --continue"
    echo
    echo "# List available slash commands"
    echo "# Type /help within Claude Code"
    echo
    echo "For more information: https://github.com/anthropics/claude-code"
    echo "Documentation: https://docs.anthropic.com/en/docs/claude-code"
    
    if [[ "$USER_INSTALL" == "true" ]] && ! echo "$PATH" | grep -q "$INSTALL_PATH"; then
        echo
        print_color "$YELLOW" "Note: Run 'source ~/.bashrc' or start a new shell to use claude"
    fi
    
    if [[ -z "$API_KEY" ]]; then
        echo
        print_color "$YELLOW" "Important: You need an Anthropic API key to use Claude Code"
        print_color "$YELLOW" "Get one at: https://console.anthropic.com/api-keys"
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
  -k, --api-key KEY       Set API key during installation
  --no-modify-path        Don't modify PATH in shell configs
  --preview               Install preview/beta version
  -V, --verbose           Enable verbose output

Examples:
  # Install latest version system-wide
  sudo $SCRIPT_NAME

  # Install for current user with API key
  $SCRIPT_NAME --user --api-key sk-ant-xxxxx

  # Install specific version
  sudo $SCRIPT_NAME --version 0.1.15
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
            -k|--api-key)
                API_KEY="$2"
                shift 2
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
    log_info "Starting Claude Code installation"
    
    # Parse arguments
    parse_args "$@"
    
    # Setup user installation if requested
    if [[ "$USER_INSTALL" == "true" ]]; then
        setup_user_install
    fi
    
    # Check system compatibility
    local platform=$(check_system)
    
    # Check for Node.js
    check_nodejs
    
    # Get version
    local version="$INSTALL_VERSION"
    if [[ "$version" == "latest" ]]; then
        version=$(get_latest_version)
    fi
    
    # Create install directory if needed
    mkdir -p "$INSTALL_PATH"
    
    # Install Claude Code
    install_claude_code "$platform" "$version"
    
    # Configure API key
    configure_api_key
    
    # Add to PATH
    add_to_path
    
    # Verify installation
    verify_installation
    
    # Print examples
    print_examples
}

# Run main
main "$@"