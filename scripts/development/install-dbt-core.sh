#!/bin/bash

# Script: install-dbt-core.sh
# Purpose: Install dbt Core - Data Build Tool for analytics engineering
# Author: Server Automation Library
# Date: 2025-01-06
# Version: 1.0

# Documentation
# =============
# Description:
#   Installs dbt Core, an open-source command-line tool that enables data analysts
#   and engineers to transform data in their warehouses more effectively. dbt uses
#   SQL and Jinja templating to build transformations and models.
#
# Features:
#   - SQL-based transformations with Jinja templating
#   - Data lineage and documentation generation
#   - Testing framework for data quality
#   - Package management for reusable analytics code
#   - Multiple database adapter support
#   - Version control integration
#
# System Requirements:
#   - Python 3.8+ (will be installed if not available)
#   - pip package manager (will be installed if not available)
#   - Git (for package management)
#
# Usage:
#   ./install-dbt-core.sh [options]
#
# Options:
#   -h, --help              Show this help message
#   -v, --version VERSION   Install specific version (default: latest)
#   -a, --adapter ADAPTER   Install database adapter (postgres, snowflake, bigquery, etc.)
#   -p, --python-version VER Python version to use (default: system default)
#   --venv PATH             Create virtual environment at path
#   --global                Install globally (not recommended)
#   --upgrade               Upgrade existing installation
#   --with-deps             Install additional dependencies (git, etc.)
#   -V, --verbose           Enable verbose output
#
# Database Adapters:
#   postgres     - PostgreSQL/Redshift
#   snowflake    - Snowflake
#   bigquery     - Google BigQuery
#   redshift     - Amazon Redshift
#   databricks   - Databricks
#   spark        - Apache Spark
#   trino        - Trino/Presto
#   clickhouse   - ClickHouse
#   duckdb       - DuckDB
#
# Examples:
#   # Install latest dbt-core with PostgreSQL adapter
#   ./install-dbt-core.sh --adapter postgres
#
#   # Install in virtual environment
#   ./install-dbt-core.sh --venv ~/dbt-env --adapter snowflake
#
#   # Install specific version with multiple adapters
#   ./install-dbt-core.sh --version 1.7.0 --adapter postgres,bigquery
#
#   # Install with system dependencies
#   sudo ./install-dbt-core.sh --with-deps --adapter postgres
#
# Post-Installation:
#   - Verify: dbt --version
#   - Initialize project: dbt init my_project
#   - Configure profiles: ~/.dbt/profiles.yml
#   - Run transformations: dbt run
#   - Test data: dbt test
#   - Generate docs: dbt docs generate && dbt docs serve

set -euo pipefail

# Script variables
SCRIPT_NAME=$(basename "$0")
DBT_VERSION="latest"
ADAPTERS=()
PYTHON_VERSION=""
VENV_PATH=""
GLOBAL_INSTALL=false
UPGRADE=false
INSTALL_DEPS=false
VERBOSE=false

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Supported adapters
SUPPORTED_ADAPTERS=(
    "postgres"
    "snowflake"
    "bigquery"
    "redshift"
    "databricks"
    "spark"
    "trino"
    "clickhouse"
    "duckdb"
)

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
    
    # Check OS
    case "$(uname -s)" in
        Linux|Darwin)
            log_debug "Operating system: $(uname -s)"
            ;;
        *)
            error_exit "Unsupported operating system: $(uname -s)"
            ;;
    esac
    
    # Check for package managers
    local has_apt=false
    local has_yum=false
    local has_brew=false
    
    if command -v apt-get &>/dev/null; then
        has_apt=true
    fi
    
    if command -v yum &>/dev/null || command -v dnf &>/dev/null; then
        has_yum=true
    fi
    
    if command -v brew &>/dev/null; then
        has_brew=true
    fi
    
    if [[ "$has_apt" == "false" && "$has_yum" == "false" && "$has_brew" == "false" ]]; then
        log_warn "No supported package manager found. Manual dependency installation may be required."
    fi
}

# Install system dependencies
install_dependencies() {
    if [[ "$INSTALL_DEPS" != "true" ]]; then
        return
    fi
    
    log_info "Installing system dependencies..."
    
    # Git is required for dbt packages
    if ! command -v git &>/dev/null; then
        log_info "Installing Git..."
        
        if command -v apt-get &>/dev/null; then
            apt-get update && apt-get install -y git
        elif command -v yum &>/dev/null; then
            yum install -y git
        elif command -v dnf &>/dev/null; then
            dnf install -y git
        elif command -v brew &>/dev/null; then
            brew install git
        else
            log_warn "Please install Git manually"
        fi
    fi
    
    # Build tools for some adapters
    if command -v apt-get &>/dev/null; then
        apt-get install -y build-essential python3-dev
    elif command -v yum &>/dev/null; then
        yum groupinstall -y "Development Tools"
        yum install -y python3-devel
    elif command -v dnf &>/dev/null; then
        dnf groupinstall -y "Development Tools"
        dnf install -y python3-devel
    fi
}

# Check and install pip if needed
check_pip() {
    local python_cmd="$1"
    
    log_info "Checking pip installation..."
    
    # Check if pip module is available
    if ! "$python_cmd" -m pip --version &>/dev/null; then
        log_info "pip not found. Installing pip..."
        install_pip "$python_cmd"
    else
        log_debug "pip is available"
    fi
}

# Install pip
install_pip() {
    local python_cmd="$1"
    
    log_info "Installing pip..."
    
    # Try different methods to install pip
    if command -v apt-get &>/dev/null; then
        apt-get update
        if [[ -n "$PYTHON_VERSION" ]]; then
            apt-get install -y "python$PYTHON_VERSION-pip"
        else
            apt-get install -y python3-pip
        fi
    elif command -v yum &>/dev/null; then
        if [[ -n "$PYTHON_VERSION" ]]; then
            yum install -y "python$PYTHON_VERSION-pip"
        else
            yum install -y python3-pip
        fi
    elif command -v dnf &>/dev/null; then
        if [[ -n "$PYTHON_VERSION" ]]; then
            dnf install -y "python$PYTHON_VERSION-pip"
        else
            dnf install -y python3-pip
        fi
    elif command -v brew &>/dev/null; then
        # pip usually comes with Python on macOS when installed via brew
        log_warn "pip should be included with Python installation on macOS"
    else
        # Fall back to get-pip.py method
        log_info "Using get-pip.py bootstrap method..."
        local temp_dir=$(mktemp -d)
        trap "rm -rf $temp_dir" EXIT
        
        if command -v curl &>/dev/null; then
            curl -o "$temp_dir/get-pip.py" https://bootstrap.pypa.io/get-pip.py
        elif command -v wget &>/dev/null; then
            wget -O "$temp_dir/get-pip.py" https://bootstrap.pypa.io/get-pip.py
        else
            error_exit "Cannot download get-pip.py. Please install pip manually."
        fi
        
        "$python_cmd" "$temp_dir/get-pip.py" || error_exit "Failed to install pip using get-pip.py"
    fi
    
    # Verify pip installation
    if ! "$python_cmd" -m pip --version &>/dev/null; then
        error_exit "pip installation failed"
    fi
    
    log_info "pip installed successfully"
}

# Check Python installation
check_python() {
    log_info "Checking Python installation..."
    
    local python_cmd="python3"
    if [[ -n "$PYTHON_VERSION" ]]; then
        python_cmd="python$PYTHON_VERSION"
    fi
    
    if ! command -v "$python_cmd" &>/dev/null; then
        log_info "Python not found. Installing Python..."
        install_python
    fi
    
    # Check Python version
    local py_version=$("$python_cmd" --version 2>&1 | cut -d' ' -f2)
    local major=$(echo "$py_version" | cut -d'.' -f1)
    local minor=$(echo "$py_version" | cut -d'.' -f2)
    
    if [[ "$major" -lt 3 || ("$major" -eq 3 && "$minor" -lt 8) ]]; then
        error_exit "Python 3.8+ is required. Found: $py_version"
    fi
    
    log_debug "Python version: $py_version"
    
    # Check and install pip if needed
    check_pip "$python_cmd"
    
    echo "$python_cmd"
}

# Install Python
install_python() {
    log_info "Installing Python..."
    
    if command -v apt-get &>/dev/null; then
        apt-get update
        if [[ -n "$PYTHON_VERSION" ]]; then
            apt-get install -y "python$PYTHON_VERSION" "python$PYTHON_VERSION-pip" "python$PYTHON_VERSION-venv"
        else
            apt-get install -y python3 python3-pip python3-venv
        fi
    elif command -v yum &>/dev/null; then
        if [[ -n "$PYTHON_VERSION" ]]; then
            yum install -y "python$PYTHON_VERSION" "python$PYTHON_VERSION-pip"
        else
            yum install -y python3 python3-pip
        fi
    elif command -v dnf &>/dev/null; then
        if [[ -n "$PYTHON_VERSION" ]]; then
            dnf install -y "python$PYTHON_VERSION" "python$PYTHON_VERSION-pip"
        else
            dnf install -y python3 python3-pip
        fi
    elif command -v brew &>/dev/null; then
        if [[ -n "$PYTHON_VERSION" ]]; then
            brew install "python@$PYTHON_VERSION"
        else
            brew install python
        fi
    else
        error_exit "Cannot install Python automatically. Please install Python 3.8+ manually."
    fi
}

# Setup virtual environment
setup_venv() {
    if [[ -z "$VENV_PATH" ]]; then
        return
    fi
    
    local python_cmd="$1"
    
    log_info "Creating virtual environment at $VENV_PATH..."
    
    # Create virtual environment
    "$python_cmd" -m venv "$VENV_PATH" || error_exit "Failed to create virtual environment"
    
    # Activate virtual environment
    source "$VENV_PATH/bin/activate" || error_exit "Failed to activate virtual environment"
    
    # Upgrade pip
    "$python_cmd" -m pip install --upgrade pip
    
    log_info "Virtual environment created and activated"
}

# Get latest dbt version
get_latest_version() {
    log_info "Fetching latest dbt version..."
    
    local version=""
    if command -v curl &>/dev/null; then
        version=$(curl -s "https://pypi.org/pypi/dbt-core/json" | grep -o '"version":"[^"]*"' | head -1 | cut -d'"' -f4)
    elif command -v wget &>/dev/null; then
        version=$(wget -qO- "https://pypi.org/pypi/dbt-core/json" | grep -o '"version":"[^"]*"' | head -1 | cut -d'"' -f4)
    else
        log_warn "Cannot fetch latest version. Using pip to determine latest."
        return
    fi
    
    if [[ -n "$version" ]]; then
        echo "$version"
    fi
}

# Validate adapters
validate_adapters() {
    if [[ ${#ADAPTERS[@]} -eq 0 ]]; then
        log_warn "No database adapters specified. Installing dbt-core only."
        return
    fi
    
    log_info "Validating database adapters..."
    
    for adapter in "${ADAPTERS[@]}"; do
        local valid=false
        for supported in "${SUPPORTED_ADAPTERS[@]}"; do
            if [[ "$adapter" == "$supported" ]]; then
                valid=true
                break
            fi
        done
        
        if [[ "$valid" != "true" ]]; then
            error_exit "Unsupported adapter: $adapter. Supported: ${SUPPORTED_ADAPTERS[*]}"
        fi
    done
    
    log_debug "Adapters validated: ${ADAPTERS[*]}"
}

# Install dbt core and adapters
install_dbt() {
    log_info "Installing dbt Core..."
    
    # Get python command
    local python_cmd="python3"
    if [[ -n "$PYTHON_VERSION" ]]; then
        python_cmd="python$PYTHON_VERSION"
    fi
    
    # Determine version
    local version="$DBT_VERSION"
    if [[ "$version" == "latest" ]]; then
        local latest=$(get_latest_version)
        if [[ -n "$latest" ]]; then
            version="$latest"
            log_debug "Latest version: $version"
        else
            version=""
        fi
    fi
    
    # Build installation command
    local pip_cmd="$python_cmd -m pip install"
    
    if [[ "$UPGRADE" == "true" ]]; then
        pip_cmd="$pip_cmd --upgrade"
    fi
    
    # Install dbt-core
    local package="dbt-core"
    if [[ -n "$version" ]]; then
        package="dbt-core==$version"
    fi
    
    log_info "Installing $package..."
    $pip_cmd "$package" || error_exit "Failed to install dbt-core"
    
    # Install adapters
    for adapter in "${ADAPTERS[@]}"; do
        local adapter_package="dbt-$adapter"
        if [[ -n "$version" ]]; then
            adapter_package="dbt-$adapter==$version"
        fi
        
        log_info "Installing adapter: $adapter_package..."
        $pip_cmd "$adapter_package" || error_exit "Failed to install adapter: $adapter"
    done
}

# Verify installation
verify_installation() {
    log_info "Verifying dbt installation..."
    
    # Check dbt command
    if ! command -v dbt &>/dev/null; then
        error_exit "dbt command not found after installation"
    fi
    
    # Check version
    local installed_version=$(dbt --version | grep "Core:" | awk '{print $2}' || echo "unknown")
    log_info "dbt Core $installed_version installed successfully!"
    
    # Check adapters
    if [[ ${#ADAPTERS[@]} -gt 0 ]]; then
        log_info "Installed adapters:"
        dbt --version | grep -E "^\s+-" | while read -r line; do
            log_debug "$line"
        done
    fi
}

# Setup dbt profiles directory
setup_profiles() {
    local profiles_dir="$HOME/.dbt"
    
    if [[ ! -d "$profiles_dir" ]]; then
        log_info "Creating dbt profiles directory..."
        mkdir -p "$profiles_dir"
    fi
    
    # Create example profiles.yml if it doesn't exist
    local profiles_file="$profiles_dir/profiles.yml"
    if [[ ! -f "$profiles_file" ]]; then
        log_info "Creating example profiles.yml..."
        
        cat > "$profiles_file" << 'EOF'
# Example dbt profiles.yml
# Configure your database connections here
# Documentation: https://docs.getdbt.com/docs/core/connect-data-platform/profiles.yml

# Example PostgreSQL configuration
# my_project:
#   target: dev
#   outputs:
#     dev:
#       type: postgres
#       host: localhost
#       user: postgres
#       password: password
#       port: 5432
#       dbname: my_database
#       schema: public
#       threads: 4
#       keepalives_idle: 0

# Example Snowflake configuration
# my_project:
#   target: dev
#   outputs:
#     dev:
#       type: snowflake
#       account: my_account
#       user: my_user
#       password: my_password
#       role: my_role
#       database: my_database
#       warehouse: my_warehouse
#       schema: public
#       threads: 4
EOF
        
        log_info "Example profiles.yml created at $profiles_file"
        log_warn "Please configure your database connections in $profiles_file"
    fi
}

# Print usage examples
print_examples() {
    echo
    print_color "$GREEN" "dbt Core Installation Complete!"
    echo
    echo "Quick Start Guide:"
    echo "=================="
    echo
    echo "# Check installation"
    echo "dbt --version"
    echo
    echo "# Initialize a new dbt project"
    echo "dbt init my_project"
    echo "cd my_project"
    echo
    echo "# Configure database connection"
    echo "# Edit ~/.dbt/profiles.yml with your database details"
    echo
    echo "# Test connection"
    echo "dbt debug"
    echo
    echo "# Run models"
    echo "dbt run"
    echo
    echo "# Test data quality"
    echo "dbt test"
    echo
    echo "# Generate and serve documentation"
    echo "dbt docs generate"
    echo "dbt docs serve"
    echo
    echo "# Install dbt packages"
    echo "# Add packages to packages.yml, then:"
    echo "dbt deps"
    echo
    echo "Configuration:"
    echo "=============="
    echo "- Profiles: ~/.dbt/profiles.yml"
    echo "- Global config: ~/.dbt/global_config/"
    
    if [[ -n "$VENV_PATH" ]]; then
        echo
        print_color "$YELLOW" "Virtual Environment:"
        echo "- Path: $VENV_PATH"
        echo "- Activate: source $VENV_PATH/bin/activate"
        echo "- Deactivate: deactivate"
    fi
    
    echo
    echo "Documentation: https://docs.getdbt.com/"
    echo "Community: https://community.getdbt.com/"
}

# Show usage
usage() {
    cat << EOF
Usage: $SCRIPT_NAME [options]

Options:
  -h, --help              Show this help message
  -v, --version VERSION   Install specific version (default: latest)
  -a, --adapter ADAPTER   Install database adapter (comma-separated for multiple)
  -p, --python-version VER Python version to use (default: system default)
  --venv PATH             Create virtual environment at path
  --global                Install globally (not recommended)
  --upgrade               Upgrade existing installation
  --with-deps             Install additional dependencies (git, etc.)
  -V, --verbose           Enable verbose output

Database Adapters:
  postgres, snowflake, bigquery, redshift, databricks, spark, trino, clickhouse

Examples:
  # Install with PostgreSQL adapter
  $SCRIPT_NAME --adapter postgres

  # Install in virtual environment
  $SCRIPT_NAME --venv ~/dbt-env --adapter snowflake

  # Install specific version with multiple adapters
  $SCRIPT_NAME --version 1.7.0 --adapter postgres,bigquery

  # Install with system dependencies
  sudo $SCRIPT_NAME --with-deps --adapter postgres
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
                DBT_VERSION="$2"
                shift 2
                ;;
            -a|--adapter)
                IFS=',' read -ra ADAPTERS <<< "$2"
                shift 2
                ;;
            -p|--python-version)
                PYTHON_VERSION="$2"
                shift 2
                ;;
            --venv)
                VENV_PATH="$2"
                shift 2
                ;;
            --global)
                GLOBAL_INSTALL=true
                shift
                ;;
            --upgrade)
                UPGRADE=true
                shift
                ;;
            --with-deps)
                INSTALL_DEPS=true
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
    log_info "Starting dbt Core installation"
    
    # Parse arguments
    parse_args "$@"
    
    # Check system compatibility
    check_system
    
    # Install system dependencies if requested
    if [[ "$INSTALL_DEPS" == "true" ]]; then
        install_dependencies
    fi
    
    # Check Python
    local python_cmd=$(check_python)
    
    # Setup virtual environment if requested
    if [[ -n "$VENV_PATH" ]]; then
        setup_venv "$python_cmd"
    fi
    
    # Validate adapters
    validate_adapters
    
    # Install dbt
    install_dbt
    
    # Verify installation
    verify_installation
    
    # Setup profiles
    setup_profiles
    
    # Print examples
    print_examples
}

# Run main
main "$@"