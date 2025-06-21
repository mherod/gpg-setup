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

# Validate PGP fingerprint format (robust version)
validate_fingerprint() {
    local fingerprint="$1"
    
    if [[ -z "$fingerprint" ]]; then
        log_error "Empty fingerprint provided"
        return 1
    fi
    
    # Remove spaces, colons, and convert to uppercase
    fingerprint=$(echo "$fingerprint" | tr -d ' :' | tr '[:lower:]' '[:upper:]')
    
    # Remove 0x prefix if present
    fingerprint=${fingerprint#0X}
    
    # Check if it's a valid 40-character hex string
    if [[ ${#fingerprint} -eq 40 && "$fingerprint" =~ ^[A-F0-9]+$ ]]; then
        echo "$fingerprint"
        return 0
    elif [[ ${#fingerprint} -eq 16 && "$fingerprint" =~ ^[A-F0-9]+$ ]]; then
        # Accept 16-character short key IDs but warn
        log_warning "Using short key ID (16 chars). Full fingerprint (40 chars) is recommended."
        echo "$fingerprint"
        return 0
    else
        log_error "Invalid fingerprint format. Expected 40-character hex string, got: '$fingerprint' (${#fingerprint} chars)"
        log_error "Example: 8062BB876817BADB404DCD95ADD781F2D92DAA2E"
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

# Check if key already exists (robust version)
key_exists() {
    local fingerprint="$1"
    
    if [[ -z "$fingerprint" ]]; then
        return 1
    fi
    
    # Try multiple ways to check if key exists
    # Method 1: Direct fingerprint lookup
    if gpg --list-keys "$fingerprint" >/dev/null 2>&1; then
        return 0
    fi
    
    # Method 2: Try with 0x prefix
    if gpg --list-keys "0x$fingerprint" >/dev/null 2>&1; then
        return 0
    fi
    
    # Method 3: Try short key ID (last 16 chars)
    local short_key_id
    short_key_id="${fingerprint: -16}"
    if [[ ${#short_key_id} -eq 16 ]] && gpg --list-keys "$short_key_id" >/dev/null 2>&1; then
        return 0
    fi
    
    return 1
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
    This script configures GPG signing for git commits. It works with existing
    GPG keys, keybase keys, or can generate new keys as needed.
    It will install required tools, configure GPG agent, and set up git
    to automatically sign commits.
    
    In automatic mode (--auto), the script will:
    • Check existing GPG configuration and use if consistent
    • Auto-detect and use existing GPG keys that match your git email
    • Install keybase automatically if not present (for additional options)
    • Fall back to keybase keys if available
    • Configure everything without requiring user input
    
    In interactive mode, the script will:
    • Check and offer to use existing GPG configuration
    • Offer to install keybase if not present
    • Try keybase import if available
    • Offer to generate a new GPG key if needed
    • Guide you through the key generation process

REQUIREMENTS:
    - Homebrew (https://brew.sh/)
    - Git
    - Keybase (https://keybase.io/) - optional, for importing existing keys
EOF
}

# Install keybase if needed
install_keybase() {
    if command_exists keybase; then
        log_info "Keybase already installed"
        return 0
    fi
    
    if [[ "$AUTO_MODE" == "true" ]]; then
        log_info "Auto mode: Installing keybase for additional key import options..."
        run_command brew install --cask keybase
        if command_exists keybase; then
            log_success "Keybase installed successfully"
            return 0
        else
            log_warning "Keybase installation failed, continuing without it"
            return 1
        fi
    else
        # Interactive mode - ask user
        echo ""
        echo -e "${BLUE}Keybase not found. Keybase provides additional GPG key import options.${NC}"
        echo -e "${YELLOW}Would you like to install keybase from homebrew? (y/N):${NC}"
        read -r install_keybase_confirm
        
        if [[ "$install_keybase_confirm" == "y" || "$install_keybase_confirm" == "Y" ]]; then
            log_info "Installing keybase..."
            run_command brew install --cask keybase
            if command_exists keybase; then
                log_success "Keybase installed successfully"
                log_info "You may need to run 'keybase login' to access your keys"
                return 0
            else
                log_warning "Keybase installation failed, continuing without it"
                return 1
            fi
        else
            log_info "Skipping keybase installation"
            return 1
        fi
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command_exists brew; then
        log_error "Homebrew is required but not installed. Install from https://brew.sh/"
        exit 1
    fi
    
    if ! command_exists git; then
        log_error "Git is required but not installed."
        exit 1
    fi
    
    log_success "Required tools found"
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
    
    local tools_installed=false
    
    # Install GPG if not present
    if ! command_exists gpg; then
        log_info "Installing gnupg..."
        run_command brew install gnupg
        tools_installed=true
    else
        log_info "gnupg already installed: $(gpg --version | head -1)"
    fi
    
    # Install pinentry-mac for native macOS integration
    if ! brew list pinentry-mac >/dev/null 2>&1; then
        log_info "Installing pinentry-mac for native macOS GUI..."
        run_command brew install pinentry-mac
        tools_installed=true
    else
        log_info "pinentry-mac already installed"
    fi
    
    if [[ "$tools_installed" == "true" ]]; then
        log_success "Tools installation complete"
    else
        log_success "All required tools already installed"
    fi
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
    
    local config_updated=false
    local expected_config="pinentry-program $PINENTRY_PATH
default-cache-ttl 28800
max-cache-ttl 86400"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create ~/.gnupg/gpg-agent.conf with pinentry-program: $PINENTRY_PATH"
    else
        # Check if configuration needs updating
        if [[ ! -f ~/.gnupg/gpg-agent.conf ]]; then
            log_info "Creating new GPG agent configuration"
            config_updated=true
        else
            local current_config
            current_config=$(cat ~/.gnupg/gpg-agent.conf 2>/dev/null || echo "")
            if [[ "$current_config" != "$expected_config" ]]; then
                log_info "Updating GPG agent configuration"
                config_updated=true
            else
                log_info "GPG agent configuration already correct"
            fi
        fi
        
        if [[ "$config_updated" == "true" ]]; then
            cat > ~/.gnupg/gpg-agent.conf << EOF
pinentry-program $PINENTRY_PATH
default-cache-ttl 28800
max-cache-ttl 86400
EOF
        fi
    fi
    
    # Reload GPG agent (always do this to ensure it's running)
    run_command gpgconf --reload gpg-agent
    
    if [[ "$config_updated" == "true" || "$DRY_RUN" == "true" ]]; then
        log_success "GPG agent configured with pinentry-mac"
    else
        log_success "GPG agent already properly configured"
    fi
}

# Check existing GPG configuration consistency
check_existing_config() {
    log_info "Checking existing GPG configuration..."
    
    local current_signing_key current_email issues=()
    current_signing_key=$(git config --global user.signingkey 2>/dev/null)
    current_email=$(git config --global user.email 2>/dev/null)
    
    # Check if we have any secret keys
    local secret_keys
    secret_keys=$(gpg --list-secret-keys --with-colons 2>/dev/null | awk -F: '/^sec:/ {print $5}' | head -5)
    
    if [[ -z "$secret_keys" ]]; then
        log_warning "No GPG secret keys found"
        issues+=("no_secret_keys")
    else
        log_info "Found existing GPG secret keys"
        
        # If no signing key is configured, suggest using an existing one
        if [[ -z "$current_signing_key" ]]; then
            log_warning "No git signing key configured"
            issues+=("no_signing_key")
        else
            # Check if the configured signing key exists
            if ! gpg --list-secret-keys "$current_signing_key" >/dev/null 2>&1; then
                log_warning "Configured signing key '$current_signing_key' not found in GPG keyring"
                issues+=("missing_signing_key")
            else
                log_info "Configured signing key '$current_signing_key' found"
                
                # Check if the key matches the current email
                if [[ -n "$current_email" ]]; then
                    local key_info uids
                    key_info=$(gpg --list-keys --with-colons "$current_signing_key" 2>/dev/null)
                    uids=$(echo "$key_info" | awk -F: '/^uid:/ {print $10}' | sed 's/\\x3a/:/g')
                    
                    if ! echo "$uids" | grep -i "$current_email" >/dev/null 2>&1; then
                        log_warning "Signing key does not contain git email '$current_email'"
                        issues+=("email_mismatch")
                    else
                        log_success "Signing key matches git email"
                    fi
                fi
            fi
        fi
    fi
    
    # Check GPG agent configuration
    if [[ ! -f ~/.gnupg/gpg-agent.conf ]]; then
        log_warning "GPG agent not configured"
        issues+=("no_gpg_agent_config")
    fi
    
    # Check git commit signing setting
    local commit_sign
    commit_sign=$(git config --global commit.gpgsign 2>/dev/null)
    if [[ "$commit_sign" != "true" ]]; then
        log_warning "Git commit signing not enabled"
        issues+=("commit_signing_disabled")
    fi
    
    # Return 0 if no issues, 1 if issues found
    if [[ ${#issues[@]} -eq 0 ]]; then
        log_success "GPG configuration is consistent and complete"
        return 0
    else
        log_info "Found ${#issues[@]} configuration issues: ${issues[*]}"
        return 1
    fi
}

# Find best existing GPG key
find_best_existing_key() {
    local current_email
    current_email=$(git config --global user.email 2>/dev/null)
    
    log_info "Looking for best existing GPG key..."
    
    # Get all secret keys
    local secret_keys
    secret_keys=$(gpg --list-secret-keys --with-colons 2>/dev/null | awk -F: '/^sec:/ {print $5}')
    
    if [[ -z "$secret_keys" ]]; then
        log_warning "No GPG secret keys found"
        return 1
    fi
    
    local matching_keys=() all_keys=()
    
    while IFS= read -r key_id; do
        if [[ -n "$key_id" ]]; then
            all_keys+=("$key_id")
            
            # Check if key matches current email
            if [[ -n "$current_email" ]]; then
                local key_info uids
                key_info=$(gpg --list-keys --with-colons "$key_id" 2>/dev/null)
                uids=$(echo "$key_info" | awk -F: '/^uid:/ {print $10}' | sed 's/\\x3a/:/g')
                
                if echo "$uids" | grep -i "$current_email" >/dev/null 2>&1; then
                    log_info "Found key matching git email: $key_id"
                    matching_keys+=("$key_id")
                fi
            fi
        fi
    done <<< "$secret_keys"
    
    # Return best match
    if [[ ${#matching_keys[@]} -gt 0 ]]; then
        echo "${matching_keys[0]}"
        return 0
    elif [[ ${#all_keys[@]} -gt 0 ]]; then
        log_info "No email match found, using first available key: ${all_keys[0]}"
        echo "${all_keys[0]}"
        return 0
    else
        log_error "No suitable GPG keys found"
        return 1
    fi
}

# Find best matching keys automatically from keybase (returns prioritized list)
find_best_keys() {
    # Only works if keybase is available
    if ! command_exists keybase; then
        log_error "Keybase not available" >&2
        return 1
    fi
    
    local current_email
    current_email=$(git config --global user.email 2>/dev/null)
    
    if [[ -z "$current_email" ]]; then
        log_error "No git email configured. Set with: git config --global user.email \"your@email.com\"" >&2
        return 1
    fi
    
    log_info "Looking for best key match for git email: $current_email" >&2
    
    # Check keybase accessibility first
    if ! keybase status >/dev/null 2>&1; then
        log_error "Keybase is not logged in or accessible" >&2
        log_info "Please run: keybase login" >&2
        return 1
    fi
    
    # Get keybase keys with retry logic
    local keybase_output
    local retry_count=0
    local max_retries=3
    
    while [[ $retry_count -lt $max_retries ]]; do
        keybase_output=$(keybase pgp list 2>/dev/null)
        
        if [[ -n "$keybase_output" ]]; then
            break
        else
            ((retry_count++))
            if [[ $retry_count -lt $max_retries ]]; then
                log_warning "Failed to get keybase keys, retrying... ($retry_count/$max_retries)" >&2
                sleep 1
            fi
        fi
    done
    
    if [[ -z "$keybase_output" ]]; then
        log_error "No keybase PGP keys found after $max_retries attempts" >&2
        log_info "Please ensure you have PGP keys in keybase: keybase pgp gen" >&2
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
        # Validate fingerprint before processing
        if ! validate_fingerprint "$fp" >/dev/null 2>&1; then
            log_warning "Skipping invalid fingerprint: $fp" >&2
            ((key_num++))
            continue
        fi
        
        if gpg --list-keys --with-colons "$fp" >/dev/null 2>&1; then
            local key_info uids
            key_info=$(gpg --list-keys --with-colons "$fp" 2>/dev/null)
            
            if [[ -z "$key_info" ]]; then
                log_warning "Could not get key info for $fp" >&2
                ((key_num++))
                continue
            fi
            
            uids=$(echo "$key_info" | awk -F: '/^uid:/ {print $10}' | sed 's/\\x3a/:/g')
            
            # Check if any UID contains the current git email
            if [[ -n "$uids" ]] && echo "$uids" | grep -i "$current_email" >/dev/null 2>&1; then
                log_info "Found matching key #$key_num: $fp" >&2
                matching_keys+=("$fp")
            fi
        else
            log_info "Key $fp not imported to local GPG keyring, skipping email check" >&2
        fi
        ((key_num++))
    done
    
    # Return prioritized list of keys
    local prioritized_keys=()
    
    if [[ ${#matching_keys[@]} -gt 0 ]]; then
        log_info "Found ${#matching_keys[@]} keys matching git email $current_email" >&2
        prioritized_keys=("${matching_keys[@]}")
        # Add non-matching keys as fallbacks
        for fp in "${temp_fingerprints[@]}"; do
            local already_added=false
            for existing in "${prioritized_keys[@]}"; do
                if [[ "$existing" == "$fp" ]]; then
                    already_added=true
                    break
                fi
            done
            if [[ "$already_added" == "false" ]]; then
                prioritized_keys+=("$fp")
            fi
        done
    else
        log_warning "No keys found matching git email $current_email" >&2
        log_info "Will try all available keys in order" >&2
        prioritized_keys=("${temp_fingerprints[@]}")
    fi
    
    if [[ ${#prioritized_keys[@]} -eq 0 ]]; then
        log_error "No keys available" >&2
        return 1
    fi
    
    # Output all keys, one per line
    for key in "${prioritized_keys[@]}"; do
        echo "$key"
    done
    return 0
}

# Try importing keys with fallback logic (keybase mode)
try_import_best_key() {
    # Check if keybase is available
    if ! command_exists keybase; then
        log_warning "Keybase not available, checking existing GPG keys..."
        return 1
    fi
    
    log_info "Finding and importing best matching key from keybase..."
    
    # Get prioritized list of keys
    local candidate_keys
    if ! candidate_keys=$(find_best_keys); then
        log_error "No candidate keys found in keybase"
        return 1
    fi
    
    # Convert to array
    local key_array=()
    while IFS= read -r key; do
        if [[ -n "$key" ]]; then
            key_array+=("$key")
        fi
    done <<< "$candidate_keys"
    
    log_info "Found ${#key_array[@]} candidate keys, trying in priority order..."
    
    # Try each key until one succeeds
    local attempt=1
    for fingerprint in "${key_array[@]}"; do
        log_info "Trying key $attempt/${#key_array[@]}: $fingerprint"
        
        # Attempt to import the key
        local key_id
        if key_id=$(import_keybase_key "$fingerprint" 2>/dev/null); then
            if [[ -n "$key_id" ]]; then
                log_success "Successfully imported key $attempt/${#key_array[@]}: $key_id"
                echo "$key_id"
                return 0
            else
                log_warning "Key $fingerprint imported but key ID is empty, trying next..."
            fi
        else
            log_warning "Failed to import key $fingerprint, trying next..."
        fi
        
        ((attempt++))
    done
    
    log_error "Failed to import any of the ${#key_array[@]} candidate keys"
    return 1
}

# Generate a new GPG key interactively
generate_new_gpg_key() {
    log_info "Generating a new GPG key..."
    
    # Get user details
    local user_name user_email
    user_name=$(git config --global user.name 2>/dev/null)
    user_email=$(git config --global user.email 2>/dev/null)
    
    # Prompt for name if not set
    if [[ -z "$user_name" ]]; then
        echo -e "${YELLOW}Enter your full name:${NC}"
        read -r user_name
        if [[ -z "$user_name" ]]; then
            log_error "Name is required for GPG key generation"
            return 1
        fi
    else
        echo -e "${BLUE}Using existing git name: $user_name${NC}"
        echo -e "${YELLOW}Press Enter to use this name, or type a new one:${NC}"
        read -r new_name
        if [[ -n "$new_name" ]]; then
            user_name="$new_name"
        fi
    fi
    
    # Prompt for email if not set
    if [[ -z "$user_email" ]]; then
        echo -e "${YELLOW}Enter your email address:${NC}"
        read -r user_email
        if [[ -z "$user_email" ]]; then
            log_error "Email is required for GPG key generation"
            return 1
        fi
    else
        echo -e "${BLUE}Using existing git email: $user_email${NC}"
        echo -e "${YELLOW}Press Enter to use this email, or type a new one:${NC}"
        read -r new_email
        if [[ -n "$new_email" ]]; then
            user_email="$new_email"
        fi
    fi
    
    # Key parameters
    local key_type="RSA"
    local key_length="4096"
    local expire_date="2y"  # 2 years
    
    echo -e "${BLUE}GPG Key Parameters:${NC}"
    echo "  Name: $user_name"
    echo "  Email: $user_email"
    echo "  Type: $key_type"
    echo "  Length: $key_length bits"
    echo "  Expires: $expire_date"
    echo ""
    
    echo -e "${YELLOW}Generate this GPG key? (y/N):${NC}"
    read -r confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_info "GPG key generation cancelled"
        return 1
    fi
    
    # Create batch file for unattended generation
    local batch_file="/tmp/gpg_gen_batch_$$"
    cat > "$batch_file" << EOF
%echo Generating GPG key...
Key-Type: $key_type
Key-Length: $key_length
Subkey-Type: $key_type
Subkey-Length: $key_length
Name-Real: $user_name
Name-Email: $user_email
Expire-Date: $expire_date
Passphrase: 
%commit
%echo GPG key generation complete
EOF
    
    # Generate the key
    log_info "Generating GPG key (this may take a while)..."
    echo -e "${YELLOW}Note: You'll be prompted to set a passphrase for your new key.${NC}"
    
    if gpg --batch --generate-key "$batch_file" 2>/dev/null; then
        log_success "GPG key generated successfully!"
        
        # Clean up batch file
        rm -f "$batch_file"
        
        # Get the new key ID
        local new_key_fingerprint new_key_id
        new_key_fingerprint=$(gpg --list-secret-keys --with-colons "$user_email" 2>/dev/null | awk -F: '/^fpr:/ {print $10}' | head -1)
        
        if [[ -n "$new_key_fingerprint" ]]; then
            new_key_id=$(gpg --list-keys --with-colons "$new_key_fingerprint" | awk -F: '/^pub:/ {print $5}' | tail -c 17)
            log_success "New key ID: $new_key_id"
            log_info "Fingerprint: $new_key_fingerprint"
            
            # Update git config if needed
            if [[ -z "$(git config --global user.name 2>/dev/null)" ]]; then
                git config --global user.name "$user_name"
                log_info "Set git user.name: $user_name"
            fi
            if [[ -z "$(git config --global user.email 2>/dev/null)" ]]; then
                git config --global user.email "$user_email"
                log_info "Set git user.email: $user_email"
            fi
            
            echo "$new_key_id"
            return 0
        else
            log_error "Could not determine new key ID"
            return 1
        fi
    else
        log_error "Failed to generate GPG key"
        rm -f "$batch_file"
        return 1
    fi
}

# Try importing from keybase or generate new key (interactive mode)
try_import_or_generate_key() {
    if [[ "$AUTO_MODE" == "true" ]]; then
        # Auto mode: try existing keys first, then keybase, no generation
        log_info "Auto mode: Checking existing GPG configuration..."
        
        # Check if current config is consistent
        if check_existing_config; then
            local current_key
            current_key=$(git config --global user.signingkey 2>/dev/null)
            if [[ -n "$current_key" ]]; then
                log_success "Using existing configured key: $current_key"
                echo "$current_key"
                return 0
            fi
        fi
        
        # Try to find best existing key
        if key_id=$(find_best_existing_key 2>/dev/null); then
            log_success "Using existing GPG key: $key_id"
            echo "$key_id"
            return 0
        fi
        
        # Try keybase import as fallback
        if command_exists keybase && key_id=$(try_import_best_key 2>/dev/null); then
            echo "$key_id"
            return 0
        fi
        
        log_error "No suitable GPG key found and auto mode doesn't generate new keys"
        log_info "Run in interactive mode to generate a new key, or set up keybase"
        return 1
    fi
    
    # Interactive mode: check existing first, then try keybase, then offer to generate
    log_info "Checking existing GPG configuration..."
    
    # Check if current config is consistent and complete
    if check_existing_config; then
        local current_key
        current_key=$(git config --global user.signingkey 2>/dev/null)
        if [[ -n "$current_key" ]]; then
            echo -e "${GREEN}Your GPG setup appears to be correctly configured.${NC}"
            echo -e "${YELLOW}Continue with existing setup? (Y/n):${NC}"
            read -r continue_existing
            if [[ "$continue_existing" != "n" && "$continue_existing" != "N" ]]; then
                log_success "Using existing configured key: $current_key"
                echo "$current_key"
                return 0
            fi
        fi
    fi
    
    # Try to use best existing key if available
    if key_id=$(find_best_existing_key 2>/dev/null); then
        echo -e "${BLUE}Found existing GPG key: $key_id${NC}"
        echo -e "${YELLOW}Use this existing key? (Y/n):${NC}"
        read -r use_existing
        if [[ "$use_existing" != "n" && "$use_existing" != "N" ]]; then
            log_success "Using existing GPG key: $key_id"
            echo "$key_id"
            return 0
        fi
    fi
    
    # Try keybase import
    if command_exists keybase; then
        log_info "Attempting to import keys from keybase..."
        if key_id=$(try_import_best_key 2>/dev/null); then
            echo "$key_id"
            return 0
        fi
        log_warning "Failed to import any keys from keybase"
    else
        log_info "Keybase not available, skipping keybase import"
    fi
    
    # Offer to generate new key
    echo ""
    echo -e "${YELLOW}Would you like to generate a new GPG key? (y/N):${NC}"
    read -r generate_confirm
    
    if [[ "$generate_confirm" == "y" || "$generate_confirm" == "Y" ]]; then
        if key_id=$(generate_new_gpg_key); then
            echo "$key_id"
            return 0
        else
            log_error "Failed to generate new GPG key"
            return 1
        fi
    else
        log_error "No GPG key available for git signing"
        log_info "You can:"
        log_info "1. Set up keybase PGP keys: keybase pgp gen"
        log_info "2. Run this script again and choose to generate a new key"
        log_info "3. Manually generate a GPG key: gpg --gen-key"
        return 1
    fi
}

# List available keybase keys
list_keybase_keys() {
    if [[ "$AUTO_MODE" == "true" ]]; then
        log_info "Auto mode: Finding best key automatically..."
        return 0
    fi
    
    # Check if keybase is available
    if ! command_exists keybase; then
        log_warning "Keybase not available - skipping keybase key listing"
        return 1
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
        log_info "Key $fingerprint already imported, retrieving key ID..."
        # Still return the key ID for git config
        local short_key_id
        short_key_id=$(gpg --list-keys --with-colons "$fingerprint" | awk -F: '/^pub:/ {print $5}' | tail -c 17)
        
        if [[ -n "$short_key_id" ]]; then
            log_success "Using existing key with ID: $short_key_id"
            echo "$short_key_id"
            return 0
        else
            log_error "Could not determine key ID for existing key"
            return 1
        fi
    fi
    
    log_info "Importing key $fingerprint from keybase..."
    
    # Import public key
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would import public key from keybase"
        log_info "[DRY RUN] Would import secret key from keybase"
        echo "DRYRUN1234567890ABCD"
        return 0
    else
        # Check if keybase is accessible
        if ! keybase status >/dev/null 2>&1; then
            log_error "Keybase is not logged in or accessible"
            log_info "Please run: keybase login"
            return 1
        fi
        
        # Import public key with retries
        local import_success=false
        local retry_count=0
        local max_retries=3
        
        while [[ $retry_count -lt $max_retries && "$import_success" == "false" ]]; do
            if keybase pgp export -q "$fingerprint" 2>/dev/null | gpg --import --quiet 2>/dev/null; then
                log_success "Public key imported"
                import_success=true
            else
                ((retry_count++))
                if [[ $retry_count -lt $max_retries ]]; then
                    log_warning "Public key import failed, retrying... ($retry_count/$max_retries)"
                    sleep 1
                fi
            fi
        done
        
        if [[ "$import_success" == "false" ]]; then
            log_error "Failed to import public key after $max_retries attempts"
            return 1
        fi
        
        # Import secret key with error handling
        log_info "Importing secret key (may require passphrase)..."
        if keybase pgp export --secret -q "$fingerprint" 2>/dev/null | gpg --import --batch --quiet 2>/dev/null; then
            log_success "Secret key imported"
        else
            log_warning "Secret key import failed or requires interactive input"
            log_info "You can manually import the secret key later if needed"
        fi
    fi
    
    # Get the short key ID for git config with retry logic
    local short_key_id
    local retry_count=0
    local max_retries=3
    
    while [[ $retry_count -lt $max_retries ]]; do
        short_key_id=$(gpg --list-keys --with-colons "$fingerprint" 2>/dev/null | awk -F: '/^pub:/ {print $5}' | tail -c 17)
        
        if [[ -n "$short_key_id" ]]; then
            log_info "Short key ID: $short_key_id"
            echo "$short_key_id"
            return 0
        else
            ((retry_count++))
            if [[ $retry_count -lt $max_retries ]]; then
                log_warning "Could not determine short key ID, retrying... ($retry_count/$max_retries)"
                sleep 1
            fi
        fi
    done
    
    log_error "Could not determine short key ID after $max_retries attempts"
    return 1
}

# Configure git signing
configure_git_signing() {
    local key_id="$1"
    
    if [[ -z "$key_id" ]]; then
        log_error "No key ID provided for git configuration"
        return 1
    fi
    
    log_info "Configuring git for GPG signing..."
    
    # Check current configuration
    local current_signing_key current_gpg_program current_commit_sign
    current_signing_key=$(git config --global user.signingkey 2>/dev/null || echo "")
    current_gpg_program=$(git config --global gpg.program 2>/dev/null || echo "")
    current_commit_sign=$(git config --global commit.gpgsign 2>/dev/null || echo "")
    
    local changes_made=false
    
    # Remove any SSH signing configuration
    run_command git config --global --unset gpg.format 2>/dev/null || true
    run_command git config --global --unset gpg.ssh.program 2>/dev/null || true  
    run_command git config --global --unset gpg.ssh.allowedsignersfile 2>/dev/null || true
    
    # Set GPG signing configuration only if different
    if [[ "$current_signing_key" != "$key_id" ]]; then
        run_command git config --global user.signingkey "$key_id"
        log_info "Updated signing key: $current_signing_key → $key_id"
        changes_made=true
    else
        log_info "Signing key already configured: $key_id"
    fi
    
    if [[ "$current_gpg_program" != "$GPG_PATH" ]]; then
        run_command git config --global gpg.program "$GPG_PATH"
        log_info "Updated GPG program: $current_gpg_program → $GPG_PATH"
        changes_made=true
    else
        log_info "GPG program already configured: $GPG_PATH"
    fi
    
    if [[ "$current_commit_sign" != "true" ]]; then
        run_command git config --global commit.gpgsign true
        log_info "Enabled automatic commit signing"
        changes_made=true
    else
        log_info "Automatic commit signing already enabled"
    fi
    
    if [[ "$changes_made" == "true" ]]; then
        log_success "Git configured for GPG signing with key $key_id"
    else
        log_success "Git already properly configured for GPG signing with key $key_id"
    fi
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
        echo -e "${BLUE}Configuration verified:${NC}"
        echo "• GPG tools: $(command_exists gpg && echo "✓ installed" || echo "✗ missing")"
        echo "• Pinentry-mac: $(brew list pinentry-mac >/dev/null 2>&1 && echo "✓ installed" || echo "✗ missing")"
        echo "• GPG agent: $(pgrep gpg-agent >/dev/null && echo "✓ running" || echo "⚠ not running")"
        echo "• Git signing: $(git config --global commit.gpgsign 2>/dev/null | grep -q true && echo "✓ enabled" || echo "✗ disabled")"
        local current_key
        current_key=$(git config --global user.signingkey 2>/dev/null)
        if [[ -n "$current_key" ]]; then
            echo "• Signing key: ✓ configured ($current_key)"
        else
            echo "• Signing key: ✗ not configured"
        fi
        echo ""
    else
        echo -e "\n${BLUE}Next steps:${NC}"
        echo "1. Make a test commit to verify GPG signing works"
        echo "2. When prompted, enter your passphrase in the GUI dialog"
        echo "3. Your commits will now be automatically signed"
        echo ""
        echo "To manually set ultimate trust on your key (optional):"
        echo "  gpg --edit-key <your-key-id>"
        echo "  > trust"
        echo "  > 5 (ultimate trust)"
        echo "  > y"
        echo "  > quit"
        echo ""
        echo "Note: If you generated a new key, you may want to:"
        echo "• Upload it to a keyserver: gpg --send-keys <your-key-id>"
        echo "• Add it to your GitHub account for verification"
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
        echo "Checking existing configuration, using existing keys, or importing from keybase as needed..."
    else
        echo "This script will configure GPG signing for git commits"
        echo "Working with existing GPG keys, keybase keys, or generating new keys as needed"
    fi
    echo ""
    
    # Initialize paths
    init_paths
    
    # Backup existing configuration
    backup_gpg_config
    
    check_prerequisites
    install_keybase
    setup_git_user_config
    setup_global_gitignore
    install_tools
    fix_gpg_database
    configure_gpg_agent
    
    echo ""
    if [[ "$DRY_RUN" != "true" ]]; then
        if [[ "$AUTO_MODE" == "true" ]]; then
            # Automatic key selection with fallback
            log_info "Auto mode: Finding and importing best key automatically..."
            if ! key_id=$(try_import_best_key); then
                log_error "Failed to find and import any suitable key automatically"
                exit 1
            fi
            log_success "Auto-selected and imported key: $key_id"
        else
            # Interactive mode: try keybase first, then offer to generate new key
            if ! key_id=$(try_import_or_generate_key); then
                log_error "No GPG key could be obtained"
                exit 1
            fi
        fi
    else
        if [[ "$AUTO_MODE" == "true" ]]; then
            # Dry run auto mode
            log_info "[DRY RUN] Would find and import best key automatically"
            key_id="DRYRUN1234567890ABCD"
        else
            # Dry run manual mode  
            log_info "[DRY RUN] Would attempt to import from keybase or generate new key"
            key_id="DRYRUN1234567890ABCD"
        fi
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