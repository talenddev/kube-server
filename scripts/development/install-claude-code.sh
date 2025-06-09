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
# Claude Code is distributed via npm
NPM_PACKAGE="@anthropic-ai/claude-code"
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
    log_info "Checking system compatibility..." >&2
    
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
    
    log_debug "Detected: $os-$arch" >&2
    
    # Check for required tools
    if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
        error_exit "Either curl or wget is required for downloading"
    fi
    
    echo "$os-$arch"
}

# Get latest version from GitHub
get_latest_version() {
    log_info "Fetching latest version information..." >&2
    
    local version=""
    
    # Try npm registry first as it's more reliable for npm packages
    if command -v npm &>/dev/null; then
        log_debug "Checking npm registry for latest version..." >&2
        version=$(npm view $NPM_PACKAGE version 2>/dev/null || true)
    fi
    
    if [[ -z "$version" ]] && command -v curl &>/dev/null; then
        log_debug "Trying npm registry via curl..." >&2
        version=$(curl -s https://registry.npmjs.org/$NPM_PACKAGE 2>/dev/null | grep '"latest"' | cut -d'"' -f4 || true)
    fi
    
    if [[ -z "$version" ]]; then
        # Try GitHub API as fallback
        log_debug "Trying GitHub API..." >&2
        local api_url="$GITHUB_API/releases/latest"
        
        if command -v curl &>/dev/null; then
            version=$(curl -s "$api_url" 2>/dev/null | grep '"tag_name"' | cut -d'"' -f4 | sed 's/^v//' || true)
        else
            version=$(wget -qO- "$api_url" 2>/dev/null | grep '"tag_name"' | cut -d'"' -f4 | sed 's/^v//' || true)
        fi
    fi
    
    if [[ -z "$version" ]]; then
        log_warn "Could not determine latest version automatically" >&2
        log_warn "Please specify a version with --version flag" >&2
        log_warn "You can check available versions at: https://www.npmjs.com/package/$NPM_PACKAGE" >&2
        error_exit "Failed to fetch latest version"
    fi
    
    echo "$version"
}

# Download and install Claude Code
install_claude_code() {
    local platform="$1"
    local version="$2"
    
    log_info "Installing Claude Code $version for $platform..." >&2
    
    # Create temporary directory
    local temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT
    
    # Method 1: Try npm install directly first
    if command -v npm &>/dev/null; then
        log_info "Installing via npm..." >&2
        
        if [[ "$USER_INSTALL" == "true" ]]; then
            # User-specific installation
            if npm install -g $NPM_PACKAGE@$version --prefix="$HOME/.local"; then
                log_info "Claude Code installed successfully" >&2
                return 0
            fi
        else
            # System-wide installation
            if npm install -g $NPM_PACKAGE@$version; then
                # Check if claude is in the expected location
                if [[ -f "/usr/local/bin/claude" ]] || which claude &>/dev/null; then
                    log_info "Claude Code installed successfully" >&2
                    return 0
                fi
            fi
        fi
        
        log_warn "npm installation failed, trying alternative method..." >&2
    fi
    
    # If we reach here, installation failed
    error_exit "Failed to install Claude Code. Please ensure Node.js 18+ and npm are installed."
}

# Setup user installation
setup_user_install() {
    INSTALL_PATH="$HOME/.local/bin"
    log_info "Setting up user installation to $INSTALL_PATH" >&2
    
    # Create directory if it doesn't exist
    mkdir -p "$INSTALL_PATH"
}

# Configure API key
configure_api_key() {
    if [[ -n "$API_KEY" ]]; then
        log_info "Configuring API key..." >&2
        
        # Create config directory
        local config_dir="$HOME/.claude"
        mkdir -p "$config_dir"
        
        # Write API key to config
        echo "ANTHROPIC_API_KEY=$API_KEY" > "$config_dir/.env"
        chmod 600 "$config_dir/.env"
        
        log_info "API key configured successfully" >&2
    else
        log_warn "No API key provided. You'll need to set it later with:" >&2
        log_warn "  claude --api-key YOUR_KEY" >&2
        log_warn "Or set the ANTHROPIC_API_KEY environment variable" >&2
    fi
}

# Add to PATH
add_to_path() {
    if [[ "$MODIFY_PATH" != "true" ]]; then
        return
    fi
    
    log_info "Checking PATH configuration..." >&2
    
    # Check if already in PATH
    if echo "$PATH" | grep -q "$INSTALL_PATH"; then
        log_debug "$INSTALL_PATH is already in PATH" >&2
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
        log_info "Adding $INSTALL_PATH to PATH in shell configuration..." >&2
        
        local path_line='export PATH="$HOME/.local/bin:$PATH"'
        
        for config in "${shell_configs[@]}"; do
            if ! grep -q "$INSTALL_PATH" "$config"; then
                echo "" >> "$config"
                echo "# Added by Claude Code installer" >> "$config"
                echo "$path_line" >> "$config"
                log_debug "Updated $config" >&2
            fi
        done
        
        log_warn "PATH has been updated. Run 'source ~/.bashrc' or start a new shell to use claude." >&2
    fi
}

# Check Node.js installation
check_nodejs() {
    if ! command -v node &>/dev/null && ! command -v npm &>/dev/null; then
        log_error "Node.js is not installed. Claude Code requires Node.js 18 or higher." >&2
        log_error "Install Node.js with:" >&2
        log_error "  curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -" >&2
        log_error "  sudo apt-get install -y nodejs" >&2
        log_error "" >&2
        log_error "Or use your system's package manager." >&2
        return 1
    fi
    
    # Check Node.js version
    local node_version=$(node --version 2>/dev/null | sed 's/v//' | cut -d. -f1)
    if [[ -n "$node_version" ]] && [[ "$node_version" -lt 18 ]]; then
        log_error "Claude Code requires Node.js 18 or higher. You have Node.js v$node_version" >&2
        log_error "Please upgrade Node.js before continuing." >&2
        return 1
    fi
    
    return 0
}

# Verify installation
verify_installation() {
    log_info "Verifying installation..." >&2
    
    local claude_cmd=""
    
    # Find the claude command
    if [[ -f "$INSTALL_PATH/claude" ]]; then
        claude_cmd="$INSTALL_PATH/claude"
    elif command -v claude &>/dev/null; then
        claude_cmd="claude"
    else
        error_exit "Claude Code binary not found after installation"
    fi
    
    # Check if claude is accessible
    if ! "$claude_cmd" --version &>/dev/null; then
        # Try without version flag
        if ! "$claude_cmd" --help &>/dev/null; then
            error_exit "Installation verification failed - claude command not working"
        fi
    fi
    
    log_info "Claude Code installed successfully!" >&2
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
    log_info "Starting Claude Code installation" >&2
    
    # Parse arguments
    parse_args "$@"
    
    # Setup user installation if requested
    if [[ "$USER_INSTALL" == "true" ]]; then
        setup_user_install
    fi
    
    # Check system compatibility
    local platform=$(check_system)
    
    # Check for Node.js
    if ! check_nodejs; then
        error_exit "Node.js 18+ is required for Claude Code installation"
    fi
    
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