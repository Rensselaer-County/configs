#!/bin/bash

# Advanced user creation script for Ubuntu 24.04+
# Supports:
#   --sudo
#   --ssh-key <file_or_key_string>
#   --password <password>
#   --force-password-change
#   --no-password (disable password login)

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status()  { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

show_usage() {
    echo "Usage: add-user <username> [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --sudo                        Grant sudo access"
    echo "  --ssh-key <key|file>          SSH public key string or file"
    echo "  --password <password>         Set specific password"
    echo "  --force-password-change       Force password change on first login"
    echo "  --no-password                 Disable password authentication"
    echo "  --help                        Show this help"
}

# Root check
if [[ $EUID -ne 0 ]]; then
    print_error "Run as root (sudo)"
    exit 1
fi

if [[ $# -lt 1 ]]; then
    print_error "Username required"
    show_usage
    exit 1
fi

USERNAME="$1"
shift

GRANT_SUDO=false
SSH_KEY=""
PASSWORD=""
FORCE_PASS_CHANGE=false
NO_PASSWORD=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sudo)
            GRANT_SUDO=true
            shift
            ;;
        --ssh-key)
            SSH_KEY="$2"
            shift 2
            ;;
        --password)
            PASSWORD="$2"
            shift 2
            ;;
        --force-password-change)
            FORCE_PASS_CHANGE=true
            shift
            ;;
        --no-password)
            NO_PASSWORD=true
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

# Username validation
if [[ ! "$USERNAME" =~ ^[a-z][-a-z0-9_]*$ ]]; then
    print_error "Invalid username format"
    exit 1
fi

if id "$USERNAME" &>/dev/null; then
    print_error "User already exists"
    exit 1
fi

print_status "Creating user '$USERNAME'..."
useradd -m -s /bin/bash "$USERNAME"

# Password logic
if [[ "$NO_PASSWORD" == true ]]; then
    passwd -l "$USERNAME"
    print_warning "Password login disabled"
else
    if [[ -z "$PASSWORD" ]]; then
        PASSWORD=$(openssl rand -base64 16)
        print_status "Generated random password"
    fi

    echo "$USERNAME:$PASSWORD" | chpasswd

    if [[ "$FORCE_PASS_CHANGE" == true ]]; then
        chage -d 0 "$USERNAME"
        print_status "User must change password on first login"
    fi
fi

# Ensure rensselaer group exists
if ! getent group rensselaer > /dev/null; then
    groupadd rensselaer
fi
usermod -a -G rensselaer "$USERNAME"

# Sudo
if [[ "$GRANT_SUDO" == true ]]; then
    usermod -a -G sudo "$USERNAME"
fi

# SSH Key handling
if [[ -n "$SSH_KEY" ]]; then
    USER_HOME="/home/$USERNAME"
    SSH_DIR="$USER_HOME/.ssh"
    AUTHORIZED_KEYS="$SSH_DIR/authorized_keys"

    mkdir -p "$SSH_DIR"
    touch "$AUTHORIZED_KEYS"

    if [[ -f "$SSH_KEY" ]]; then
        KEY_CONTENT=$(cat "$SSH_KEY")
    else
        KEY_CONTENT="$SSH_KEY"
    fi

    # Prevent duplicates
    if ! grep -qxF "$KEY_CONTENT" "$AUTHORIZED_KEYS"; then
        echo "$KEY_CONTENT" >> "$AUTHORIZED_KEYS"
        print_status "SSH key added"
    else
        print_warning "SSH key already exists"
    fi

    chown -R "$USERNAME:$USERNAME" "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    chmod 600 "$AUTHORIZED_KEYS"
fi

echo ""
print_status "User setup complete"
echo "----------------------------------------"
echo "Username: $USERNAME"
echo "Groups: $(groups $USERNAME | cut -d: -f2)"
echo "Sudo: $GRANT_SUDO"
echo "SSH key: $([[ -n "$SSH_KEY" ]] && echo YES || echo NO)"
echo "Password disabled: $NO_PASSWORD"
if [[ "$NO_PASSWORD" == false ]]; then
    echo "Password: $PASSWORD"
fi
echo "----------------------------------------"
