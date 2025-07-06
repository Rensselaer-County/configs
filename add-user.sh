#!/bin/bash

# Script to add users to Ubuntu 24.04 server
# Usage: ./add-user.sh <username> --ssh-key <key_file_or_string> --password <password> [OPTIONS]

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 <username> --ssh-key <key> --password <password> [OPTIONS]"
    echo ""
    echo "Arguments:"
    echo "  <username>             The username to create"
    echo "  --ssh-key <key>        SSH public key (file path or key string)"
    echo "  --password <password>  A temporary password for the user"
    echo ""
    echo "Options:"
    echo "  --sudo                 Grant sudo access to the user"
    echo "  --force-password-change Force user to change password on first login"
    echo "  --help                 Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 john --ssh-key /path/to/key.pub --password 'somepassword' --sudo --force-password-change"
    echo "  $0 jane --ssh-key \"ssh-rsa AAAAB3NzaC1yc2E...\" --password 'anotherpassword'"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root (use sudo)"
    exit 1
fi

# Parse command line arguments
USERNAME=""
GRANT_SUDO=false
SSH_KEY=""
TEMP_PASSWORD=""
FORCE_PASSWORD_CHANGE=false

if [[ $# -eq 0 ]]; then
    print_error "No username provided"
    show_usage
    exit 1
fi

USERNAME="$1"
shift

while [[ $# -gt 0 ]]; do
    case $1 in
        --sudo)
            GRANT_SUDO=true
            shift
            ;;
        --ssh-key)
            if [[ -n "$2" ]]; then
                SSH_KEY="$2"
                shift 2
            else
                print_error "--ssh-key requires a value"
                exit 1
            fi
            ;;
        --password)
            if [[ -n "$2" ]]; then
                TEMP_PASSWORD="$2"
                shift 2
            else
                print_error "--password requires a value"
                exit 1
            fi
            ;;
        --force-password-change)
            FORCE_PASSWORD_CHANGE=true
            shift
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate username
if [[ ! "$USERNAME" =~ ^[a-z][-a-z0-9_]*$ ]]; then
    print_error "Invalid username. Username must start with a lowercase letter and contain only lowercase letters, numbers, hyphens, and underscores."
    exit 1
fi

# Check for SSH key
if [[ -z "$SSH_KEY" ]]; then
    print_error "SSH key is required. Use the --ssh-key option."
    show_usage
    exit 1
fi

# Check for temporary password
if [[ -z "$TEMP_PASSWORD" ]]; then
    print_error "Temporary password is required. Use the --password option."
    show_usage
    exit 1
fi

# Check if user already exists
if id "$USERNAME" &>/dev/null; then
    print_error "User '$USERNAME' already exists"
    exit 1
fi

print_status "Creating user '$USERNAME'..."

# Create the user with home directory
useradd -m -s /bin/bash "$USERNAME"

# Set the temporary password and force change on first login
echo "$USERNAME:$TEMP_PASSWORD" | chpasswd
print_status "User '$USERNAME' created with the provided temporary password."

if [[ "$FORCE_PASSWORD_CHANGE" == true ]]; then
    chage -d 0 "$USERNAME"
    print_warning "User will be required to change password on first login."
fi

# Create rensselaer group if it doesn't exist
if ! getent group rensselaer > /dev/null 2>&1; then
    print_status "Creating 'rensselaer' group..."
    groupadd rensselaer
fi

# Add user to rensselaer group
print_status "Adding user to 'rensselaer' group..."
usermod -a -G rensselaer "$USERNAME"

# Grant sudo access if requested
if [[ "$GRANT_SUDO" == true ]]; then
    print_status "Granting sudo access..."
    usermod -a -G sudo "$USERNAME"
fi

# Handle SSH key setup
print_status "Setting up SSH key..."

# Create .ssh directory
USER_HOME="/home/$USERNAME"
SSH_DIR="$USER_HOME/.ssh"
AUTHORIZED_KEYS="$SSH_DIR/authorized_keys"

mkdir -p "$SSH_DIR"

# Determine if SSH_KEY is a file or a key string
if [[ -f "$SSH_KEY" ]]; then
    # It's a file path
    if [[ -r "$SSH_KEY" ]]; then
        cat "$SSH_KEY" >> "$AUTHORIZED_KEYS"
        print_status "SSH key added from file: $SSH_KEY"
    else
        print_error "Cannot read SSH key file: $SSH_KEY"
        exit 1
    fi
else
    # Assume it's a key string
    echo "$SSH_KEY" >> "$AUTHORIZED_KEYS"
    print_status "SSH key added from provided string"
fi

# Set proper permissions
chown -R "$USERNAME:$USERNAME" "$SSH_DIR"
chmod 700 "$SSH_DIR"
chmod 600 "$AUTHORIZED_KEYS"

print_status "SSH key setup completed"

# Display summary
echo ""
print_status "User setup completed successfully!"
echo "----------------------------------------"
echo "Username: $USERNAME"
echo "Home directory: /home/$USERNAME"
echo "Groups: $(groups $USERNAME | cut -d: -f2)"
echo "Sudo access: $(if [[ "$GRANT_SUDO" == true ]]; then echo "YES"; else echo "NO"; fi)"
echo "SSH key configured: YES"
echo "Temporary password set: YES"
echo "Password change on first login: $(if [[ "$FORCE_PASSWORD_CHANGE" == true ]]; then echo "YES"; else echo "NO"; fi)"
echo "----------------------------------------"

if [[ "$FORCE_PASSWORD_CHANGE" == true ]]; then
    print_warning "User must change password on first login"
fi

print_status "User can now login via SSH using their private key or via password"