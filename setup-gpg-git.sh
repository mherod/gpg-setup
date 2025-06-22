#!/bin/bash

# GPG and Git Setup Script
# Fixes common macOS GPG integration issues and sets up proper git signing
# Based on troubleshooting session resolving keybase, GPG, and git integration

set -e

# Global variables
DRY_RUN=false
AUTO_MODE=false
NEW_KEY_MODE=false
SPECIFIED_KEY=""
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

# Validate environment compatibility
validate_environment() {
    log_info "Validating environment compatibility..."
    
    # Check operating system
    local os_name
    os_name=$(uname -s)
    
    if [[ "$os_name" != "Darwin" ]]; then
        log_error "Unsupported operating system: $os_name"
        log_error "This script is designed specifically for macOS (Darwin)"
        echo ""
        echo -e "${YELLOW}Supported environment:${NC}"
        echo "  • macOS (any version with Homebrew support)"
        echo ""
        echo -e "${YELLOW}Your system:${NC}"
        echo "  • OS: $os_name"
        echo "  • Architecture: $(uname -m)"
        echo ""
        echo -e "${BLUE}For other platforms, consider:${NC}"
        echo "  • Linux: Use your distribution's package manager for GPG setup"
        echo "  • Windows: Use GPG4Win or Windows Subsystem for Linux"
        echo ""
        return 1
    fi
    
    # Check macOS version (optional warning for very old versions)
    local macos_version
    if command_exists sw_vers; then
        macos_version=$(sw_vers -productVersion)
        log_success "macOS detected: $macos_version"
        
        # Extract major version (e.g., "13" from "13.2.1")
        local major_version
        major_version=$(echo "$macos_version" | cut -d. -f1)
        
        if [[ "$major_version" -lt 10 ]]; then
            log_warning "Very old macOS version detected ($macos_version)"
            log_warning "Some features may not work correctly on macOS < 10.x"
        fi
    else
        log_warning "Could not determine macOS version (sw_vers not available)"
    fi
    
    # Check for required system tools
    local missing_tools=()
    
    if ! command_exists uname; then
        missing_tools+=("uname")
    fi
    
    if ! command_exists curl; then
        missing_tools+=("curl")
    fi
    
    if ! command_exists git; then
        missing_tools+=("git")
    fi
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required system tools: ${missing_tools[*]}"
        log_error "Please install the missing tools and try again"
        return 1
    fi
    
    # Check architecture (informational)
    local arch
    arch=$(uname -m)
    case "$arch" in
        "x86_64")
            log_info "Architecture: Intel (x86_64)"
            ;;
        "arm64")
            log_info "Architecture: Apple Silicon (arm64)"
            ;;
        *)
            log_warning "Unknown architecture: $arch"
            log_warning "Script may work but hasn't been tested on this architecture"
            ;;
    esac
    
    log_success "Environment validation passed"
    return 0
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

# Get the newest GPG key for a given email address
get_newest_key_for_email() {
    local email="$1"
    
    if [[ -z "$email" ]]; then
        return 1
    fi
    
    # Get all keys for this email with creation timestamps and sort by newest
    local newest_key
    newest_key=$(gpg --list-secret-keys --with-colons --with-fingerprint "$email" 2>/dev/null | \
        awk -F: '
        /^sec:/ { 
            key_id = $5
            creation_time = $6
            if (creation_time != "" && creation_time != "0") {
                keys[creation_time] = key_id
            }
        }
        END {
            max_time = 0
            newest_key = ""
            for (time in keys) {
                if (time > max_time) {
                    max_time = time
                    newest_key = keys[time]
                }
            }
            if (newest_key != "") {
                print newest_key
            }
        }')
    
    if [[ -n "$newest_key" ]]; then
        # Convert key ID to full fingerprint
        local fingerprint
        fingerprint=$(gpg --list-secret-keys --with-colons --with-fingerprint "$newest_key" 2>/dev/null | awk -F: '/^fpr:/ {print $10}' | head -1)
        if [[ -n "$fingerprint" ]]; then
            echo "$fingerprint"
            return 0
        fi
    fi
    
    return 1
}

# Convert fingerprint to short key ID
fingerprint_to_key_id() {
    local fingerprint="$1"
    
    if [[ -z "$fingerprint" ]]; then
        return 1
    fi
    
    local key_id
    key_id=$(gpg --list-keys --with-colons "$fingerprint" 2>/dev/null | awk -F: '/^pub:/ {print $5}' | tail -c 17)
    
    if [[ -n "$key_id" ]]; then
        echo "$key_id"
        return 0
    else
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
            --new)
                NEW_KEY_MODE=true
                log_info "New key mode enabled - will always generate a fresh GPG key"
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
    --new        Always generate a new GPG key (skip existing key detection)
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
    • Install GitHub CLI and upload GPG key for commit verification
    • Upload generated keys to Keybase and GitHub for full integration
    • Fall back to keybase keys if available
    • Configure everything without requiring user input
    
    In interactive mode, the script will:
    • Check and offer to use existing GPG configuration
    • Offer to install keybase if not present
    • Offer to install GitHub CLI for automatic key upload
    • Try keybase import if available
    • Offer to generate a new GPG key if needed
    • Upload new keys to Keybase and GitHub
    • Guide you through the key generation process
    
    With --new flag, the script will:
    • Skip all existing key detection and configuration checks
    • Always generate a fresh GPG key with your git credentials
    • Set the new key as the default signing key
    • Upload to GitHub and Keybase if available
    • Provide a clean slate GPG setup

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

# Install GitHub CLI if needed
install_gh_cli() {
    if command_exists gh; then
        log_info "GitHub CLI already installed"
        return 0
    fi
    
    if [[ "$AUTO_MODE" == "true" ]]; then
        log_info "Auto mode: Installing GitHub CLI for GPG key upload..."
        run_command brew install gh
        if command_exists gh; then
            log_success "GitHub CLI installed successfully"
            return 0
        else
            log_warning "GitHub CLI installation failed, skipping GitHub integration"
            return 1
        fi
    else
        # Interactive mode - ask user
        echo ""
        echo -e "${BLUE}GitHub CLI not found. This enables automatic GPG key upload to GitHub.${NC}"
        echo -e "${YELLOW}Would you like to install GitHub CLI from homebrew? (y/N):${NC}"
        read -r install_gh_confirm
        
        if [[ "$install_gh_confirm" == "y" || "$install_gh_confirm" == "Y" ]]; then
            log_info "Installing GitHub CLI..."
            run_command brew install gh
            if command_exists gh; then
                log_success "GitHub CLI installed successfully"
                return 0
            else
                log_warning "GitHub CLI installation failed, skipping GitHub integration"
                return 1
            fi
        else
            log_info "Skipping GitHub CLI installation"
            return 1
        fi
    fi
}

# Check if user is authenticated with GitHub
check_gh_auth() {
    if ! command_exists gh; then
        return 1
    fi
    
    if gh auth status >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Upload GPG key to GitHub
upload_gpg_key_to_github() {
    local key_id="$1"
    
    if [[ -z "$key_id" ]]; then
        log_error "No key ID provided for GitHub upload"
        return 1
    fi
    
    # Check if GitHub CLI is available
    if ! command_exists gh; then
        log_warning "GitHub CLI not available, skipping GitHub key upload"
        return 1
    fi
    
    # Check authentication
    if ! check_gh_auth; then
        if [[ "$AUTO_MODE" == "true" ]]; then
            log_warning "Not authenticated with GitHub, skipping key upload"
            log_info "Run 'gh auth login' to enable automatic GitHub key upload"
            return 1
        else
            echo ""
            echo -e "${BLUE}GitHub authentication required for key upload.${NC}"
            echo -e "${YELLOW}Would you like to authenticate with GitHub now? (y/N):${NC}"
            read -r auth_confirm
            
            if [[ "$auth_confirm" == "y" || "$auth_confirm" == "Y" ]]; then
                log_info "Starting GitHub authentication..."
                if [[ "$DRY_RUN" == "true" ]]; then
                    log_info "[DRY RUN] Would run: gh auth login"
                    return 0
                else
                    gh auth login
                    if ! check_gh_auth; then
                        log_warning "GitHub authentication failed, skipping key upload"
                        return 1
                    fi
                fi
            else
                log_info "Skipping GitHub authentication and key upload"
                return 1
            fi
        fi
    fi
    
    log_info "Uploading GPG key to GitHub..."
    
    # Get the public key
    local public_key_file="/tmp/gpg_key_${key_id}.asc"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would export public key: gpg --armor --export $key_id"
        log_info "[DRY RUN] Would upload to GitHub: gh gpg-key add"
        log_success "GPG key would be uploaded to GitHub"
        return 0
    fi
    
    # Export the public key
    if ! gpg --armor --export "$key_id" > "$public_key_file" 2>/dev/null; then
        log_error "Failed to export public key for $key_id"
        rm -f "$public_key_file"
        return 1
    fi
    
    # Check if key already exists on GitHub
    local existing_keys
    existing_keys=$(gh gpg-key list 2>/dev/null | grep -o '[A-F0-9]\{16\}' || echo "")
    
    if echo "$existing_keys" | grep -q "$key_id"; then
        log_info "GPG key $key_id already exists on GitHub"
        rm -f "$public_key_file"
        return 0
    fi
    
    # Upload the key
    if gh gpg-key add "$public_key_file" >/dev/null 2>&1; then
        log_success "GPG key uploaded to GitHub successfully"
        log_info "Your commits will now show as 'Verified' on GitHub"
        rm -f "$public_key_file"
        return 0
    else
        log_warning "Failed to upload GPG key to GitHub"
        log_info "You can manually add it at: https://github.com/settings/gpg/new"
        rm -f "$public_key_file"
        return 1
    fi
}

# Upload GPG key to Keybase
upload_gpg_key_to_keybase() {
    local key_id="$1"
    
    if [[ -z "$key_id" ]]; then
        log_error "No key ID provided for Keybase upload"
        return 1
    fi
    
    # Check if keybase is available
    if ! command_exists keybase; then
        log_warning "Keybase not available, skipping Keybase key upload"
        return 1
    fi
    
    # Check if keybase is logged in
    if ! keybase status >/dev/null 2>&1; then
        if [[ "$AUTO_MODE" == "true" ]]; then
            log_warning "Not logged into Keybase, skipping key upload"
            log_info "Run 'keybase login' to enable automatic Keybase key upload"
            return 1
        else
            echo ""
            echo -e "${BLUE}Keybase login required for key upload.${NC}"
            echo -e "${YELLOW}Would you like to login to Keybase now? (y/N):${NC}"
            read -r keybase_login_confirm
            
            if [[ "$keybase_login_confirm" == "y" || "$keybase_login_confirm" == "Y" ]]; then
                log_info "Starting Keybase login..."
                if [[ "$DRY_RUN" == "true" ]]; then
                    log_info "[DRY RUN] Would run: keybase login"
                    return 0
                else
                    keybase login
                    if ! keybase status >/dev/null 2>&1; then
                        log_warning "Keybase login failed, skipping key upload"
                        return 1
                    fi
                fi
            else
                log_info "Skipping Keybase login and key upload"
                return 1
            fi
        fi
    fi
    
    log_info "Uploading GPG key to Keybase..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would select GPG key for Keybase: keybase pgp select $key_id"
        log_success "GPG key would be uploaded to Keybase"
        return 0
    fi
    
    # Check if key already exists in keybase
    local existing_keybase_keys
    existing_keybase_keys=$(keybase pgp list 2>/dev/null | grep -o '[A-F0-9]\{16\}' || echo "")
    
    if echo "$existing_keybase_keys" | grep -q "$key_id"; then
        log_info "GPG key $key_id already exists in Keybase"
        return 0
    fi
    
    # Upload the key to keybase using pgp select
    if keybase pgp select "$key_id" >/dev/null 2>&1; then
        log_success "GPG key uploaded to Keybase successfully"
        log_info "Your key is now available for Keybase PGP operations"
        return 0
    else
        log_warning "Failed to upload GPG key to Keybase"
        log_info "You can manually add it with: keybase pgp select $key_id"
        return 1
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
    
    log_info "Looking for best existing GPG key..." >&2
    
    # Validate GPG is working first
    if ! gpg --list-secret-keys >/dev/null 2>&1; then
        log_error "GPG is not functioning properly" >&2
        return 1
    fi
    
    # First try to get the newest key for the current email
    if [[ -n "$current_email" ]]; then
        local newest_fingerprint
        if newest_fingerprint=$(get_newest_key_for_email "$current_email"); then
            # Validate the fingerprint format
            if [[ ${#newest_fingerprint} -eq 40 && "$newest_fingerprint" =~ ^[A-F0-9]+$ ]]; then
                local newest_key_id
                if newest_key_id=$(fingerprint_to_key_id "$newest_fingerprint"); then
                    # Verify key is actually usable for signing
                    if gpg --list-secret-keys "$newest_key_id" >/dev/null 2>&1; then
                        log_info "Found newest key matching git email: $newest_key_id" >&2
                        echo "$newest_key_id"
                        return 0
                    else
                        log_warning "Key $newest_key_id exists but is not usable for signing" >&2
                    fi
                fi
            else
                log_warning "Invalid fingerprint format returned: $newest_fingerprint" >&2
            fi
        fi
    fi
    
    # Fallback: get all secret keys sorted by creation time
    local best_key
    best_key=$(gpg --list-secret-keys --with-colons 2>/dev/null | \
        awk -F: '
        /^sec:/ { 
            key_id = $5
            creation_time = $6
            # Only include keys with valid timestamps and key IDs
            if (creation_time != "" && creation_time != "0" && key_id != "" && length(key_id) >= 8) {
                keys[creation_time] = key_id
            }
        }
        END {
            max_time = 0
            newest_key = ""
            for (time in keys) {
                if (time > max_time) {
                    max_time = time
                    newest_key = keys[time]
                }
            }
            if (newest_key != "") {
                print newest_key
            }
        }')
    
    if [[ -n "$best_key" ]]; then
        # Verify the fallback key is actually usable
        if gpg --list-secret-keys "$best_key" >/dev/null 2>&1; then
            if [[ -n "$current_email" ]]; then
                log_info "No email match found, using newest available key: $best_key" >&2
            else
                log_info "No git email configured, using newest available key: $best_key" >&2
            fi
            echo "$best_key"
            return 0
        else
            log_error "Selected key $best_key is not usable" >&2
            return 1
        fi
    else
        log_error "No suitable GPG keys found" >&2
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
%no-protection
%commit
%echo GPG key generation complete
EOF
    
    # Generate the key
    log_info "Generating GPG key (this may take a while)..."
    echo -e "${YELLOW}Note: Key will be generated without passphrase protection for automation.${NC}"
    
    if gpg --batch --generate-key "$batch_file" 2>/dev/null; then
        log_success "GPG key generated successfully!"
        
        # Clean up batch file
        rm -f "$batch_file"
        
        # Get the newest key ID for this email
        local new_key_fingerprint new_key_id
        if new_key_fingerprint=$(get_newest_key_for_email "$user_email"); then
            if new_key_id=$(fingerprint_to_key_id "$new_key_fingerprint"); then
                log_success "New key ID: $new_key_id"
                log_info "Fingerprint: $new_key_fingerprint"
            else
                log_error "Could not determine key ID for generated key"
                return 1
            fi
        else
            log_error "Could not find the newly generated key"
            return 1
        fi
        
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

# Generate new GPG key mode - always creates a fresh key
generate_new_key_mode() {
    log_info "New key mode: Generating fresh GPG key..." >&2
    
    # Get git configuration for key generation
    local user_name user_email
    user_name=$(git config --global user.name 2>/dev/null)
    user_email=$(git config --global user.email 2>/dev/null)
    
    # Ensure we have name and email
    if [[ -z "$user_name" ]]; then
        if [[ "$AUTO_MODE" == "true" ]]; then
            log_error "Git user.name not configured. Set with: git config --global user.name \"Your Name\"" >&2
            return 1
        else
            echo -e "${YELLOW}Enter your full name:${NC}" >&2
            read -r user_name
            if [[ -z "$user_name" ]]; then
                log_error "Name is required for GPG key generation" >&2
                return 1
            fi
            # Set it for future use
            git config --global user.name "$user_name"
        fi
    fi
    
    if [[ -z "$user_email" ]]; then
        if [[ "$AUTO_MODE" == "true" ]]; then
            log_error "Git user.email not configured. Set with: git config --global user.email \"you@example.com\"" >&2
            return 1
        else
            echo -e "${YELLOW}Enter your email address:${NC}" >&2
            read -r user_email
            if [[ -z "$user_email" ]]; then
                log_error "Email is required for GPG key generation" >&2
                return 1
            fi
            # Set it for future use
            git config --global user.email "$user_email"
        fi
    fi
    
    log_info "Generating new GPG key for: $user_name <$user_email>" >&2
    
    if [[ "$AUTO_MODE" != "true" ]]; then
        echo "" >&2
        echo -e "${BLUE}This will create a new 4096-bit RSA GPG key with 2-year expiration.${NC}" >&2
        echo -e "${YELLOW}Continue with key generation? (Y/n):${NC}" >&2
        read -r confirm_generation
        if [[ "$confirm_generation" == "n" || "$confirm_generation" == "N" ]]; then
            log_info "Key generation cancelled" >&2
            return 1
        fi
    fi
    
    # Create batch file for unattended generation
    local batch_file="/tmp/gpg_gen_batch_new_$$"
    
    if [[ "$AUTO_MODE" == "true" ]]; then
        log_warning "Auto mode: Generating key without passphrase protection for automation. This is less secure!" >&2
        cat > "$batch_file" << EOF
%echo Generating new GPG key...
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: $user_name
Name-Email: $user_email
Expire-Date: 2y
%no-protection
%commit
%echo GPG key generation complete
EOF
    else
        # Interactive mode - use passphrase
        cat > "$batch_file" << EOF
%echo Generating new GPG key...
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: $user_name
Name-Email: $user_email
Expire-Date: 2y
%commit
%echo GPG key generation complete
EOF
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would generate new GPG key with batch file" >&2
        log_info "[DRY RUN] Key details: $user_name <$user_email>, RSA 4096-bit, 2y expiration" >&2
        if [[ "$AUTO_MODE" == "true" ]]; then
            log_info "[DRY RUN] Would use no passphrase protection (auto mode)" >&2
        else
            log_info "[DRY RUN] Would prompt for passphrase (interactive mode)" >&2
        fi
        rm -f "$batch_file"
        echo "DRYRUN1234567890ABCD"
        return 0
    fi
    
    # Generate the key
    log_info "Generating GPG key (this may take a while)..." >&2
    
    if gpg --batch --generate-key "$batch_file" 2>/dev/null; then
        log_success "New GPG key generated successfully!" >&2
        
        # Clean up batch file
        rm -f "$batch_file"
        
        # Get the newest key ID for this email
        # Sleep briefly to ensure timestamp difference
        sleep 1
        local new_key_fingerprint new_key_id
        if new_key_fingerprint=$(get_newest_key_for_email "$user_email"); then
            if new_key_id=$(fingerprint_to_key_id "$new_key_fingerprint"); then
                log_success "New key ID: $new_key_id" >&2
                log_info "Fingerprint: $new_key_fingerprint" >&2
                echo "$new_key_id"
                return 0
            else
                log_error "Could not determine key ID for generated key" >&2
                return 1
            fi
        else
            log_error "Could not find the newly generated key" >&2
            return 1
        fi
    else
        log_error "Failed to generate GPG key" >&2
        rm -f "$batch_file"
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
        log_error "No fingerprint provided" >&2
        return 1
    fi
    
    # Validate fingerprint format
    if ! fingerprint=$(validate_fingerprint "$fingerprint"); then
        return 1
    fi
    
    # Check if key already exists
    if key_exists "$fingerprint"; then
        log_info "Key $fingerprint already imported, retrieving key ID..." >&2
        # Still return the key ID for git config
        local short_key_id
        short_key_id=$(gpg --list-keys --with-colons "$fingerprint" | awk -F: '/^pub:/ {print $5}' | tail -c 17)
        
        if [[ -n "$short_key_id" ]]; then
            log_success "Using existing key with ID: $short_key_id" >&2
            echo "$short_key_id"
            return 0
        else
            log_error "Could not determine key ID for existing key" >&2
            return 1
        fi
    fi
    
    log_info "Importing key $fingerprint from keybase..." >&2
    
    # Import public key
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would import public key from keybase" >&2
        log_info "[DRY RUN] Would import secret key from keybase" >&2
        echo "DRYRUN1234567890ABCD"
        return 0
    else
        # Check if keybase is accessible
        if ! keybase status >/dev/null 2>&1; then
            log_error "Keybase is not logged in or accessible" >&2
            log_info "Please run: keybase login" >&2
            return 1
        fi
        
        # Import public key with retries
        local import_success=false
        local retry_count=0
        local max_retries=3
        
        while [[ $retry_count -lt $max_retries && "$import_success" == "false" ]]; do
            if keybase pgp export -q "$fingerprint" 2>/dev/null | gpg --import --quiet 2>/dev/null; then
                log_success "Public key imported" >&2
                import_success=true
            else
                ((retry_count++))
                if [[ $retry_count -lt $max_retries ]]; then
                    log_warning "Public key import failed, retrying... ($retry_count/$max_retries)" >&2
                    sleep 1
                fi
            fi
        done
        
        if [[ "$import_success" == "false" ]]; then
            log_error "Failed to import public key after $max_retries attempts" >&2
            return 1
        fi
        
        # Import secret key with error handling
        log_info "Importing secret key (may require passphrase)..." >&2
        if keybase pgp export --secret -q "$fingerprint" 2>/dev/null | gpg --import --batch --quiet 2>/dev/null; then
            log_success "Secret key imported" >&2
        else
            log_warning "Secret key import failed or requires interactive input" >&2
            log_info "You can manually import the secret key later if needed" >&2
        fi
    fi
    
    # Get the short key ID for git config with retry logic
    local short_key_id
    local retry_count=0
    local max_retries=3
    
    while [[ $retry_count -lt $max_retries ]]; do
        short_key_id=$(fingerprint_to_key_id "$fingerprint")
        
        if [[ -n "$short_key_id" ]]; then
            log_info "Short key ID: $short_key_id" >&2
            echo "$short_key_id"
            return 0
        else
            ((retry_count++))
            if [[ $retry_count -lt $max_retries ]]; then
                log_warning "Could not determine short key ID, retrying... ($retry_count/$max_retries)" >&2
                sleep 1
            fi
        fi
    done
    
    log_error "Could not determine short key ID after $max_retries attempts" >&2
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
        
        # Check GitHub integration
        if command_exists gh && check_gh_auth; then
            echo "• GitHub integration: ✓ authenticated"
        elif command_exists gh; then
            echo "• GitHub integration: ⚠ not authenticated"
        else
            echo "• GitHub integration: ✗ GitHub CLI not installed"
        fi
        
        # Check Keybase integration
        if command_exists keybase && keybase status >/dev/null 2>&1; then
            echo "• Keybase integration: ✓ logged in"
        elif command_exists keybase; then
            echo "• Keybase integration: ⚠ not logged in"
        else
            echo "• Keybase integration: ✗ not installed"
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
        if ! (command_exists gh && check_gh_auth); then
            echo "• Add it to your GitHub account for verification"
        fi
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
    
    # Validate environment compatibility early
    if ! validate_environment; then
        log_error "Environment validation failed. Cannot continue."
        exit 1
    fi
    echo ""
    
    echo -e "${BLUE}GPG and Git Setup Script${NC}"
    if [[ "$NEW_KEY_MODE" == "true" ]]; then
        echo "New key mode: This script will generate a fresh GPG key and configure git signing"
        echo "Skipping existing key detection and always creating a new key..."
    elif [[ "$AUTO_MODE" == "true" ]]; then
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
    install_gh_cli
    setup_git_user_config
    setup_global_gitignore
    install_tools
    fix_gpg_database
    configure_gpg_agent
    
    echo ""
    if [[ "$DRY_RUN" != "true" ]]; then
        if [[ "$NEW_KEY_MODE" == "true" ]]; then
            # New key mode: always generate a fresh key
            log_info "New key mode: Generating fresh GPG key..."
            if ! key_id=$(generate_new_key_mode); then
                log_error "Failed to generate new GPG key"
                exit 1
            fi
            log_success "Generated new GPG key: $key_id"
        elif [[ "$AUTO_MODE" == "true" ]]; then
            # Automatic key selection with fallback
            log_info "Auto mode: Finding best existing key or importing from keybase..."
            
            # First try existing keys
            if key_id=$(find_best_existing_key 2>/dev/null); then
                log_success "Auto-selected existing key: $key_id"
            # Fallback to keybase import
            elif command_exists keybase && key_id=$(try_import_best_key 2>/dev/null); then
                log_success "Auto-imported key from keybase: $key_id"
            else
                log_error "Failed to find any suitable key automatically"
                log_info "Try running in interactive mode or set up keybase"
                exit 1
            fi
        else
            # Interactive mode: try keybase first, then offer to generate new key
            if ! key_id=$(try_import_or_generate_key); then
                log_error "No GPG key could be obtained"
                exit 1
            fi
        fi
    else
        if [[ "$NEW_KEY_MODE" == "true" ]]; then
            # Dry run new key mode
            log_info "[DRY RUN] Would generate new GPG key"
            key_id="DRYRUN1234567890ABCD"
        elif [[ "$AUTO_MODE" == "true" ]]; then
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
    
    # Upload key to GitHub
    upload_gpg_key_to_github "$key_id"
    
    # Upload key to Keybase
    upload_gpg_key_to_keybase "$key_id"
    
    # Verify everything
    if [[ "$DRY_RUN" != "true" ]]; then
        verify_configuration
    fi
    
    # Show next steps
    show_next_steps
}

# Run main function
main "$@"