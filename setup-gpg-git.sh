#!/bin/bash

# GPG and Git Setup Script
# Fixes common macOS GPG integration issues and sets up proper git signing
# Based on troubleshooting session resolving keybase, GPG, and git integration

set -e

# Global variables
DRY_RUN=false
BREW_PREFIX=""
PINENTRY_PATH=""
GPG_PATH=""
BACKUP_DIR="$HOME/.gnupg_backup_$(date +%Y%m%d_%H%M%S)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Initialize paths based on Homebrew installation
init_paths() {
    log_info "Detecting Homebrew installation..."
    
    if command_exists brew; then
        BREW_PREFIX=$(brew --prefix)
        PINENTRY_PATH="$BREW_PREFIX/bin/pinentry-mac"
        GPG_PATH="$BREW_PREFIX/bin/gpg"
        log_success "Homebrew found at: $BREW_PREFIX"
    else
        log_error "Homebrew not found"
        return 1
    fi
}

# Validate PGP fingerprint format
validate_fingerprint() {
    local fingerprint="$1"
    
    # Remove spaces and convert to uppercase
    fingerprint=$(echo "$fingerprint" | tr -d ' ' | tr '[:lower:]' '[:upper:]')
    
    # Check if it's a valid 40-character hex string
    if [[ ${#fingerprint} -eq 40 && "$fingerprint" =~ ^[A-F0-9]+$ ]]; then
        echo "$fingerprint"
        return 0
    else
        log_error "Invalid fingerprint format. Expected 40-character hex string."
        return 1
    fi
}

# Backup existing GPG configuration
backup_gpg_config() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would backup GPG config to: $BACKUP_DIR"
        return 0
    fi
    
    if [[ -d ~/.gnupg ]]; then
        log_info "Backing up existing GPG configuration..."
        mkdir -p "$BACKUP_DIR"
        cp -r ~/.gnupg/* "$BACKUP_DIR/" 2>/dev/null || true
        log_success "GPG config backed up to: $BACKUP_DIR"
    else
        log_info "No existing GPG configuration to backup"
    fi
}

# Check if key already exists
key_exists() {
    local fingerprint="$1"
    gpg --list-keys "$fingerprint" >/dev/null 2>&1
}

# Dry run wrapper for commands
run_command() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would run: $*"
        return 0
    else
        "$@"
    fi
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                log_info "Dry run mode enabled"
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Show help information
show_help() {
    cat << EOF
GPG and Git Setup Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --dry-run    Show what would be done without making changes
    --help, -h   Show this help message

DESCRIPTION:
    This script configures GPG signing for git commits using keybase keys.
    It will install required tools, configure GPG agent, and set up git
    to automatically sign commits.

REQUIREMENTS:
    - Homebrew (https://brew.sh/)
    - Keybase (https://keybase.io/)
    - Git
EOF
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command_exists brew; then
        log_error "Homebrew is required but not installed. Install from https://brew.sh/"
        exit 1
    fi
    
    if ! command_exists keybase; then
        log_error "Keybase is required but not installed. Install from https://keybase.io/"
        exit 1
    fi
    
    if ! command_exists git; then
        log_error "Git is required but not installed."
        exit 1
    fi
    
    log_success "All prerequisites found"
}

# Setup global gitignore
setup_global_gitignore() {
    log_info "Setting up global gitignore..."
    
    run_command git config --global core.excludesfile ~/.gitignore_global
    
    if [[ ! -f ~/.gitignore_global ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would create ~/.gitignore_global"
        else
            cat > ~/.gitignore_global << 'EOF'
# macOS
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db

# Editor files
*~
*.swp
*.swo
.vscode/
.idea/

# Log files
*.log
npm-debug.log*
yarn-debug.log*
yarn-error.log*

# Runtime data
pids
*.pid
*.seed
*.pid.lock

# Temporary files
*.tmp
*.temp
EOF
            log_success "Created ~/.gitignore_global"
        fi
    else
        log_info "Global gitignore already exists"
    fi
}

# Install required tools
install_tools() {
    log_info "Installing required tools..."
    
    # Install GPG if not present
    if ! command_exists gpg; then
        log_info "Installing gnupg..."
        run_command brew install gnupg
    fi
    
    # Install pinentry-mac for native macOS integration
    if ! brew list pinentry-mac >/dev/null 2>&1; then
        log_info "Installing pinentry-mac for native macOS GUI..."
        run_command brew install pinentry-mac
    else
        log_info "pinentry-mac already installed"
    fi
    
    log_success "Tools installation complete"
}

# Fix GPG database issues
fix_gpg_database() {
    log_info "Checking GPG database..."
    
    # Test GPG and fix if broken
    if ! gpg --list-keys >/dev/null 2>&1; then
        log_warning "GPG database appears corrupted, attempting fix..."
        
        # Kill all GPG processes
        gpgconf --kill all 2>/dev/null || true
        
        # Remove socket files
        rm -rf ~/.gnupg/S.* ~/.gnupg/.#* 2>/dev/null || true
        
        # Test again
        if gpg --list-keys >/dev/null 2>&1; then
            log_success "GPG database fixed"
        else
            log_error "Failed to fix GPG database"
            exit 1
        fi
    else
        log_success "GPG database is healthy"
    fi
}

# Configure GPG agent
configure_gpg_agent() {
    log_info "Configuring GPG agent..."
    
    run_command mkdir -p ~/.gnupg
    run_command chmod 700 ~/.gnupg
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create ~/.gnupg/gpg-agent.conf with pinentry-program: $PINENTRY_PATH"
    else
        cat > ~/.gnupg/gpg-agent.conf << EOF
pinentry-program $PINENTRY_PATH
default-cache-ttl 28800
max-cache-ttl 86400
EOF
    fi
    
    # Reload GPG agent
    run_command gpgconf --reload gpg-agent
    
    log_success "GPG agent configured with pinentry-mac"
}

# List available keybase keys
list_keybase_keys() {
    log_info "Available Keybase PGP keys:"
    keybase pgp list | grep -E "(Keybase Key ID|PGP Fingerprint|PGP Identities)" | while IFS= read -r line; do
        if [[ $line == *"PGP Fingerprint"* ]]; then
            echo -e "${GREEN}$line${NC}"
        else
            echo "  $line"
        fi
    done
}

# Import key from keybase
import_keybase_key() {
    local fingerprint="$1"
    
    if [[ -z "$fingerprint" ]]; then
        log_error "No fingerprint provided"
        return 1
    fi
    
    # Validate fingerprint format
    fingerprint=$(validate_fingerprint "$fingerprint")
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    # Check if key already exists
    if key_exists "$fingerprint"; then
        log_warning "Key $fingerprint already imported"
        # Still return the key ID for git config
        local short_key_id
        short_key_id=$(gpg --list-keys --with-colons "$fingerprint" | awk -F: '/^pub:/ {print $5}' | tail -c 17)
        echo "$short_key_id"
        return 0
    fi
    
    log_info "Importing key $fingerprint from keybase..."
    
    # Import public key
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would import public key from keybase"
        log_info "[DRY RUN] Would import secret key from keybase"
        echo "DRYRUN1234567890ABCD"
        return 0
    else
        if keybase pgp export -q "$fingerprint" | gpg --import; then
            log_success "Public key imported"
        else
            log_error "Failed to import public key"
            return 1
        fi
        
        # Import secret key
        if keybase pgp export --secret -q "$fingerprint" | gpg --import --batch; then
            log_success "Secret key imported"
        else
            log_warning "Secret key import failed (this may require interactive input)"
        fi
    fi
    
    # Get the short key ID for git config
    local short_key_id
    short_key_id=$(gpg --list-keys --with-colons "$fingerprint" | awk -F: '/^pub:/ {print $5}' | tail -c 17)
    
    if [[ -n "$short_key_id" ]]; then
        log_info "Short key ID: $short_key_id"
        echo "$short_key_id"
    else
        log_error "Could not determine short key ID"
        return 1
    fi
}

# Configure git signing
configure_git_signing() {
    local key_id="$1"
    
    if [[ -z "$key_id" ]]; then
        log_error "No key ID provided for git configuration"
        return 1
    fi
    
    log_info "Configuring git for GPG signing..."
    
    # Remove any SSH signing configuration
    run_command git config --global --unset gpg.format 2>/dev/null || true
    run_command git config --global --unset gpg.ssh.program 2>/dev/null || true  
    run_command git config --global --unset gpg.ssh.allowedsignersfile 2>/dev/null || true
    
    # Set GPG signing configuration
    run_command git config --global user.signingkey "$key_id"
    run_command git config --global gpg.program "$GPG_PATH"
    run_command git config --global commit.gpgsign true
    
    log_success "Git configured for GPG signing with key $key_id"
}

# Verify configuration
verify_configuration() {
    log_info "Verifying configuration..."
    
    # Check git config
    local user_name user_email signing_key gpg_program commit_sign
    user_name=$(git config --global user.name 2>/dev/null || echo "NOT SET")
    user_email=$(git config --global user.email 2>/dev/null || echo "NOT SET")
    signing_key=$(git config --global user.signingkey 2>/dev/null || echo "NOT SET")
    gpg_program=$(git config --global gpg.program 2>/dev/null || echo "NOT SET")
    commit_sign=$(git config --global commit.gpgsign 2>/dev/null || echo "NOT SET")
    
    echo -e "\n${BLUE}=== Git Configuration ===${NC}"
    echo "User name: $user_name"
    echo "User email: $user_email"
    echo "Signing key: $signing_key"
    echo "GPG program: $gpg_program"
    echo "Auto-sign commits: $commit_sign"
    
    # Check GPG keys
    echo -e "\n${BLUE}=== GPG Keys ===${NC}"
    if gpg --list-secret-keys --with-fingerprint 2>/dev/null; then
        log_success "GPG secret keys found"
    else
        log_warning "No GPG secret keys found"
    fi
    
    # Check pinentry
    echo -e "\n${BLUE}=== GPG Agent Configuration ===${NC}"
    if [[ -f ~/.gnupg/gpg-agent.conf ]]; then
        echo "GPG agent config:"
        cat ~/.gnupg/gpg-agent.conf | sed 's/^/  /'
    else
        log_warning "No GPG agent configuration found"
    fi
    
    # Test signing (will show passphrase dialog)
    echo -e "\n${BLUE}=== Testing GPG Signing ===${NC}"
    if echo "test" | gpg --armor --detach-sign --default-key "$signing_key" >/dev/null 2>&1; then
        log_success "GPG signing test successful"
    else
        log_warning "GPG signing test failed (may require passphrase entry)"
        log_info "This is normal - signing will work when you make commits"
    fi
}

# Rollback changes in case of error
rollback_changes() {
    log_warning "Rolling back changes..."
    
    if [[ -d "$BACKUP_DIR" ]]; then
        log_info "Restoring GPG configuration from backup..."
        if [[ -d ~/.gnupg ]]; then
            rm -rf ~/.gnupg
        fi
        cp -r "$BACKUP_DIR" ~/.gnupg 2>/dev/null || true
        chmod 700 ~/.gnupg
        log_success "GPG configuration restored"
    fi
    
    # Reset git configuration
    git config --global --unset user.signingkey 2>/dev/null || true
    git config --global --unset gpg.program 2>/dev/null || true
    git config --global --unset commit.gpgsign 2>/dev/null || true
    
    log_warning "Rollback complete. Please check your configuration."
}

# Trap errors and rollback
trap 'if [[ $? -ne 0 ]]; then rollback_changes; fi' ERR

# Show next steps
show_next_steps() {
    echo -e "\n${GREEN}=== Setup Complete! ===${NC}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "\n${YELLOW}This was a dry run. No changes were made.${NC}"
        echo "Run without --dry-run to apply changes."
        return 0
    fi
    
    echo -e "\n${BLUE}Next steps:${NC}"
    echo "1. Make a test commit to verify GPG signing works"
    echo "2. When prompted, enter your keybase passphrase in the GUI dialog"
    echo "3. Your commits will now be automatically signed"
    echo ""
    echo "To manually set ultimate trust on your key (optional):"
    echo "  gpg --edit-key <your-key-id>"
    echo "  > trust"
    echo "  > 5 (ultimate trust)"
    echo "  > y"
    echo "  > quit"
    echo ""
    echo "Backup created at: $BACKUP_DIR"
}

# Main execution
main() {
    # Parse command line arguments first
    parse_args "$@"
    
    echo -e "${BLUE}GPG and Git Setup Script${NC}"
    echo "This script will configure GPG signing for git commits using keybase keys"
    echo ""
    
    # Initialize paths
    init_paths
    
    # Backup existing configuration
    backup_gpg_config
    
    check_prerequisites
    setup_global_gitignore
    install_tools
    fix_gpg_database
    configure_gpg_agent
    
    echo ""
    if [[ "$DRY_RUN" != "true" ]]; then
        list_keybase_keys
        echo ""
        
        # Interactive key selection
        echo -e "${YELLOW}Enter the PGP fingerprint of the key you want to use for git signing:${NC}"
        read -r fingerprint
        
        if [[ -z "$fingerprint" ]]; then
            log_error "No fingerprint provided"
            exit 1
        fi
    else
        fingerprint="ABCDEF1234567890ABCDEF1234567890ABCDEF12"
        log_info "[DRY RUN] Using dummy fingerprint for demonstration"
    fi
    
    # Import the key
    key_id=$(import_keybase_key "$fingerprint")
    if [[ $? -ne 0 ]]; then
        log_error "Failed to import key"
        exit 1
    fi
    
    # Configure git
    configure_git_signing "$key_id"
    
    # Verify everything
    if [[ "$DRY_RUN" != "true" ]]; then
        verify_configuration
    fi
    
    # Show next steps
    show_next_steps
}

# Run main function
main "$@"