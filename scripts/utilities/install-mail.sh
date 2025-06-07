#!/bin/bash

# Script: install-mail.sh
# Purpose: Install and configure mail system for sending emails
# Author: Server Automation Library
# Date: 2025-01-06
# Version: 1.0

# Documentation
# =============
# Description:
#   Installs and configures mail utilities for sending emails from the server.
#   Supports multiple mail transfer agents (MTAs) and email providers including
#   local sendmail, postfix, AWS SES, Gmail, and other SMTP services.
#
# Prerequisites:
#   - Root access (sudo)
#   - Internet connection for package installation
#   - Valid email credentials for external SMTP services
#
# Supported MTAs:
#   - Postfix (recommended)
#   - Sendmail
#   - SSMTP (lightweight, send-only)
#   - MSMTP (lightweight, multiple accounts)
#
# Supported Providers:
#   - Local delivery
#   - Gmail/Google Workspace
#   - AWS SES
#   - SendGrid
#   - Mailgun
#   - Generic SMTP
#
# Usage:
#   sudo ./install-mail.sh [options]
#
# Options:
#   -h, --help              Show this help message
#   -m, --mta MTA           Mail Transfer Agent: postfix, sendmail, ssmtp, msmtp (default: postfix)
#   -p, --provider PROVIDER Email provider: local, gmail, aws-ses, sendgrid, mailgun, smtp
#   -e, --email EMAIL       From email address
#   -n, --name NAME         From name (default: hostname)
#   -s, --smtp-host HOST    SMTP server hostname
#   -o, --smtp-port PORT    SMTP port (default: 587)
#   -u, --smtp-user USER    SMTP username
#   -w, --smtp-pass PASS    SMTP password (use -W for prompt)
#   -W, --ask-pass          Prompt for SMTP password
#   -t, --test-email EMAIL  Send test email to this address
#   -r, --relay-only        Configure as relay-only (no local delivery)
#   --tls                   Enable TLS (default)
#   --no-tls                Disable TLS
#   -v, --verbose           Enable verbose output
#
# Examples:
#   # Install postfix for local mail
#   sudo ./install-mail.sh -m postfix -p local
#
#   # Configure Gmail relay
#   sudo ./install-mail.sh -p gmail -e myapp@gmail.com -W
#
#   # Configure AWS SES
#   sudo ./install-mail.sh -p aws-ses -s email-smtp.us-east-1.amazonaws.com -u AKIAIOSFODNN7EXAMPLE -W
#
#   # Configure generic SMTP with test
#   sudo ./install-mail.sh -p smtp -s smtp.example.com -e noreply@example.com -W -t admin@example.com
#
# Post-Installation:
#   - Test: echo "Test" | mail -s "Test Subject" recipient@example.com
#   - Logs: /var/log/mail.log or journalctl -u postfix
#   - Queue: mailq (postfix) or sendmail -bp

set -euo pipefail

# Script variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/mail-install.log"
VERBOSE=false

# Configuration variables
MTA="postfix"
PROVIDER=""
FROM_EMAIL=""
FROM_NAME="$(hostname)"
SMTP_HOST=""
SMTP_PORT="587"
SMTP_USER=""
SMTP_PASS=""
ASK_PASS=false
TEST_EMAIL=""
RELAY_ONLY=false
USE_TLS=true

# OS detection
OS=""
OS_VERSION=""

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

# Detect OS
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    else
        error_exit "Cannot detect OS version"
    fi
    
    log "INFO" "Detected OS: $OS $OS_VERSION"
}

# Install packages based on OS
install_packages() {
    local packages=("$@")
    
    log "INFO" "Installing packages: ${packages[*]}"
    
    case $OS in
        ubuntu|debian)
            apt-get update -qq
            DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
            ;;
        centos|rhel|fedora)
            yum install -y "${packages[@]}"
            ;;
        *)
            error_exit "Unsupported OS: $OS"
            ;;
    esac
}

# Install Postfix
install_postfix() {
    log "INFO" "Installing Postfix..."
    
    # Preseed postfix configuration
    case $OS in
        ubuntu|debian)
            debconf-set-selections <<< "postfix postfix/mailname string $(hostname -f)"
            debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
            ;;
    esac
    
    install_packages postfix mailutils libsasl2-2 ca-certificates libsasl2-modules
    
    # Start and enable postfix
    systemctl enable postfix
    systemctl start postfix
}

# Install Sendmail
install_sendmail() {
    log "INFO" "Installing Sendmail..."
    
    install_packages sendmail sendmail-cf m4 mailx
    
    # Start and enable sendmail
    systemctl enable sendmail
    systemctl start sendmail
}

# Install SSMTP
install_ssmtp() {
    log "INFO" "Installing SSMTP..."
    
    install_packages ssmtp mailutils
}

# Install MSMTP
install_msmtp() {
    log "INFO" "Installing MSMTP..."
    
    install_packages msmtp msmtp-mta mailutils ca-certificates
}

# Configure Postfix for relay
configure_postfix_relay() {
    log "INFO" "Configuring Postfix as relay..."
    
    # Backup original configuration
    cp /etc/postfix/main.cf /etc/postfix/main.cf.bak
    
    # Basic relay configuration
    cat >> /etc/postfix/main.cf << EOF

# Relay Configuration
relayhost = [$SMTP_HOST]:$SMTP_PORT
smtp_sasl_auth_enable = yes
smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd
smtp_sasl_security_options = noanonymous
smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt
smtp_use_tls = yes
smtp_tls_security_level = encrypt
smtp_tls_note_starttls_offer = yes
smtp_tls_loglevel = 1
smtp_tls_session_cache_database = btree:\${data_directory}/smtp_scache

# Additional settings
myhostname = $(hostname -f)
mydestination = localhost
mynetworks = 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128
mailbox_size_limit = 0
recipient_delimiter = +
inet_interfaces = loopback-only
inet_protocols = all
EOF

    # Create password file
    echo "[$SMTP_HOST]:$SMTP_PORT $SMTP_USER:$SMTP_PASS" > /etc/postfix/sasl_passwd
    chmod 600 /etc/postfix/sasl_passwd
    postmap /etc/postfix/sasl_passwd
    
    # Set sender canonical maps if FROM_EMAIL is specified
    if [[ -n "$FROM_EMAIL" ]]; then
        echo "/.+/ $FROM_EMAIL" > /etc/postfix/sender_canonical_maps
        echo "sender_canonical_maps = regexp:/etc/postfix/sender_canonical_maps" >> /etc/postfix/main.cf
        echo "sender_canonical_classes = envelope_sender, header_sender" >> /etc/postfix/main.cf
    fi
    
    # Restart postfix
    systemctl restart postfix
}

# Configure SSMTP
configure_ssmtp() {
    log "INFO" "Configuring SSMTP..."
    
    # Backup original configuration
    cp /etc/ssmtp/ssmtp.conf /etc/ssmtp/ssmtp.conf.bak 2>/dev/null || true
    
    # Create new configuration
    cat > /etc/ssmtp/ssmtp.conf << EOF
# SSMTP Configuration
root=$FROM_EMAIL
mailhub=$SMTP_HOST:$SMTP_PORT
FromLineOverride=YES
AuthUser=$SMTP_USER
AuthPass=$SMTP_PASS
UseTLS=$( [[ "$USE_TLS" == "true" ]] && echo "YES" || echo "NO" )
UseSTARTTLS=$( [[ "$USE_TLS" == "true" ]] && echo "YES" || echo "NO" )
TLS_CA_File=/etc/ssl/certs/ca-certificates.crt
hostname=$(hostname -f)
EOF
    
    chmod 640 /etc/ssmtp/ssmtp.conf
    
    # Configure revaliases
    echo "root:$FROM_EMAIL:$SMTP_HOST:$SMTP_PORT" > /etc/ssmtp/revaliases
    echo "$(whoami):$FROM_EMAIL:$SMTP_HOST:$SMTP_PORT" >> /etc/ssmtp/revaliases
    chmod 640 /etc/ssmtp/revaliases
}

# Configure MSMTP
configure_msmtp() {
    log "INFO" "Configuring MSMTP..."
    
    # Create configuration directory
    mkdir -p /etc/msmtp
    
    # Create configuration
    cat > /etc/msmtprc << EOF
# MSMTP Configuration
defaults
auth           on
tls            $( [[ "$USE_TLS" == "true" ]] && echo "on" || echo "off" )
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /var/log/msmtp.log

account        default
host           $SMTP_HOST
port           $SMTP_PORT
from           $FROM_EMAIL
user           $SMTP_USER
password       $SMTP_PASS

account default : default
EOF
    
    chmod 600 /etc/msmtprc
    
    # Create log file
    touch /var/log/msmtp.log
    chmod 666 /var/log/msmtp.log
    
    # Set as default MTA
    ln -sf /usr/bin/msmtp /usr/sbin/sendmail 2>/dev/null || true
}

# Configure for Gmail
configure_gmail() {
    log "INFO" "Configuring for Gmail..."
    
    SMTP_HOST="smtp.gmail.com"
    SMTP_PORT="587"
    
    if [[ -z "$SMTP_USER" ]]; then
        SMTP_USER="$FROM_EMAIL"
    fi
    
    log "WARN" "Gmail requires an App Password, not your regular password"
    log "WARN" "Enable 2FA and create an App Password at: https://myaccount.google.com/apppasswords"
}

# Configure for AWS SES
configure_aws_ses() {
    log "INFO" "Configuring for AWS SES..."
    
    if [[ -z "$SMTP_HOST" ]]; then
        log "WARN" "AWS SES SMTP endpoint required. Common endpoints:"
        log "WARN" "  - email-smtp.us-east-1.amazonaws.com"
        log "WARN" "  - email-smtp.us-west-2.amazonaws.com"
        log "WARN" "  - email-smtp.eu-west-1.amazonaws.com"
        error_exit "Please specify SMTP host with -s option"
    fi
    
    SMTP_PORT="587"
    
    log "INFO" "AWS SES requires SMTP credentials (not regular AWS credentials)"
    log "INFO" "Generate at: https://console.aws.amazon.com/ses/home#/smtp"
}

# Configure provider
configure_provider() {
    case $PROVIDER in
        local)
            log "INFO" "Configuring for local delivery only"
            RELAY_ONLY=false
            ;;
        gmail)
            configure_gmail
            ;;
        aws-ses)
            configure_aws_ses
            ;;
        sendgrid)
            SMTP_HOST="smtp.sendgrid.net"
            SMTP_PORT="587"
            SMTP_USER="apikey"
            log "INFO" "SendGrid: Use 'apikey' as username and your API key as password"
            ;;
        mailgun)
            if [[ -z "$SMTP_HOST" ]]; then
                SMTP_HOST="smtp.mailgun.org"
            fi
            SMTP_PORT="587"
            ;;
        smtp)
            if [[ -z "$SMTP_HOST" ]]; then
                error_exit "SMTP host required for generic SMTP configuration"
            fi
            ;;
        *)
            if [[ -n "$PROVIDER" ]]; then
                error_exit "Unknown provider: $PROVIDER"
            fi
            ;;
    esac
}

# Test email configuration
test_email() {
    local recipient="$1"
    
    log "INFO" "Sending test email to: $recipient"
    
    # Create test message
    local subject="Test Email from $(hostname)"
    local body="This is a test email sent from $(hostname) at $(date).

Mail system: $MTA
Provider: ${PROVIDER:-local}
From: ${FROM_EMAIL:-root@$(hostname)}

If you received this email, your mail configuration is working correctly."
    
    # Send test email
    echo "$body" | mail -s "$subject" "$recipient"
    
    if [[ $? -eq 0 ]]; then
        log "INFO" "Test email sent successfully"
        log "INFO" "Check the recipient's inbox and the mail logs:"
        
        case $MTA in
            postfix)
                log "INFO" "  - View logs: tail -f /var/log/mail.log"
                log "INFO" "  - Check queue: mailq"
                ;;
            sendmail)
                log "INFO" "  - View logs: tail -f /var/log/maillog"
                log "INFO" "  - Check queue: sendmail -bp"
                ;;
            ssmtp|msmtp)
                log "INFO" "  - View logs: tail -f /var/log/syslog | grep -E 'ssmtp|msmtp'"
                ;;
        esac
    else
        log "ERROR" "Failed to send test email"
        return 1
    fi
}

# Create mail wrapper script
create_mail_wrapper() {
    log "INFO" "Creating mail wrapper script..."
    
    cat > /usr/local/bin/send-mail << 'EOF'
#!/bin/bash
# Simple mail sending wrapper

usage() {
    echo "Usage: send-mail -t recipient@example.com -s 'Subject' [-b 'Body'] [-f from@example.com]"
    echo "  or:  echo 'Body' | send-mail -t recipient@example.com -s 'Subject'"
    exit 1
}

TO=""
SUBJECT=""
BODY=""
FROM=""

while getopts "t:s:b:f:h" opt; do
    case $opt in
        t) TO="$OPTARG" ;;
        s) SUBJECT="$OPTARG" ;;
        b) BODY="$OPTARG" ;;
        f) FROM="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

if [[ -z "$TO" ]] || [[ -z "$SUBJECT" ]]; then
    usage
fi

# Read from stdin if no body provided
if [[ -z "$BODY" ]] && [[ ! -t 0 ]]; then
    BODY=$(cat)
fi

# Send email
if [[ -n "$FROM" ]]; then
    echo "$BODY" | mail -r "$FROM" -s "$SUBJECT" "$TO"
else
    echo "$BODY" | mail -s "$SUBJECT" "$TO"
fi
EOF
    
    chmod +x /usr/local/bin/send-mail
}

# Print configuration summary
print_summary() {
    echo
    echo -e "${GREEN}Mail System Installation Summary${NC}"
    echo "================================="
    echo "MTA: $MTA"
    echo "Provider: ${PROVIDER:-local}"
    
    if [[ "$PROVIDER" != "local" ]]; then
        echo "SMTP Host: $SMTP_HOST"
        echo "SMTP Port: $SMTP_PORT"
        echo "SMTP User: $SMTP_USER"
        echo "From Email: ${FROM_EMAIL:-root@$(hostname)}"
    fi
    
    echo
    echo -e "${GREEN}Testing Commands:${NC}"
    echo "# Send a test email:"
    echo "echo 'Test message' | mail -s 'Test Subject' recipient@example.com"
    echo
    echo "# Using the wrapper:"
    echo "send-mail -t recipient@example.com -s 'Test Subject' -b 'Test message'"
    echo
    
    case $MTA in
        postfix)
            echo -e "${GREEN}Postfix Commands:${NC}"
            echo "# View mail queue: mailq"
            echo "# Flush queue: postfix flush"
            echo "# View logs: tail -f /var/log/mail.log"
            echo "# Restart: systemctl restart postfix"
            ;;
        sendmail)
            echo -e "${GREEN}Sendmail Commands:${NC}"
            echo "# View mail queue: sendmail -bp"
            echo "# Process queue: sendmail -q"
            echo "# View logs: tail -f /var/log/maillog"
            echo "# Restart: systemctl restart sendmail"
            ;;
        ssmtp|msmtp)
            echo -e "${GREEN}${MTA^^} Info:${NC}"
            echo "# Configuration: /etc/${MTA}/${MTA}.conf or /etc/${MTA}rc"
            echo "# View logs: grep $MTA /var/log/syslog"
            ;;
    esac
    
    echo
    echo -e "${YELLOW}Troubleshooting:${NC}"
    echo "# Test connectivity: telnet $SMTP_HOST $SMTP_PORT"
    echo "# Check DNS: nslookup $SMTP_HOST"
    echo "# Verify TLS: openssl s_client -starttls smtp -connect $SMTP_HOST:$SMTP_PORT"
}

# Usage function
usage() {
    grep "^#" "$0" | grep -E "^# (Usage|Options|Examples):" -A 50 | grep -E "^#( |$)" | sed 's/^# //'
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -m|--mta)
                MTA="$2"
                shift 2
                ;;
            -p|--provider)
                PROVIDER="$2"
                shift 2
                ;;
            -e|--email)
                FROM_EMAIL="$2"
                shift 2
                ;;
            -n|--name)
                FROM_NAME="$2"
                shift 2
                ;;
            -s|--smtp-host)
                SMTP_HOST="$2"
                shift 2
                ;;
            -o|--smtp-port)
                SMTP_PORT="$2"
                shift 2
                ;;
            -u|--smtp-user)
                SMTP_USER="$2"
                shift 2
                ;;
            -w|--smtp-pass)
                SMTP_PASS="$2"
                shift 2
                ;;
            -W|--ask-pass)
                ASK_PASS=true
                shift
                ;;
            -t|--test-email)
                TEST_EMAIL="$2"
                shift 2
                ;;
            -r|--relay-only)
                RELAY_ONLY=true
                shift
                ;;
            --tls)
                USE_TLS=true
                shift
                ;;
            --no-tls)
                USE_TLS=false
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
    
    log "INFO" "Starting mail system installation"
    
    # Parse arguments
    parse_args "$@"
    
    # Check prerequisites
    check_root
    detect_os
    
    # Configure provider settings
    configure_provider
    
    # Ask for password if needed
    if [[ "$ASK_PASS" == "true" ]] && [[ -z "$SMTP_PASS" ]]; then
        read -sp "Enter SMTP password: " SMTP_PASS
        echo
    fi
    
    # Validate configuration
    if [[ "$PROVIDER" != "local" ]] && [[ "$PROVIDER" != "" ]]; then
        if [[ -z "$SMTP_HOST" ]] || [[ -z "$SMTP_USER" ]] || [[ -z "$SMTP_PASS" ]]; then
            error_exit "SMTP configuration incomplete. Required: host, user, password"
        fi
    fi
    
    # Install MTA
    case $MTA in
        postfix)
            install_postfix
            if [[ "$PROVIDER" != "local" ]]; then
                configure_postfix_relay
            fi
            ;;
        sendmail)
            install_sendmail
            if [[ "$PROVIDER" != "local" ]]; then
                log "WARN" "Sendmail relay configuration not automated. Manual configuration required."
            fi
            ;;
        ssmtp)
            install_ssmtp
            if [[ "$PROVIDER" != "local" ]]; then
                configure_ssmtp
            fi
            ;;
        msmtp)
            install_msmtp
            if [[ "$PROVIDER" != "local" ]]; then
                configure_msmtp
            fi
            ;;
        *)
            error_exit "Unknown MTA: $MTA"
            ;;
    esac
    
    # Create wrapper script
    create_mail_wrapper
    
    # Test if requested
    if [[ -n "$TEST_EMAIL" ]]; then
        sleep 2  # Give services time to start
        test_email "$TEST_EMAIL"
    fi
    
    # Print summary
    print_summary
    
    log "INFO" "Mail system installation completed"
}

# Run main
main "$@"