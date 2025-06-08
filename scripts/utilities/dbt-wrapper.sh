#!/bin/bash

# Script: dbt-wrapper.sh
# Purpose: Wrapper script for dbt execution with GitHub repository integration and detailed logging
# Author: Server Automation Library
# Date: 2025-01-06
# Version: 1.0

# Documentation
# =============
# Description:
#   A wrapper script that clones GitHub repositories containing dbt projects and executes
#   dbt commands with comprehensive logging and error handling. Supports both public and
#   private repositories, environment variable injection, and profile management.
#
# Features:
#   - Clone GitHub repositories (public/private with authentication)
#   - Execute dbt commands with logging and error handling
#   - Environment variable injection for profiles and configurations
#   - Virtual environment support
#   - Profile validation and setup
#   - Dependency management (dbt deps)
#   - Comprehensive logging with timestamps
#   - Cleanup and workspace management
#   - Support for different dbt commands (run, test, docs, etc.)
#
# System Requirements:
#   - Git (for repository cloning)
#   - dbt Core (installed via install-dbt-core.sh)
#   - Python 3.8+ with virtual environment support
#
# Usage:
#   ./dbt-wrapper.sh [options] -- dbt-command [arguments]
#
# Options:
#   -h, --help              Show this help message
#   -r, --repo URL          GitHub repository URL (required)
#   -b, --branch BRANCH     Git branch to checkout (default: main)
#   -t, --token TOKEN       GitHub personal access token for private repos
#   -w, --workspace DIR     Working directory (default: /tmp/dbt-wrapper-TIMESTAMP)
#   -l, --log-dir DIR       Log directory (default: /var/log/dbt-wrapper)
#   -p, --prefix PREFIX     Log file prefix (default: repository name)
#   --tag TAG               Add custom tag to log filename
#   --venv PATH             Use virtual environment
#   --profile PROFILE       dbt profile name to use
#   --target TARGET         dbt target to use (dev, prod, etc.)
#   --env KEY=VALUE         Set environment variable (can be used multiple times)
#   --env-file FILE         Read environment variables from file
#   --project-dir DIR       dbt project directory within repo (default: repo root)
#   --profiles-dir DIR      dbt profiles directory (default: ~/.dbt)
#   --no-deps               Skip dbt deps command
#   --cleanup               Remove workspace after execution
#   --keep-on-error         Keep workspace on error for debugging
#   -e, --email EMAIL       Send email on failure (requires mail command)
#   -s, --silent            Don't output to console
#   -v, --verbose           Verbose output
#
# Examples:
#   # Run dbt models from public repository
#   ./dbt-wrapper.sh --repo https://github.com/user/my-dbt-project.git -- run
#
#   # Run with specific branch and target
#   ./dbt-wrapper.sh --repo https://github.com/user/project.git --branch develop --target prod -- run
#
#   # Run with environment variables
#   ./dbt-wrapper.sh --repo https://github.com/user/project.git --env DBT_PROFILES_DIR=/custom/profiles -- test
#
#   # Run with private repository
#   ./dbt-wrapper.sh --repo https://github.com/user/private-project.git --token ghp_xxx -- docs generate
#
#   # Run in virtual environment with cleanup
#   ./dbt-wrapper.sh --venv ~/dbt-env --cleanup --repo https://github.com/user/project.git -- run --models my_model
#
# Environment Variables:
#   - DBT_PROFILES_DIR: Override profiles directory
#   - DBT_PROJECT_DIR: Override project directory
#   - GITHUB_TOKEN: GitHub personal access token
#   - Any dbt-specific environment variables
#
# Log Files:
#   - Output: {log-dir}/{prefix}_{tag}_YYYYMMDD_HHMMSS.log
#   - Errors: {log-dir}/{prefix}_{tag}_YYYYMMDD_HHMMSS.err
#   - Summary: {log-dir}/{prefix}_{tag}_YYYYMMDD_HHMMSS.summary

set -o pipefail

# Script variables
SCRIPT_NAME=$(basename "$0")
REPO_URL=""
BRANCH="main"
GITHUB_TOKEN=""
WORKSPACE_DIR=""
LOG_DIR="/var/log/dbt-wrapper"
LOG_PREFIX=""
CUSTOM_TAG=""
VENV_PATH=""
DBT_PROFILE=""
DBT_TARGET=""
ENV_VARS=()
ENV_FILE=""
PROJECT_DIR=""
PROFILES_DIR=""
SKIP_DEPS=false
CLEANUP=false
KEEP_ON_ERROR=false
EMAIL=""
SILENT=false
VERBOSE=false
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
DATE_STAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Color codes (for console output)
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
fi

# Print colored output
print_color() {
    local color=$1
    shift
    if [[ "$SILENT" != "true" ]]; then
        echo -e "${color}$@${NC}"
    fi
}

# Print verbose messages
verbose_log() {
    if [[ "$VERBOSE" == "true" ]]; then
        print_color "$BLUE" "[VERBOSE] $@"
    fi
}

# Error exit function
error_exit() {
    print_color "$RED" "[ERROR] $1"
    
    # Keep workspace for debugging if requested
    if [[ "$KEEP_ON_ERROR" == "true" && -n "$WORKSPACE_DIR" ]]; then
        print_color "$YELLOW" "[DEBUG] Workspace preserved at: $WORKSPACE_DIR"
    elif [[ "$CLEANUP" == "true" && -n "$WORKSPACE_DIR" ]]; then
        cleanup_workspace
    fi
    
    exit 1
}

# Show usage
usage() {
    grep "^#" "$0" | grep -E "^# (Usage|Options|Examples):" -A 50 | grep -E "^#( |$)" | sed 's/^# //'
}

# Parse command line arguments
parse_args() {
    local parsing_command=false
    DBT_COMMAND_ARGS=()
    
    while [[ $# -gt 0 ]]; do
        if [[ "$parsing_command" == "true" ]]; then
            DBT_COMMAND_ARGS+=("$1")
            shift
            continue
        fi
        
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -r|--repo)
                REPO_URL="$2"
                shift 2
                ;;
            -b|--branch)
                BRANCH="$2"
                shift 2
                ;;
            -t|--token)
                GITHUB_TOKEN="$2"
                shift 2
                ;;
            -w|--workspace)
                WORKSPACE_DIR="$2"
                shift 2
                ;;
            -l|--log-dir)
                LOG_DIR="$2"
                shift 2
                ;;
            -p|--prefix)
                LOG_PREFIX="$2"
                shift 2
                ;;
            --tag)
                CUSTOM_TAG="$2"
                shift 2
                ;;
            --venv)
                VENV_PATH="$2"
                shift 2
                ;;
            --profile)
                DBT_PROFILE="$2"
                shift 2
                ;;
            --target)
                DBT_TARGET="$2"
                shift 2
                ;;
            --env)
                ENV_VARS+=("$2")
                shift 2
                ;;
            --env-file)
                ENV_FILE="$2"
                shift 2
                ;;
            --project-dir)
                PROJECT_DIR="$2"
                shift 2
                ;;
            --profiles-dir)
                PROFILES_DIR="$2"
                shift 2
                ;;
            --no-deps)
                SKIP_DEPS=true
                shift
                ;;
            --cleanup)
                CLEANUP=true
                shift
                ;;
            --keep-on-error)
                KEEP_ON_ERROR=true
                shift
                ;;
            -e|--email)
                EMAIL="$2"
                shift 2
                ;;
            -s|--silent)
                SILENT=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --)
                parsing_command=true
                shift
                ;;
            *)
                error_exit "Unknown option: $1"
                ;;
        esac
    done
    
    # Check required parameters
    if [[ -z "$REPO_URL" ]]; then
        error_exit "Repository URL is required. Use -r/--repo option."
    fi
    
    if [[ ${#DBT_COMMAND_ARGS[@]} -eq 0 ]]; then
        error_exit "No dbt command specified. Use -- dbt-command [args]"
    fi
}

# Create log directory
create_log_dir() {
    if [[ ! -d "$LOG_DIR" ]]; then
        verbose_log "Creating log directory: $LOG_DIR"
        mkdir -p "$LOG_DIR" || error_exit "Failed to create log directory: $LOG_DIR"
    fi
}

# Get repository name for log prefix
get_repo_name() {
    local repo_name=$(basename "$REPO_URL" .git)
    
    # If no prefix specified, use repository name
    if [[ -z "$LOG_PREFIX" ]]; then
        LOG_PREFIX=$(echo "$repo_name" | sed 's/[^a-zA-Z0-9_-]/_/g')
    fi
    
    # Add custom tag if specified
    if [[ -n "$CUSTOM_TAG" ]]; then
        LOG_PREFIX="${LOG_PREFIX}_${CUSTOM_TAG}"
    fi
}

# Setup workspace
setup_workspace() {
    if [[ -z "$WORKSPACE_DIR" ]]; then
        WORKSPACE_DIR="/tmp/dbt-wrapper-$TIMESTAMP"
    fi
    
    verbose_log "Creating workspace: $WORKSPACE_DIR"
    mkdir -p "$WORKSPACE_DIR" || error_exit "Failed to create workspace: $WORKSPACE_DIR"
}

# Cleanup workspace
cleanup_workspace() {
    if [[ -n "$WORKSPACE_DIR" && -d "$WORKSPACE_DIR" ]]; then
        verbose_log "Cleaning up workspace: $WORKSPACE_DIR"
        rm -rf "$WORKSPACE_DIR"
    fi
}

# Setup virtual environment
setup_venv() {
    if [[ -z "$VENV_PATH" ]]; then
        return
    fi
    
    if [[ ! -d "$VENV_PATH" ]]; then
        error_exit "Virtual environment not found: $VENV_PATH"
    fi
    
    verbose_log "Activating virtual environment: $VENV_PATH"
    source "$VENV_PATH/bin/activate" || error_exit "Failed to activate virtual environment"
}

# Clone repository
clone_repository() {
    local clone_url="$REPO_URL"
    
    # Add token to URL for private repositories
    if [[ -n "$GITHUB_TOKEN" ]]; then
        # Extract components from URL
        if [[ "$REPO_URL" =~ ^https://github.com/(.+)$ ]]; then
            clone_url="https://${GITHUB_TOKEN}@github.com/${BASH_REMATCH[1]}"
        else
            error_exit "Invalid GitHub URL format: $REPO_URL"
        fi
    fi
    
    verbose_log "Cloning repository: $REPO_URL (branch: $BRANCH)"
    
    cd "$WORKSPACE_DIR" || error_exit "Failed to change to workspace directory"
    
    # Clone repository
    if ! git clone --branch "$BRANCH" --single-branch "$clone_url" repo; then
        error_exit "Failed to clone repository: $REPO_URL"
    fi
    
    # Change to repository directory
    cd repo || error_exit "Failed to change to repository directory"
    
    # Set project directory
    if [[ -n "$PROJECT_DIR" ]]; then
        if [[ -d "$PROJECT_DIR" ]]; then
            cd "$PROJECT_DIR" || error_exit "Failed to change to project directory: $PROJECT_DIR"
        else
            error_exit "Project directory not found: $PROJECT_DIR"
        fi
    fi
    
    verbose_log "Repository cloned and ready at: $(pwd)"
}

# Setup environment variables
setup_environment() {
    # Load environment file if specified
    if [[ -n "$ENV_FILE" && -f "$ENV_FILE" ]]; then
        verbose_log "Loading environment variables from: $ENV_FILE"
        set -o allexport
        source "$ENV_FILE"
        set +o allexport
    fi
    
    # Set individual environment variables
    for env_var in "${ENV_VARS[@]}"; do
        verbose_log "Setting environment variable: ${env_var%%=*}"
        export "$env_var"
    done
    
    # Set dbt-specific environment variables
    if [[ -n "$PROFILES_DIR" ]]; then
        export DBT_PROFILES_DIR="$PROFILES_DIR"
    fi
    
    # Use GitHub token from environment if not provided
    if [[ -z "$GITHUB_TOKEN" && -n "${GITHUB_TOKEN:-}" ]]; then
        GITHUB_TOKEN="$GITHUB_TOKEN"
    fi
}

# Check dbt installation
check_dbt() {
    if ! command -v dbt &>/dev/null; then
        error_exit "dbt is not installed or not in PATH. Please install dbt Core first."
    fi
    
    verbose_log "dbt version: $(dbt --version | head -1)"
}

# Validate dbt project
validate_project() {
    if [[ ! -f "dbt_project.yml" ]]; then
        error_exit "dbt_project.yml not found. This doesn't appear to be a dbt project."
    fi
    
    verbose_log "Found dbt_project.yml"
    
    # Run dbt debug to validate configuration
    verbose_log "Running dbt debug to validate configuration..."
    
    local debug_args=()
    if [[ -n "$DBT_PROFILE" ]]; then
        debug_args+=("--profile" "$DBT_PROFILE")
    fi
    if [[ -n "$DBT_TARGET" ]]; then
        debug_args+=("--target" "$DBT_TARGET")
    fi
    
    if ! dbt debug "${debug_args[@]}" &>/dev/null; then
        error_exit "dbt debug failed. Please check your profiles.yml configuration."
    fi
    
    verbose_log "dbt configuration is valid"
}

# Install dbt dependencies
install_dependencies() {
    if [[ "$SKIP_DEPS" == "true" ]]; then
        return
    fi
    
    if [[ -f "packages.yml" ]]; then
        verbose_log "Found packages.yml, installing dependencies..."
        
        local deps_args=()
        if [[ -n "$DBT_PROFILE" ]]; then
            deps_args+=("--profile" "$DBT_PROFILE")
        fi
        
        if ! dbt deps "${deps_args[@]}"; then
            error_exit "Failed to install dbt dependencies"
        fi
        
        verbose_log "dbt dependencies installed successfully"
    else
        verbose_log "No packages.yml found, skipping dependency installation"
    fi
}

# Execute dbt command with logging
execute_dbt() {
    local log_file="${LOG_DIR}/${LOG_PREFIX}_${TIMESTAMP}.log"
    local err_file="${LOG_DIR}/${LOG_PREFIX}_${TIMESTAMP}.err"
    local summary_file="${LOG_DIR}/${LOG_PREFIX}_${TIMESTAMP}.summary"
    local start_time=$(date +%s)
    local exit_code=0
    
    # Build dbt command
    local dbt_command=("dbt" "${DBT_COMMAND_ARGS[@]}")
    
    # Add profile and target if specified
    if [[ -n "$DBT_PROFILE" ]]; then
        dbt_command+=("--profile" "$DBT_PROFILE")
    fi
    if [[ -n "$DBT_TARGET" ]]; then
        dbt_command+=("--target" "$DBT_TARGET")
    fi
    
    # Create summary header
    {
        echo "==================================================================="
        echo "dbt Execution Summary"
        echo "==================================================================="
        echo "Date: $DATE_STAMP"
        echo "Repository: $REPO_URL"
        echo "Branch: $BRANCH"
        echo "dbt Command: ${dbt_command[*]}"
        echo "Working Directory: $(pwd)"
        echo "User: $(whoami)"
        echo "Hostname: $(hostname)"
        echo "Log File: $log_file"
        echo "Error File: $err_file"
        echo "-------------------------------------------------------------------"
    } > "$summary_file"
    
    print_color "$BLUE" "[INFO] Executing dbt: ${dbt_command[*]}"
    print_color "$BLUE" "[INFO] Logging to: $log_file"
    print_color "$BLUE" "[INFO] Errors to: $err_file"
    
    # Add header to log files
    {
        echo "==================================================================="
        echo "dbt execution started at: $DATE_STAMP"
        echo "Repository: $REPO_URL (branch: $BRANCH)"
        echo "Command: ${dbt_command[*]}"
        echo "==================================================================="
        echo ""
    } > "$log_file"
    
    {
        echo "==================================================================="
        echo "dbt error log started at: $DATE_STAMP"
        echo "Repository: $REPO_URL (branch: $BRANCH)"
        echo "Command: ${dbt_command[*]}"
        echo "==================================================================="
        echo ""
    } > "$err_file"
    
    # Execute dbt command with timestamp prefixing
    {
        "${dbt_command[@]}" 2>&1 1>&3 3>&- |
        while IFS= read -r line; do
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] $line" >> "$err_file"
            if [[ "$SILENT" != "true" ]]; then
                echo -e "${RED}[STDERR]${NC} $line"
            fi
        done
    } 3>&1 1>&2 |
    while IFS= read -r line; do
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $line" >> "$log_file"
        if [[ "$SILENT" != "true" ]]; then
            echo "$line"
        fi
    done
    
    # Capture exit code
    exit_code=${PIPESTATUS[0]}
    
    # Calculate execution time
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local hours=$((duration / 3600))
    local minutes=$(((duration % 3600) / 60))
    local seconds=$((duration % 60))
    local duration_str=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)
    
    # Add footer to log files
    {
        echo ""
        echo "==================================================================="
        echo "dbt execution completed at: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Exit code: $exit_code"
        echo "Duration: $duration_str"
        echo "==================================================================="
    } | tee -a "$log_file" >> "$err_file"
    
    # Update summary
    {
        echo "Start Time: $DATE_STAMP"
        echo "End Time: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Duration: $duration_str"
        echo "Exit Code: $exit_code"
        echo "-------------------------------------------------------------------"
        
        # Add statistics
        local log_lines=$(grep -c "^\[" "$log_file" 2>/dev/null || echo "0")
        local err_lines=$(grep -c "^\[" "$err_file" 2>/dev/null || echo "0")
        
        echo "Output Lines: $log_lines"
        echo "Error Lines: $err_lines"
        
        if [[ $exit_code -eq 0 ]]; then
            echo "Status: SUCCESS"
        else
            echo "Status: FAILED"
            
            # Include last few error lines in summary
            if [[ $err_lines -gt 0 ]]; then
                echo "-------------------------------------------------------------------"
                echo "Last Error Lines:"
                grep "^\[" "$err_file" | tail -10
            fi
        fi
        
        echo "==================================================================="
    } >> "$summary_file"
    
    # Print completion message
    if [[ $exit_code -eq 0 ]]; then
        print_color "$GREEN" "[SUCCESS] dbt command completed successfully (Duration: $duration_str)"
    else
        print_color "$RED" "[FAILED] dbt command failed with exit code: $exit_code (Duration: $duration_str)"
    fi
    
    # Check if error file is empty and remove if so
    if [[ ! -s "$err_file" ]]; then
        verbose_log "No errors logged, removing empty error file"
        rm -f "$err_file"
    else
        print_color "$YELLOW" "[WARNING] Errors were logged to: $err_file"
    fi
    
    # Send email notification if configured
    if [[ -n "$EMAIL" ]] && [[ $exit_code -ne 0 ]]; then
        send_email_notification "$exit_code" "$summary_file"
    fi
    
    return $exit_code
}

# Send email notification
send_email_notification() {
    local exit_code=$1
    local summary_file=$2
    
    if command -v mail &>/dev/null; then
        verbose_log "Sending email notification to: $EMAIL"
        
        {
            echo "dbt execution failed with exit code: $exit_code"
            echo "Repository: $REPO_URL"
            echo "Branch: $BRANCH"
            echo ""
            cat "$summary_file"
        } | mail -s "[FAILED] dbt wrapper: ${LOG_PREFIX} - $(hostname)" "$EMAIL"
        
        print_color "$BLUE" "[INFO] Email notification sent to: $EMAIL"
    else
        print_color "$YELLOW" "[WARNING] Mail command not found, skipping email notification"
    fi
}

# Main function
main() {
    # Parse arguments
    parse_args "$@"
    
    # Setup
    get_repo_name
    create_log_dir
    setup_workspace
    setup_environment
    setup_venv
    
    # Check requirements
    if ! command -v git &>/dev/null; then
        error_exit "Git is required but not installed"
    fi
    check_dbt
    
    # Clone and setup repository
    clone_repository
    validate_project
    install_dependencies
    
    # Execute dbt command
    execute_dbt
    local exit_code=$?
    
    # Cleanup if requested
    if [[ "$CLEANUP" == "true" ]]; then
        cleanup_workspace
    fi
    
    # Return the same exit code as the dbt command
    exit $exit_code
}

# Setup trap for cleanup on exit
trap 'if [[ "$CLEANUP" == "true" ]]; then cleanup_workspace; fi' EXIT

# Run main function
main "$@"