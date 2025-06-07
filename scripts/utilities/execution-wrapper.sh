#!/bin/bash

# Script: execution-wrapper.sh
# Purpose: Wrapper script for command execution with detailed logging
# Author: Server Automation Library
# Date: 2025-01-06
# Version: 1.0

# Documentation
# =============
# Description:
#   A wrapper script that executes commands while capturing their output to log files.
#   Stdout and stderr are logged separately with timestamps and command information.
#   Useful for cron jobs, automation scripts, and debugging command execution.
#
# Features:
#   - Logs command output with timestamps
#   - Separates stdout and stderr into different files
#   - Captures exit codes and execution time
#   - Supports log rotation by date
#   - Provides execution summary
#   - Can email notifications on failure (optional)
#
# Usage:
#   ./execution-wrapper.sh [options] -- command [arguments]
#
# Options:
#   -h, --help              Show this help message
#   -l, --log-dir DIR       Log directory (default: /var/log/execution-wrapper)
#   -p, --prefix PREFIX     Log file prefix (default: command basename)
#   -e, --email EMAIL       Send email on failure (requires mail command)
#   -r, --rotate DAYS       Keep logs for N days (default: 30)
#   -s, --silent            Don't output to console
#   -t, --tag TAG           Add custom tag to log filename
#   -v, --verbose           Verbose output
#
# Examples:
#   ./execution-wrapper.sh -- ls -la
#   ./execution-wrapper.sh -l /tmp/logs -- backup.sh
#   ./execution-wrapper.sh -p mybackup -e admin@example.com -- rsync -av /src /dst
#   ./execution-wrapper.sh -t daily -- /usr/local/bin/database-backup.sh
#
# Log Files:
#   - Output: {log-dir}/{prefix}_{tag}_YYYYMMDD_HHMMSS.log
#   - Errors: {log-dir}/{prefix}_{tag}_YYYYMMDD_HHMMSS.err
#   - Summary: {log-dir}/{prefix}_{tag}_YYYYMMDD_HHMMSS.summary

set -o pipefail

# Script variables
SCRIPT_NAME=$(basename "$0")
LOG_DIR="/var/log/execution-wrapper"
LOG_PREFIX=""
EMAIL=""
ROTATE_DAYS=30
SILENT=false
CUSTOM_TAG=""
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
    exit 1
}

# Show usage
usage() {
    grep "^#" "$0" | grep -E "^# (Usage|Options|Examples):" -A 20 | grep -E "^#( |$)" | sed 's/^# //'
}

# Parse command line arguments
parse_args() {
    local parsing_command=false
    COMMAND_ARGS=()
    
    while [[ $# -gt 0 ]]; do
        if [[ "$parsing_command" == "true" ]]; then
            COMMAND_ARGS+=("$1")
            shift
            continue
        fi
        
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -l|--log-dir)
                LOG_DIR="$2"
                shift 2
                ;;
            -p|--prefix)
                LOG_PREFIX="$2"
                shift 2
                ;;
            -e|--email)
                EMAIL="$2"
                shift 2
                ;;
            -r|--rotate)
                ROTATE_DAYS="$2"
                shift 2
                ;;
            -s|--silent)
                SILENT=true
                shift
                ;;
            -t|--tag)
                CUSTOM_TAG="$2"
                shift 2
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
    
    # Check if command was provided
    if [[ ${#COMMAND_ARGS[@]} -eq 0 ]]; then
        error_exit "No command specified. Use -- command [args]"
    fi
}

# Create log directory
create_log_dir() {
    if [[ ! -d "$LOG_DIR" ]]; then
        verbose_log "Creating log directory: $LOG_DIR"
        mkdir -p "$LOG_DIR" || error_exit "Failed to create log directory: $LOG_DIR"
    fi
}

# Get command name for log prefix
get_command_name() {
    local cmd="${COMMAND_ARGS[0]}"
    
    # If no prefix specified, use command basename
    if [[ -z "$LOG_PREFIX" ]]; then
        LOG_PREFIX=$(basename "$cmd" | sed 's/[^a-zA-Z0-9_-]/_/g')
    fi
    
    # Add custom tag if specified
    if [[ -n "$CUSTOM_TAG" ]]; then
        LOG_PREFIX="${LOG_PREFIX}_${CUSTOM_TAG}"
    fi
}

# Rotate old logs
rotate_logs() {
    if [[ "$ROTATE_DAYS" -gt 0 ]]; then
        verbose_log "Rotating logs older than $ROTATE_DAYS days"
        find "$LOG_DIR" -name "${LOG_PREFIX}_*.log" -o -name "${LOG_PREFIX}_*.err" -o -name "${LOG_PREFIX}_*.summary" \
            -type f -mtime +$ROTATE_DAYS -delete 2>/dev/null
    fi
}

# Execute command with logging
execute_command() {
    local log_file="${LOG_DIR}/${LOG_PREFIX}_${TIMESTAMP}.log"
    local err_file="${LOG_DIR}/${LOG_PREFIX}_${TIMESTAMP}.err"
    local summary_file="${LOG_DIR}/${LOG_PREFIX}_${TIMESTAMP}.summary"
    local start_time=$(date +%s)
    local exit_code=0
    
    # Create summary header
    {
        echo "==================================================================="
        echo "Execution Summary"
        echo "==================================================================="
        echo "Date: $DATE_STAMP"
        echo "Command: ${COMMAND_ARGS[*]}"
        echo "Working Directory: $(pwd)"
        echo "User: $(whoami)"
        echo "Hostname: $(hostname)"
        echo "Log File: $log_file"
        echo "Error File: $err_file"
        echo "-------------------------------------------------------------------"
    } > "$summary_file"
    
    print_color "$BLUE" "[INFO] Executing: ${COMMAND_ARGS[*]}"
    print_color "$BLUE" "[INFO] Logging to: $log_file"
    print_color "$BLUE" "[INFO] Errors to: $err_file"
    
    # Add header to log files
    {
        echo "==================================================================="
        echo "Command execution started at: $DATE_STAMP"
        echo "Command: ${COMMAND_ARGS[*]}"
        echo "==================================================================="
        echo ""
    } > "$log_file"
    
    {
        echo "==================================================================="
        echo "Error log started at: $DATE_STAMP"
        echo "Command: ${COMMAND_ARGS[*]}"
        echo "==================================================================="
        echo ""
    } > "$err_file"
    
    # Execute command with timestamp prefixing
    {
        "${COMMAND_ARGS[@]}" 2>&1 1>&3 3>&- |
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
        echo "Command execution completed at: $(date '+%Y-%m-%d %H:%M:%S')"
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
        print_color "$GREEN" "[SUCCESS] Command completed successfully (Duration: $duration_str)"
    else
        print_color "$RED" "[FAILED] Command failed with exit code: $exit_code (Duration: $duration_str)"
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
            echo "Command execution failed with exit code: $exit_code"
            echo ""
            cat "$summary_file"
        } | mail -s "[FAILED] Execution wrapper: ${LOG_PREFIX} - $(hostname)" "$EMAIL"
        
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
    get_command_name
    create_log_dir
    rotate_logs
    
    # Execute command
    execute_command
    local exit_code=$?
    
    # Return the same exit code as the wrapped command
    exit $exit_code
}

# Run main function
main "$@"