#!/bin/bash

# Script: install-zsh-ohmyzsh.sh
# Purpose: Install Zsh, Oh My Zsh, and Powerlevel10k theme for enhanced terminal experience
# Author: Server Automation Library
# Date: 2025-01-07
# Version: 1.0

# Documentation
# =============
# Description:
#   This script automates the installation of:
#   - Zsh shell
#   - Oh My Zsh framework
#   - Powerlevel10k theme
#   - Recommended fonts for Powerlevel10k
#   - Common Oh My Zsh plugins
#
# Dependencies:
#   - git: Required for cloning Oh My Zsh and themes
#   - curl/wget: For downloading installation scripts
#   - fontconfig: For installing fonts
#
# System Requirements:
#   - Supported OS: Ubuntu 20.04+, Debian 10+, CentOS 8+, RHEL 8+, Fedora 32+
#   - Internet connection for downloading packages
#   - Minimum RAM: 512MB
#   - Disk space: 100MB
#
# Configuration Variables:
#   - TARGET_USER: User to install for (default: current sudo user or root)
#   - INSTALL_FONTS: Install recommended fonts (default: true)
#   - PLUGINS: Comma-separated list of plugins to enable (default: git,zsh-autosuggestions,zsh-syntax-highlighting)
#
# Usage:
#   sudo ./install-zsh-ohmyzsh.sh [options]
#
# Options:
#   -h, --help         Show this help message
#   -u, --user USER    Install for specific user (default: current user)
#   -f, --no-fonts     Skip font installation
#   -p, --plugins LIST Comma-separated list of plugins to install
#   -v, --verbose      Enable verbose output
#
# Examples:
#   sudo ./install-zsh-ohmyzsh.sh
#   sudo ./install-zsh-ohmyzsh.sh --user john
#   sudo ./install-zsh-ohmyzsh.sh --plugins "git,docker,kubectl"
#
# Post-Installation:
#   1. Log out and log back in to use Zsh as default shell
#   2. Run 'p10k configure' to set up Powerlevel10k
#   3. Configuration files: ~/.zshrc, ~/.p10k.zsh
#   4. To change shell manually: chsh -s $(which zsh)

# Exit on error, undefined variable, or pipe failure
set -euo pipefail

# Script variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "$0")"

# Source common functions
source "${SCRIPT_DIR}/../utilities/common-functions.sh" || {
    echo "Error: Cannot source common-functions.sh"
    exit 1
}

# Configuration variables
TARGET_USER="${SUDO_USER:-$(whoami)}"
TARGET_HOME=""
INSTALL_FONTS=true
PLUGINS="git,zsh-autosuggestions,zsh-syntax-highlighting"
VERBOSE=false

# Font URLs
NERD_FONT_URL="https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf"
NERD_FONT_BOLD_URL="https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold.ttf"
NERD_FONT_ITALIC_URL="https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Italic.ttf"
NERD_FONT_BOLD_ITALIC_URL="https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold%20Italic.ttf"

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
            -u|--user)
                TARGET_USER="$2"
                shift 2
                ;;
            -f|--no-fonts)
                INSTALL_FONTS=false
                shift
                ;;
            -p|--plugins)
                PLUGINS="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                DEBUG=true
                shift
                ;;
            *)
                error_exit "Unknown option: $1"
                ;;
        esac
    done
}

# Validate target user
validate_user() {
    if ! id "$TARGET_USER" &>/dev/null; then
        error_exit "User $TARGET_USER does not exist"
    fi
    
    # Get user's home directory
    TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
    
    if [[ ! -d "$TARGET_HOME" ]]; then
        error_exit "Home directory $TARGET_HOME does not exist for user $TARGET_USER"
    fi
    
    log "INFO" "Installing for user: $TARGET_USER (home: $TARGET_HOME)"
}

# Install Zsh
install_zsh() {
    log "INFO" "Installing Zsh..."
    
    if command -v zsh &>/dev/null; then
        log "INFO" "Zsh is already installed"
        return 0
    fi
    
    case $OS in
        ubuntu|debian)
            install_packages zsh
            ;;
        centos|rhel|fedora|rocky|almalinux)
            install_packages zsh
            ;;
        *)
            error_exit "Unsupported OS for Zsh installation: $OS"
            ;;
    esac
    
    # Verify installation
    if ! command -v zsh &>/dev/null; then
        error_exit "Failed to install Zsh"
    fi
    
    log "INFO" "Zsh installed successfully"
}

# Install Oh My Zsh
install_ohmyzsh() {
    log "INFO" "Installing Oh My Zsh for user $TARGET_USER..."
    
    local oh_my_zsh_dir="$TARGET_HOME/.oh-my-zsh"
    
    # Check if already installed
    if [[ -d "$oh_my_zsh_dir" ]]; then
        log "WARN" "Oh My Zsh is already installed at $oh_my_zsh_dir"
        log "INFO" "Updating Oh My Zsh..."
        sudo -u "$TARGET_USER" bash -c "cd '$oh_my_zsh_dir' && git pull"
        return 0
    fi
    
    # Install git if not present
    if ! command -v git &>/dev/null; then
        install_packages git
    fi
    
    # Download and run Oh My Zsh installer
    log "INFO" "Downloading Oh My Zsh installer..."
    
    # Create a temporary installation script
    local temp_script="/tmp/install-ohmyzsh-${TARGET_USER}.sh"
    
    # Download the installer
    if command -v curl &>/dev/null; then
        curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -o "$temp_script"
    elif command -v wget &>/dev/null; then
        wget -qO "$temp_script" https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh
    else
        install_packages curl
        curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -o "$temp_script"
    fi
    
    # Make it executable
    chmod +x "$temp_script"
    
    # Run installer as target user with RUNZSH=no to prevent shell switching
    sudo -u "$TARGET_USER" env RUNZSH=no CHSH=no "$temp_script" --unattended
    
    # Clean up
    rm -f "$temp_script"
    
    # Verify installation
    if [[ ! -d "$oh_my_zsh_dir" ]]; then
        error_exit "Failed to install Oh My Zsh"
    fi
    
    log "INFO" "Oh My Zsh installed successfully"
}

# Install Powerlevel10k theme
install_powerlevel10k() {
    log "INFO" "Installing Powerlevel10k theme..."
    
    local p10k_dir="$TARGET_HOME/.oh-my-zsh/custom/themes/powerlevel10k"
    
    # Check if already installed
    if [[ -d "$p10k_dir" ]]; then
        log "INFO" "Updating Powerlevel10k..."
        sudo -u "$TARGET_USER" bash -c "cd '$p10k_dir' && git pull"
    else
        # Clone Powerlevel10k repository
        sudo -u "$TARGET_USER" git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$p10k_dir"
    fi
    
    # Update .zshrc to use Powerlevel10k theme
    local zshrc="$TARGET_HOME/.zshrc"
    
    if [[ -f "$zshrc" ]]; then
        # Backup current .zshrc
        backup_file "$zshrc"
        
        # Change theme to powerlevel10k
        sudo -u "$TARGET_USER" sed -i 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$zshrc"
        
        # Add instant prompt configuration if not present
        if ! grep -q "Enable Powerlevel10k instant prompt" "$zshrc"; then
            local instant_prompt='# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi'
            
            # Add instant prompt at the beginning of .zshrc
            sudo -u "$TARGET_USER" bash -c "echo '$instant_prompt' | cat - '$zshrc' > '$zshrc.tmp' && mv '$zshrc.tmp' '$zshrc'"
        fi
        
        # Add p10k configuration source at the end if not present
        if ! grep -q "source.*p10k.zsh" "$zshrc"; then
            echo -e "\n# To customize prompt, run \`p10k configure\` or edit ~/.p10k.zsh." | sudo -u "$TARGET_USER" tee -a "$zshrc" > /dev/null
            echo '[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh' | sudo -u "$TARGET_USER" tee -a "$zshrc" > /dev/null
        fi
    fi
    
    log "INFO" "Powerlevel10k theme installed successfully"
}

# Install recommended fonts
install_fonts() {
    if [[ "$INSTALL_FONTS" != "true" ]]; then
        log "INFO" "Skipping font installation"
        return 0
    fi
    
    log "INFO" "Installing recommended fonts for Powerlevel10k..."
    
    # Install fontconfig if not present
    case $OS in
        ubuntu|debian)
            install_packages fontconfig fonts-powerline
            ;;
        centos|rhel|fedora|rocky|almalinux)
            install_packages fontconfig
            ;;
    esac
    
    # Create fonts directory
    local font_dir="$TARGET_HOME/.local/share/fonts"
    sudo -u "$TARGET_USER" mkdir -p "$font_dir"
    
    # Download MesloLGS NF fonts
    log "INFO" "Downloading MesloLGS Nerd Fonts..."
    
    local fonts=(
        "MesloLGS NF Regular.ttf|$NERD_FONT_URL"
        "MesloLGS NF Bold.ttf|$NERD_FONT_BOLD_URL"
        "MesloLGS NF Italic.ttf|$NERD_FONT_ITALIC_URL"
        "MesloLGS NF Bold Italic.ttf|$NERD_FONT_BOLD_ITALIC_URL"
    )
    
    for font_info in "${fonts[@]}"; do
        IFS='|' read -r font_name font_url <<< "$font_info"
        local font_path="$font_dir/$font_name"
        
        if [[ ! -f "$font_path" ]]; then
            if command -v curl &>/dev/null; then
                sudo -u "$TARGET_USER" curl -fsSL "$font_url" -o "$font_path"
            else
                sudo -u "$TARGET_USER" wget -q "$font_url" -O "$font_path"
            fi
        fi
    done
    
    # Update font cache
    sudo -u "$TARGET_USER" fc-cache -f "$font_dir"
    
    log "INFO" "Fonts installed successfully"
    log "WARN" "Remember to configure your terminal to use 'MesloLGS NF' font"
}

# Install Oh My Zsh plugins
install_plugins() {
    log "INFO" "Installing Oh My Zsh plugins..."
    
    local custom_plugins_dir="$TARGET_HOME/.oh-my-zsh/custom/plugins"
    
    # Install zsh-autosuggestions
    if [[ "$PLUGINS" == *"zsh-autosuggestions"* ]]; then
        local autosuggestions_dir="$custom_plugins_dir/zsh-autosuggestions"
        if [[ ! -d "$autosuggestions_dir" ]]; then
            log "INFO" "Installing zsh-autosuggestions..."
            sudo -u "$TARGET_USER" git clone https://github.com/zsh-users/zsh-autosuggestions "$autosuggestions_dir"
        fi
    fi
    
    # Install zsh-syntax-highlighting
    if [[ "$PLUGINS" == *"zsh-syntax-highlighting"* ]]; then
        local syntax_highlighting_dir="$custom_plugins_dir/zsh-syntax-highlighting"
        if [[ ! -d "$syntax_highlighting_dir" ]]; then
            log "INFO" "Installing zsh-syntax-highlighting..."
            sudo -u "$TARGET_USER" git clone https://github.com/zsh-users/zsh-syntax-highlighting "$syntax_highlighting_dir"
        fi
    fi
    
    # Update plugins in .zshrc
    local zshrc="$TARGET_HOME/.zshrc"
    if [[ -f "$zshrc" ]]; then
        # Convert comma-separated plugins to space-separated format for .zshrc
        local plugins_formatted=$(echo "$PLUGINS" | tr ',' ' ')
        sudo -u "$TARGET_USER" sed -i "s/^plugins=.*/plugins=($plugins_formatted)/" "$zshrc"
    fi
    
    log "INFO" "Plugins configured: $PLUGINS"
}

# Set Zsh as default shell
set_default_shell() {
    log "INFO" "Setting Zsh as default shell for user $TARGET_USER..."
    
    local zsh_path=$(which zsh)
    local current_shell=$(getent passwd "$TARGET_USER" | cut -d: -f7)
    
    if [[ "$current_shell" == "$zsh_path" ]]; then
        log "INFO" "Zsh is already the default shell for $TARGET_USER"
        return 0
    fi
    
    # Add zsh to valid shells if not present
    if ! grep -q "^$zsh_path$" /etc/shells; then
        echo "$zsh_path" >> /etc/shells
    fi
    
    # Change shell
    chsh -s "$zsh_path" "$TARGET_USER"
    
    log "INFO" "Default shell changed to Zsh"
}

# Verify installation
verify_installation() {
    log "INFO" "Verifying installation..."
    
    local errors=0
    
    # Check Zsh
    if ! command -v zsh &>/dev/null; then
        log "ERROR" "Zsh is not installed"
        ((errors++))
    fi
    
    # Check Oh My Zsh
    if [[ ! -d "$TARGET_HOME/.oh-my-zsh" ]]; then
        log "ERROR" "Oh My Zsh is not installed"
        ((errors++))
    fi
    
    # Check Powerlevel10k
    if [[ ! -d "$TARGET_HOME/.oh-my-zsh/custom/themes/powerlevel10k" ]]; then
        log "ERROR" "Powerlevel10k theme is not installed"
        ((errors++))
    fi
    
    # Check .zshrc
    if [[ ! -f "$TARGET_HOME/.zshrc" ]]; then
        log "ERROR" ".zshrc file not found"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log "INFO" "All components installed successfully"
        return 0
    else
        return 1
    fi
}

# Print post-installation instructions
print_instructions() {
    echo ""
    echo "=============================================="
    echo "Installation completed successfully!"
    echo "=============================================="
    echo ""
    echo "Next steps:"
    echo "1. Log out and log back in to start using Zsh"
    echo "   OR run: exec zsh"
    echo ""
    echo "2. Configure Powerlevel10k by running:"
    echo "   p10k configure"
    echo ""
    echo "3. If using a terminal emulator, set the font to:"
    echo "   'MesloLGS NF' or 'MesloLGS Nerd Font'"
    echo ""
    echo "4. Customize your setup by editing:"
    echo "   - ~/.zshrc (Zsh configuration)"
    echo "   - ~/.p10k.zsh (Powerlevel10k configuration)"
    echo ""
    echo "Installed plugins: $PLUGINS"
    echo ""
    echo "To manually change your shell later, run:"
    echo "   chsh -s \$(which zsh)"
    echo "=============================================="
}

# Main execution
main() {
    log "INFO" "Starting Zsh, Oh My Zsh, and Powerlevel10k installation"
    
    # Parse arguments
    parse_args "$@"
    
    # Check prerequisites
    check_root
    detect_os
    
    # Validate user
    validate_user
    
    # Update package cache
    update_package_cache
    
    # Install components
    install_zsh
    install_ohmyzsh
    install_powerlevel10k
    install_fonts
    install_plugins
    set_default_shell
    
    # Verify installation
    if verify_installation; then
        print_instructions
        log "INFO" "Installation completed successfully"
    else
        error_exit "Installation completed with errors"
    fi
}

# Run main function
main "$@"