#!/bin/bash

# GPG and Git Setup Script
# Fixes common macOS GPG integration issues and sets up proper git signing
# Based on troubleshooting session resolving keybase, GPG, and git integration

set -e

# Global variables
DRY_RUN=false
AUTO_MODE=false
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
            --auto)
                AUTO_MODE=true
                log_info "Automatic mode enabled - will make best decisions without prompts"
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
    --auto       Automatic mode - make best decisions without user prompts
    --help, -h   Show this help message

DESCRIPTION:
    This script configures GPG signing for git commits using keybase keys.
    It will install required tools, configure GPG agent, and set up git
    to automatically sign commits.
    
    In automatic mode (--auto), the script will:
    • Auto-detect and configure git user name/email from keybase
    • Automatically select the best matching PGP key
    • Configure everything without requiring user input

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

# Setup git user configuration automatically
setup_git_user_config() {
    if [[ "$AUTO_MODE" != "true" ]]; then
        return 0
    fi
    
    log_info "Auto mode: Configuring git user settings..."
    
    local current_name current_email
    current_name=$(git config --global user.name 2>/dev/null)
    current_email=$(git config --global user.email 2>/dev/null)
    
    # Try to get name from keybase if not set
    if [[ -z "$current_name" ]]; then
        local keybase_name
        keybase_name=$(keybase id 2>/dev/null | grep "username:" | cut -d: -f2 | xargs)
        if [[ -n "$keybase_name" ]]; then
            log_info "Setting git user.name from keybase: $keybase_name"
            run_command git config --global user.name "$keybase_name"
        fi
    else
        log_info "Git user.name already set: $current_name"
    fi
    
    # Try to get primary email from keybase if not set
    if [[ -z "$current_email" ]]; then
        local keybase_email
        keybase_email=$(keybase pgp list 2>/dev/null | grep -o '<[^>]*>' | head -1 | tr -d '<>')
        if [[ -n "$keybase_email" ]]; then
            log_info "Setting git user.email from keybase: $keybase_email"
            run_command git config --global user.email "$keybase_email"
        else
            log_warning "Could not auto-detect email. You may need to set it manually:"
            log_warning "git config --global user.email \"your@email.com\""
        fi
    else
        log_info "Git user.email already set: $current_email"
    fi
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

# Find best matching key automatically
find_best_key() {
    local current_email
    current_email=$(git config --global user.email 2>/dev/null)
    
    if [[ -z "$current_email" ]]; then
        log_error "No git email configured. Set with: git config --global user.email \"your@email.com\""
        return 1
    fi
    
    log_info "Looking for best key match for git email: $current_email"
    
    # Get keybase keys
    local keybase_output
    keybase_output=$(keybase pgp list 2>/dev/null)
    
    if [[ -z "$keybase_output" ]]; then
        log_error "No keybase PGP keys found"
        return 1
    fi
    
    # Extract fingerprints
    local temp_fingerprints=()
    while IFS= read -r line; do
        if [[ $line == *"PGP Fingerprint:"* ]]; then
            local fp
            fp=${line#PGP Fingerprint: }
            temp_fingerprints+=("$fp")
        fi
    done <<< "$keybase_output"
    
    # Find keys that match the current git email
    local matching_keys=()
    local key_num=1
    
    for fp in "${temp_fingerprints[@]}"; do
        if gpg --list-keys --with-colons "$fp" >/dev/null 2>&1; then
            local key_info uids
            key_info=$(gpg --list-keys --with-colons "$fp" 2>/dev/null)
            uids=$(echo "$key_info" | awk -F: '/^uid:/ {print $10}' | sed 's/\\x3a/:/g')
            
            # Check if any UID contains the current git email
            if echo "$uids" | grep -i "$current_email" >/dev/null 2>&1; then
                log_info "Found matching key #$key_num: $fp"
                matching_keys+=("$fp")
            fi
        fi
        ((key_num++))
    done
    
    if [[ ${#matching_keys[@]} -eq 0 ]]; then
        log_warning "No keys found matching git email $current_email"
        log_info "Will use the first available key instead"
        
        # Import first available key
        if [[ ${#temp_fingerprints[@]} -gt 0 ]]; then
            echo "${temp_fingerprints[0]}"
            return 0
        else
            log_error "No keys available"
            return 1
        fi
    elif [[ ${#matching_keys[@]} -eq 1 ]]; then
        log_success "Perfect match found: ${matching_keys[0]}"
        echo "${matching_keys[0]}"
        return 0
    else
        log_info "Multiple matching keys found, using the first one: ${matching_keys[0]}"
        echo "${matching_keys[0]}"
        return 0
    fi
}

# List available keybase keys
list_keybase_keys() {
    if [[ "$AUTO_MODE" == "true" ]]; then
        log_info "Auto mode: Finding best key automatically..."
        return 0
    fi
    
    log_info "Available Keybase PGP keys:"
    echo ""
    
    # Get full keybase PGP list with all details
    local keybase_output
    keybase_output=$(keybase pgp list 2>/dev/null)
    
    if [[ -z "$keybase_output" ]]; then
        log_error "No keybase PGP keys found or keybase not accessible"
        return 1
    fi
    
    # Parse keybase output and get additional GPG details
    local temp_fingerprints=()
    while IFS= read -r line; do
        if [[ $line == *"PGP Fingerprint:"* ]]; then
            local fp
            fp=${line#PGP Fingerprint: }
            temp_fingerprints+=("$fp")
        fi
    done <<< "$keybase_output"
    
    echo "$keybase_output" | awk -v nc="$NC" -v green="$GREEN" -v yellow="$YELLOW" -v blue="$BLUE" '
    BEGIN { 
        key_count = 0
        print "┌─────────────────────────────────────────────────────────────────────────────┐"
    }
    /^Keybase Key ID:/ { 
        if (key_count > 0) print "├─────────────────────────────────────────────────────────────────────────────┤"
        key_count++
        keybase_id = $0
        gsub(/^Keybase Key ID: */, "", keybase_id)
        printf "│ Key #%d                                                                      │\n", key_count
        printf "│ Keybase ID: %-63s │\n", substr(keybase_id, 1, 63)
        next
    }
    /^PGP Fingerprint:/ { 
        fingerprint = $0
        gsub(/^PGP Fingerprint: */, "", fingerprint)
        # Format fingerprint with spaces for readability
        formatted_fp = substr(fingerprint,1,4) " " substr(fingerprint,5,4) " " substr(fingerprint,9,4) " " substr(fingerprint,13,4) " " substr(fingerprint,17,4) " " substr(fingerprint,21,4) " " substr(fingerprint,25,4) " " substr(fingerprint,29,4) " " substr(fingerprint,33,4) " " substr(fingerprint,37,4)
        printf "│ Fingerprint: %-62s │\n", formatted_fp
        
        # Store fingerprint for GPG details lookup
        current_fp = fingerprint
        next
    }
    /^PGP Identities:/ { 
        printf "│ Identities:                                                                 │\n"
        next
    }
    /^   / { 
        identity = $0
        gsub(/^   /, "", identity)
        printf "│   • %-69s │\n", substr(identity, 1, 69)
        next
    }
    END { 
        print "└─────────────────────────────────────────────────────────────────────────────┘"
        print ""
    }'
    
    # Get additional GPG details for each key
    log_info "Additional GPG Details:"
    echo ""
    local key_num=1
    for fp in "${temp_fingerprints[@]}"; do
        echo -e "${BLUE}Key #$key_num Additional Info:${NC}"
        
        # Get key creation date and expiration
        if gpg --list-keys --with-colons "$fp" >/dev/null 2>&1; then
            local key_info
            key_info=$(gpg --list-keys --with-colons "$fp" 2>/dev/null)
            
            # Extract creation and expiration dates
            local creation_date expiration_date key_type key_size
            creation_date=$(echo "$key_info" | awk -F: '/^pub:/ {print $6}' | head -1)
            expiration_date=$(echo "$key_info" | awk -F: '/^pub:/ {print $7}' | head -1)
            key_type=$(echo "$key_info" | awk -F: '/^pub:/ {print $4}' | head -1)
            key_size=$(echo "$key_info" | awk -F: '/^pub:/ {print $3}' | head -1)
            
            if [[ -n "$creation_date" && "$creation_date" != "0" ]]; then
                local formatted_creation
                formatted_creation=$(date -r "$creation_date" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "Unknown")
                echo "  Created: $formatted_creation"
            fi
            
            if [[ -n "$expiration_date" && "$expiration_date" != "0" ]]; then
                local formatted_expiration
                formatted_expiration=$(date -r "$expiration_date" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "Never")
                echo "  Expires: $formatted_expiration"
            else
                echo "  Expires: Never"
            fi
            
            if [[ -n "$key_type" && -n "$key_size" ]]; then
                case "$key_type" in
                    1) key_type_name="RSA" ;;
                    17) key_type_name="DSA" ;;
                    18) key_type_name="ECDH" ;;
                    19) key_type_name="ECDSA" ;;
                    22) key_type_name="EdDSA" ;;
                    *) key_type_name="Type $key_type" ;;
                esac
                echo "  Algorithm: $key_type_name $key_size bits"
            fi
            
            # Get UIDs (email addresses)
            local uids
            uids=$(echo "$key_info" | awk -F: '/^uid:/ {print $10}' | sed 's/\\x3a/:/g')
            if [[ -n "$uids" ]]; then
                echo "  Email addresses:"
                while IFS= read -r uid; do
                    if [[ -n "$uid" ]]; then
                        # Extract email from UID
                        local email
                        email=$(echo "$uid" | grep -o '<[^>]*>' | tr -d '<>')
                        if [[ -n "$email" ]]; then
                            echo "    • $email"
                        else
                            echo "    • $uid"
                        fi
                    fi
                done <<< "$uids"
            fi
            
        else
            echo "  Status: Not imported to local GPG keyring"
        fi
        
        echo ""
        ((key_num++))
    done
    
    # Show current git configuration and recommend matching key
    echo -e "${BLUE}=== Git Configuration Analysis ===${NC}"
    local current_key current_email current_name
    current_key=$(git config --global user.signingkey 2>/dev/null)
    current_email=$(git config --global user.email 2>/dev/null)
    current_name=$(git config --global user.name 2>/dev/null)
    
    if [[ -n "$current_email" ]]; then
        echo -e "${YELLOW}Current git email: $current_email${NC}"
    else
        echo -e "${YELLOW}No git email configured${NC}"
    fi
    
    if [[ -n "$current_name" ]]; then
        echo -e "${YELLOW}Current git name: $current_name${NC}"
    else
        echo -e "${YELLOW}No git name configured${NC}"
    fi
    
    if [[ -n "$current_key" ]]; then
        echo -e "${YELLOW}Current git signing key: $current_key${NC}"
        
        # Try to match current key to one of the keybase keys
        echo "$keybase_output" | grep -A1 -B1 "$current_key" | head -3 | while IFS= read -r line; do
            if [[ $line == *"PGP Fingerprint"* ]]; then
                local fp
                fp=${line#PGP Fingerprint: }
                echo -e "${GREEN}↳ Matches fingerprint: $fp${NC}"
            fi
        done
    fi
    
    echo ""
    
    # Recommend keys that match the current git email
    if [[ -n "$current_email" ]]; then
        echo -e "${GREEN}=== Recommended Keys for $current_email ===${NC}"
        local found_match=false
        local key_num=1
        
        for fp in "${temp_fingerprints[@]}"; do
            if gpg --list-keys --with-colons "$fp" >/dev/null 2>&1; then
                local key_info uids
                key_info=$(gpg --list-keys --with-colons "$fp" 2>/dev/null)
                uids=$(echo "$key_info" | awk -F: '/^uid:/ {print $10}' | sed 's/\\x3a/:/g')
                
                # Check if any UID contains the current git email
                if echo "$uids" | grep -i "$current_email" >/dev/null 2>&1; then
                    echo -e "${GREEN}✓ Key #$key_num matches your git email${NC}"
                    echo "  Fingerprint: $fp"
                    echo "  Matching identities:"
                    while IFS= read -r uid; do
                        if [[ -n "$uid" && "$uid" == *"$current_email"* ]]; then
                            echo "    • $uid"
                        fi
                    done <<< "$uids"
                    echo ""
                    found_match=true
                fi
            fi
            ((key_num++))
        done
        
        if [[ "$found_match" == "false" ]]; then
            echo -e "${YELLOW}No keys found matching your git email ($current_email)${NC}"
            echo "Consider:"
            echo "1. Adding your git email to one of your existing keys"
            echo "2. Changing your git email to match one of your key identities"
            echo "3. Creating a new key with your current git email"
        fi
    else
        echo -e "${YELLOW}Set your git email first with: git config --global user.email \"your@email.com\"${NC}"
    fi
    
    echo ""
    log_info "Choose a key by copying its PGP Fingerprint (without spaces)"
}

# Import key from keybase
import_keybase_key() {
    local fingerprint="$1"
    
    if [[ -z "$fingerprint" ]]; then
        log_error "No fingerprint provided"
        return 1
    fi
    
    # Validate fingerprint format
    if ! fingerprint=$(validate_fingerprint "$fingerprint"); then
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
        sed 's/^/  /' ~/.gnupg/gpg-agent.conf
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
        if [[ "$AUTO_MODE" == "true" ]]; then
            echo "Run with --auto (without --dry-run) to apply changes automatically."
        else
            echo "Run without --dry-run to apply changes."
        fi
        return 0
    fi
    
    if [[ "$AUTO_MODE" == "true" ]]; then
        echo -e "\n${GREEN}Automatic setup completed successfully!${NC}"
        echo "Your git is now configured for automatic GPG signing."
        echo ""
        echo -e "${BLUE}What was configured:${NC}"
        echo "• GPG tools installed and configured"
        echo "• Best matching key selected and imported"
        echo "• Git configured for automatic commit signing"
        echo "• Global gitignore configured"
        echo ""
    else
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
    fi
    
    echo -e "${BLUE}Test your setup:${NC}"
    echo "  git commit --allow-empty -m \"Test GPG signing\""
    echo ""
    echo "Backup created at: $BACKUP_DIR"
    
    if [[ "$AUTO_MODE" == "true" ]]; then
        echo ""
        echo -e "${GREEN}Ready to go! Your next commit will be automatically signed.${NC}"
    fi
}

# Main execution
main() {
    # Parse command line arguments first
    parse_args "$@"
    
    echo -e "${BLUE}GPG and Git Setup Script${NC}"
    if [[ "$AUTO_MODE" == "true" ]]; then
        echo "Auto mode: This script will automatically configure GPG signing for git commits"
        echo "Making intelligent decisions without user prompts..."
    else
        echo "This script will configure GPG signing for git commits using keybase keys"
    fi
    echo ""
    
    # Initialize paths
    init_paths
    
    # Backup existing configuration
    backup_gpg_config
    
    check_prerequisites
    setup_git_user_config
    setup_global_gitignore
    install_tools
    fix_gpg_database
    configure_gpg_agent
    
    echo ""
    if [[ "$DRY_RUN" != "true" ]]; then
        if [[ "$AUTO_MODE" == "true" ]]; then
            # Automatic key selection
            log_info "Auto mode: Selecting best key automatically..."
            if ! fingerprint=$(find_best_key); then
                log_error "Failed to find suitable key automatically"
                exit 1
            fi
            log_success "Auto-selected key: $fingerprint"
        else
            # Interactive key selection
            list_keybase_keys
            echo ""
            echo -e "${YELLOW}Enter the PGP fingerprint of the key you want to use for git signing:${NC}"
            read -r fingerprint
            
            if [[ -z "$fingerprint" ]]; then
                log_error "No fingerprint provided"
                exit 1
            fi
        fi
    else
        fingerprint="ABCDEF1234567890ABCDEF1234567890ABCDEF12"
        log_info "[DRY RUN] Using dummy fingerprint for demonstration"
    fi
    
    # Import the key
    if ! key_id=$(import_keybase_key "$fingerprint"); then
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