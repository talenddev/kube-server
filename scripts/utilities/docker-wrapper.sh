#!/bin/bash

# Script: docker-wrapper.sh
# Purpose: Wrapper script for Docker container execution with environment variables and detailed logging
# Author: Server Automation Library
# Date: 2025-01-06
# Version: 1.0

# Documentation
# =============
# Description:
#   A wrapper script that starts Docker containers with configurable environment variables,
#   parameters, and detailed logging. Captures container output and provides execution
#   summaries similar to execution-wrapper.sh.
#
# Features:
#   - Set environment variables for Docker containers
#   - Configure Docker run parameters (volumes, ports, networks, etc.)
#   - Logs container output with timestamps
#   - Separates stdout and stderr into different files
#   - Captures exit codes and execution time
#   - Supports log rotation by date
#   - Provides execution summary
#   - Can email notifications on failure (optional)
#   - Supports both interactive and detached modes
#
# Usage:
#   ./docker-wrapper.sh [options] -- image [command] [arguments]
#
# Options:
#   -h, --help              Show this help message
#   -l, --log-dir DIR       Log directory (default: /var/log/docker-wrapper)
#   -p, --prefix PREFIX     Log file prefix (default: image basename)
#   -e, --email EMAIL       Send email on failure (requires mail command)
#   -r, --rotate DAYS       Keep logs for N days (default: 30)
#   -s, --silent            Don't output to console
#   -t, --tag TAG           Add custom tag to log filename
#   -v, --verbose           Verbose output
#   -d, --detach            Run container in detached mode
#   -i, --interactive       Run container in interactive mode
#   --rm                    Automatically remove container when it exits
#   --name NAME             Assign a name to the container
#   --env KEY=VALUE         Set environment variable (can be used multiple times)
#   --env-file FILE         Read environment variables from file
#   --volume SRC:DST        Bind mount volume (can be used multiple times)
#   --port HOST:CONTAINER   Publish port (can be used multiple times)
#   --network NETWORK       Connect to network
#   --user USER             Username or UID
#   --workdir DIR           Working directory inside container
#   --entrypoint CMD        Override default entrypoint
#   --docker-args ARGS      Additional Docker arguments (quoted string)
#
# Examples:
#   ./docker-wrapper.sh -- nginx:alpine
#   ./docker-wrapper.sh --env APP_ENV=production --port 8080:80 -- nginx:alpine
#   ./docker-wrapper.sh --volume /data:/app/data --name myapp -- myimage:latest
#   ./docker-wrapper.sh --env-file .env --rm -- postgres:13
#   ./docker-wrapper.sh --detach --name webapp --port 3000:3000 -- node:16 npm start
#   ./docker-wrapper.sh --docker-args "--cap-add=SYS_ADMIN --privileged" -- myimage
#
# Log Files:
#   - Output: {log-dir}/{prefix}_{tag}_YYYYMMDD_HHMMSS.log
#   - Errors: {log-dir}/{prefix}_{tag}_YYYYMMDD_HHMMSS.err
#   - Summary: {log-dir}/{prefix}_{tag}_YYYYMMDD_HHMMSS.summary

set -o pipefail

# Script variables
SCRIPT_NAME=$(basename "$0")
LOG_DIR="/var/log/docker-wrapper"
LOG_PREFIX=""
EMAIL=""
ROTATE_DAYS=30
SILENT=false
CUSTOM_TAG=""
VERBOSE=false
DETACHED=false
INTERACTIVE=false
AUTO_REMOVE=false
CONTAINER_NAME=""
ENV_VARS=()
ENV_FILE=""
VOLUMES=()
PORTS=()
NETWORK=""
USER=""
WORKDIR=""
ENTRYPOINT=""
DOCKER_ARGS=""
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
    grep "^#" "$0" | grep -E "^# (Usage|Options|Examples):" -A 30 | grep -E "^#( |$)" | sed 's/^# //'
}

# Parse command line arguments
parse_args() {
    local parsing_image=false
    IMAGE_ARGS=()
    
    while [[ $# -gt 0 ]]; do
        if [[ "$parsing_image" == "true" ]]; then
            IMAGE_ARGS+=("$1")
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
            -d|--detach)
                DETACHED=true
                shift
                ;;
            -i|--interactive)
                INTERACTIVE=true
                shift
                ;;
            --rm)
                AUTO_REMOVE=true
                shift
                ;;
            --name)
                CONTAINER_NAME="$2"
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
            --volume)
                VOLUMES+=("$2")
                shift 2
                ;;
            --port)
                PORTS+=("$2")
                shift 2
                ;;
            --network)
                NETWORK="$2"
                shift 2
                ;;
            --user)
                USER="$2"
                shift 2
                ;;
            --workdir)
                WORKDIR="$2"
                shift 2
                ;;
            --entrypoint)
                ENTRYPOINT="$2"
                shift 2
                ;;
            --docker-args)
                DOCKER_ARGS="$2"
                shift 2
                ;;
            --)
                parsing_image=true
                shift
                ;;
            *)
                error_exit "Unknown option: $1"
                ;;
        esac
    done
    
    # Check if image was provided
    if [[ ${#IMAGE_ARGS[@]} -eq 0 ]]; then
        error_exit "No Docker image specified. Use -- image [command] [args]"
    fi
}

# Create log directory
create_log_dir() {
    if [[ ! -d "$LOG_DIR" ]]; then
        verbose_log "Creating log directory: $LOG_DIR"
        mkdir -p "$LOG_DIR" || error_exit "Failed to create log directory: $LOG_DIR"
    fi
}

# Get image name for log prefix
get_image_name() {
    local image="${IMAGE_ARGS[0]}"
    
    # If no prefix specified, use image basename
    if [[ -z "$LOG_PREFIX" ]]; then
        LOG_PREFIX=$(echo "$image" | sed 's/[^a-zA-Z0-9_-]/_/g' | sed 's/:/_/g')
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

# Build Docker command
build_docker_command() {
    local docker_cmd=("docker" "run")
    
    # Add detached mode
    if [[ "$DETACHED" == "true" ]]; then
        docker_cmd+=("-d")
    fi
    
    # Add interactive mode
    if [[ "$INTERACTIVE" == "true" ]]; then
        docker_cmd+=("-it")
    fi
    
    # Add auto-remove
    if [[ "$AUTO_REMOVE" == "true" ]]; then
        docker_cmd+=("--rm")
    fi
    
    # Add container name
    if [[ -n "$CONTAINER_NAME" ]]; then
        docker_cmd+=("--name" "$CONTAINER_NAME")
    fi
    
    # Add environment variables
    for env_var in "${ENV_VARS[@]}"; do
        docker_cmd+=("-e" "$env_var")
    done
    
    # Add environment file
    if [[ -n "$ENV_FILE" ]]; then
        docker_cmd+=("--env-file" "$ENV_FILE")
    fi
    
    # Add volumes
    for volume in "${VOLUMES[@]}"; do
        docker_cmd+=("-v" "$volume")
    done
    
    # Add ports
    for port in "${PORTS[@]}"; do
        docker_cmd+=("-p" "$port")
    done
    
    # Add network
    if [[ -n "$NETWORK" ]]; then
        docker_cmd+=("--network" "$NETWORK")
    fi
    
    # Add user
    if [[ -n "$USER" ]]; then
        docker_cmd+=("--user" "$USER")
    fi
    
    # Add working directory
    if [[ -n "$WORKDIR" ]]; then
        docker_cmd+=("-w" "$WORKDIR")
    fi
    
    # Add entrypoint
    if [[ -n "$ENTRYPOINT" ]]; then
        docker_cmd+=("--entrypoint" "$ENTRYPOINT")
    fi
    
    # Add additional Docker arguments
    if [[ -n "$DOCKER_ARGS" ]]; then
        eval "docker_cmd+=($DOCKER_ARGS)"
    fi
    
    # Add image and command
    docker_cmd+=("${IMAGE_ARGS[@]}")
    
    echo "${docker_cmd[@]}"
}

# Execute Docker container with logging
execute_docker() {
    local log_file="${LOG_DIR}/${LOG_PREFIX}_${TIMESTAMP}.log"
    local err_file="${LOG_DIR}/${LOG_PREFIX}_${TIMESTAMP}.err"
    local summary_file="${LOG_DIR}/${LOG_PREFIX}_${TIMESTAMP}.summary"
    local start_time=$(date +%s)
    local exit_code=0
    local container_id=""
    
    # Build Docker command
    local docker_command
    docker_command=$(build_docker_command)
    
    # Create summary header
    {
        echo "==================================================================="
        echo "Docker Container Execution Summary"
        echo "==================================================================="
        echo "Date: $DATE_STAMP"
        echo "Docker Command: $docker_command"
        echo "Working Directory: $(pwd)"
        echo "User: $(whoami)"
        echo "Hostname: $(hostname)"
        echo "Log File: $log_file"
        echo "Error File: $err_file"
        echo "-------------------------------------------------------------------"
    } > "$summary_file"
    
    print_color "$BLUE" "[INFO] Executing Docker: $docker_command"
    print_color "$BLUE" "[INFO] Logging to: $log_file"
    print_color "$BLUE" "[INFO] Errors to: $err_file"
    
    # Add header to log files
    {
        echo "==================================================================="
        echo "Docker container execution started at: $DATE_STAMP"
        echo "Docker Command: $docker_command"
        echo "==================================================================="
        echo ""
    } > "$log_file"
    
    {
        echo "==================================================================="
        echo "Docker error log started at: $DATE_STAMP"
        echo "Docker Command: $docker_command"
        echo "==================================================================="
        echo ""
    } > "$err_file"
    
    # Execute Docker command
    if [[ "$DETACHED" == "true" ]]; then
        # For detached mode, just capture container ID
        container_id=$(eval "$docker_command" 2>&1)
        exit_code=$?
        
        if [[ $exit_code -eq 0 ]]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Container started with ID: $container_id" >> "$log_file"
            print_color "$GREEN" "[SUCCESS] Container started with ID: $container_id"
        else
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Failed to start container: $container_id" >> "$err_file"
            print_color "$RED" "[ERROR] Failed to start container: $container_id"
        fi
    else
        # For non-detached mode, capture output
        {
            eval "$docker_command" 2>&1 1>&3 3>&- |
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
    fi
    
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
        echo "Docker container execution completed at: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Exit code: $exit_code"
        echo "Duration: $duration_str"
        if [[ -n "$container_id" ]]; then
            echo "Container ID: $container_id"
        fi
        echo "==================================================================="
    } | tee -a "$log_file" >> "$err_file"
    
    # Update summary
    {
        echo "Start Time: $DATE_STAMP"
        echo "End Time: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Duration: $duration_str"
        echo "Exit Code: $exit_code"
        if [[ -n "$container_id" ]]; then
            echo "Container ID: $container_id"
        fi
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
        print_color "$GREEN" "[SUCCESS] Docker container completed successfully (Duration: $duration_str)"
    else
        print_color "$RED" "[FAILED] Docker container failed with exit code: $exit_code (Duration: $duration_str)"
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
            echo "Docker container execution failed with exit code: $exit_code"
            echo ""
            cat "$summary_file"
        } | mail -s "[FAILED] Docker wrapper: ${LOG_PREFIX} - $(hostname)" "$EMAIL"
        
        print_color "$BLUE" "[INFO] Email notification sent to: $EMAIL"
    else
        print_color "$YELLOW" "[WARNING] Mail command not found, skipping email notification"
    fi
}

# Check Docker availability
check_docker() {
    if ! command -v docker &>/dev/null; then
        error_exit "Docker is not installed or not in PATH"
    fi
    
    if ! docker info &>/dev/null; then
        error_exit "Docker daemon is not running or not accessible"
    fi
}

# Main function
main() {
    # Check Docker availability
    check_docker
    
    # Parse arguments
    parse_args "$@"
    
    # Setup
    get_image_name
    create_log_dir
    rotate_logs
    
    # Execute Docker container
    execute_docker
    local exit_code=$?
    
    # Return the same exit code as the container
    exit $exit_code
}

# Run main function
main "$@"