# GPG and Git Setup Script

[![ShellCheck](https://github.com/mherod/gpg-setup/workflows/ShellCheck/badge.svg)](https://github.com/mherod/gpg-setup/actions/workflows/shellcheck.yml)
[![CI](https://github.com/mherod/gpg-setup/workflows/CI/badge.svg)](https://github.com/mherod/gpg-setup/actions/workflows/ci.yml)

A comprehensive, production-ready script that automates GPG and Git signing setup on macOS. Works with existing GPG keys, optionally imports from Keybase, or generates new keys with intelligent fallback logic.

## 🚀 Quick Install

```bash
# Download and run directly
curl -sSL https://raw.githubusercontent.com/mherod/gpg-setup/main/setup-gpg-git.sh | bash -s -- --auto

# Or clone and run
git clone https://github.com/mherod/gpg-setup.git
cd gpg-setup
chmod +x setup-gpg-git.sh
./setup-gpg-git.sh --auto
```

## ✨ Features

### **Core Functionality**
- ✅ **Automatic Mode** - Zero-config setup with intelligent existing key detection
- ✅ **New Key Mode** - Always generate fresh GPG key (skip existing detection)
- ✅ **Interactive Mode** - Guided setup with manual key selection
- ✅ **Existing Key Detection** - Uses your current GPG keys if properly configured
- ✅ **Auto Tool Install** - Installs keybase and GitHub CLI automatically in auto mode
- ✅ **GitHub Integration** - Automatically uploads GPG keys for commit verification
- ✅ **Keybase Integration** - Uploads generated keys to Keybase for PGP operations
- ✅ **Smart Fallback** - Keybase import → new key generation if needed
- ✅ **Multi-Key Support** - Tries multiple keys until one succeeds
- ✅ **Robust Error Handling** - Comprehensive retry logic and validation

### **System Integration**
- ✅ **Homebrew Detection** - Auto-detects Intel/Apple Silicon installations
- ✅ **Native macOS GUI** - Uses pinentry-mac for seamless password entry
- ✅ **Git Integration** - Configures automatic commit signing
- ✅ **Global Gitignore** - Sets up comprehensive exclusion patterns

### **Safety & Reliability**
- ✅ **Backup & Restore** - Automatic backup with timestamped directories
- ✅ **Atomic Operations** - All-or-nothing changes with automatic rollback
- ✅ **Input Validation** - Validates all fingerprints and configurations
- ✅ **Idempotent** - Safe to run multiple times
- ✅ **ShellCheck Compliant** - High code quality with automated CI
- ✅ **Modular Code** - Reusable helper functions eliminate code duplication
- ✅ **Security Warnings** - Clear alerts for passphrase-free key generation

## 📋 Requirements

### **System Requirements**
| Requirement | Details | Notes |
|-------------|---------|-------|
| **Operating System** | macOS (Darwin) | **Required** - Script validates OS and rejects non-macOS systems |
| **Architecture** | Intel (x86_64) or Apple Silicon (arm64) | Both supported |
| **macOS Version** | macOS 10.x or later | Older versions may have limited functionality |

### **Software Dependencies**
| Tool | Purpose | Installation |
|------|---------|-------------|
| **Homebrew** | Package manager | [brew.sh](https://brew.sh/) |
| **Git** | Version control | Usually pre-installed |
| **Keybase** *(optional)* | PGP key import/upload | [keybase.io](https://keybase.io/) |
| **GitHub CLI** *(optional)* | GPG key upload to GitHub | Auto-installed via homebrew |

> **Note**: The script includes comprehensive environment validation and will refuse to run on non-macOS systems. Keybase and GitHub CLI are optional - the script works with existing GPG keys and can generate new ones.

## 🎯 Quick Start

### **Automatic Mode** (Recommended)
```bash
# Fully automated setup - uses existing keys or finds best match
./setup-gpg-git.sh --auto

# Preview what auto mode would do
./setup-gpg-git.sh --auto --dry-run
```

### **New Key Mode** (Fresh Start)
```bash
# Always generate a new GPG key (skip existing key detection)
./setup-gpg-git.sh --new

# Combine with auto mode for zero-config new key generation
./setup-gpg-git.sh --new --auto

# Preview new key generation
./setup-gpg-git.sh --new --dry-run
```

### **Interactive Mode**
```bash
# Guided setup with manual key selection
./setup-gpg-git.sh

# Preview interactive mode
./setup-gpg-git.sh --dry-run
```

### **Get Help**
```bash
./setup-gpg-git.sh --help
```

## 🔄 How It Works

### **Automatic Mode Workflow**
1. **Environment Setup** - Detects Homebrew, installs tools, configures GPG agent
2. **Tool Installation** - Automatically installs keybase and GitHub CLI if not present
3. **Configuration Check** - Validates existing GPG setup and git configuration
4. **Smart Key Selection** - Uses existing keys or finds best match from Keybase
5. **Automated Import** - Tries keys in priority order until one succeeds
6. **Git Configuration** - Sets up automatic commit signing
7. **Platform Integration** - Uploads keys to GitHub and Keybase for full integration
8. **Verification** - Tests the complete setup

### **New Key Mode Workflow**
1. **Environment Setup** - Same as automatic mode
2. **Tool Installation** - Same as automatic mode
3. **Fresh Key Generation** - Always creates new 4096-bit RSA GPG key
4. **Security Configuration** - Auto mode uses no passphrase (with warning), interactive mode prompts for passphrase
5. **Git Configuration** - Sets up automatic commit signing with new key
6. **Platform Integration** - Uploads new key to GitHub and Keybase
7. **Verification** - Tests the complete setup

### **Interactive Mode Workflow**
1. **Environment Setup** - Same as automatic mode
2. **Tool Installation** - Offers to install keybase and GitHub CLI if not present
3. **Configuration Check** - Reviews existing setup and offers to use if valid
4. **Key Discovery** - Shows existing GPG keys and Keybase keys if available
5. **Smart Recommendations** - Highlights keys matching your git email
6. **Fallback Options** - Offers to generate new key if needed
7. **Manual Selection** - User chooses key or approves generation
8. **Platform Integration** - Uploads keys to GitHub and Keybase
9. **Configuration & Testing** - Same as automatic mode

### **Key Generation Process** (Interactive Mode Fallback)
1. **User Input** - Name and email (smart defaults from git config)
2. **Parameter Review** - Shows key type, size, expiration
3. **Secure Generation** - RSA 4096-bit with user-chosen passphrase
4. **Automatic Setup** - Immediately configures for git signing
5. **Usage Guidance** - Instructions for keyserver upload and GitHub

## 📊 Detailed Feature Breakdown

### **Intelligent Key Selection**
```bash
# Priority order for automatic mode:
1. Existing configured GPG key (if setup is consistent)
2. Existing GPG keys matching your git email (exact match)
3. Keybase keys matching your git email (case-insensitive)
4. All other available keys (fallback)
5. New key generation (interactive mode only)
```

### **Comprehensive Error Handling**
- **Missing Keybase**: Gracefully falls back to existing GPG keys
- **Configuration Issues**: Detects and fixes inconsistent setups
- **Import Failures**: Automatically tries next best key
- **Network Problems**: Graceful degradation with helpful messages
- **Partial Configurations**: Atomic rollback to previous state

### **Advanced Validation**
- **Configuration Consistency**: Checks GPG setup completeness and accuracy
- **Fingerprint Formats**: Supports 40-char and 16-char formats
- **Key Accessibility**: Verifies Keybase login status when available
- **Existing Keys**: Smart detection, validation, and reuse
- **Git Configuration**: Validates and updates existing settings

## 🛠️ Configuration Options

### **Command Line Arguments**
| Flag | Description | Use Case |
|------|-------------|----------|
| `--auto` | Fully automated mode | CI/CD, scripted setups |
| `--new` | Always generate new GPG key | Fresh start, clean setup |
| `--dry-run` | Preview mode (no changes) | Testing, validation |
| `--help` | Show detailed help | Learning, reference |

### **Flag Combinations**
- `--auto --new` - Zero-config new key generation
- `--new --dry-run` - Preview key generation process
- `--auto --dry-run` - Preview automatic setup

### **Generated GPG Key Specifications**
```bash
Key Type:        RSA
Key Size:        4096 bits
Subkey Type:     RSA  
Subkey Size:     4096 bits
Expiration:      2 years
Cipher:          AES256
Digest:          SHA512
Compression:     ZLIB

# Security Settings:
Auto Mode:       No passphrase (with security warning)
Interactive:     Prompts for passphrase protection
```

## 📁 File Locations

### **Backup Directories**
```bash
~/.gnupg_backup_YYYYMMDD_HHMMSS/  # Timestamped backups
```

### **Configuration Files**
```bash
~/.gnupg/gpg-agent.conf           # GPG agent configuration
~/.gitignore_global               # Global git exclusions
~/.gitconfig                      # Git signing configuration
```

### **Log Files**
All operations are logged to stdout with color-coded severity levels:
- 🔵 **INFO**: General information
- 🟢 **SUCCESS**: Successful operations
- 🟡 **WARNING**: Non-fatal issues
- 🔴 **ERROR**: Fatal problems

## 🔧 Advanced Usage

### **CI/CD Integration**
```bash
# Dockerfile example
RUN curl -sSL https://github.com/mherod/gpg-setup/raw/main/setup-gpg-git.sh | \
    bash -s -- --auto
```

### **Custom Git Configuration**
```bash
# The script configures these automatically:
git config --global commit.gpgsign true
git config --global user.signingkey YOUR_KEY_ID
git config --global gpg.program /opt/homebrew/bin/gpg
```

### **Manual Key Trust (Optional)**
```bash
# Set ultimate trust on your key:
gpg --edit-key YOUR_KEY_ID
> trust
> 5 (ultimate trust)
> y
> quit
```

## 🚨 Troubleshooting

### **Common Issues & Solutions**

#### **Keybase Not Available/Logged In**
```bash
# Solution (if you want to use Keybase):
keybase login
./setup-gpg-git.sh --auto

# Or just use existing GPG keys:
./setup-gpg-git.sh --auto
```

#### **GPG Agent Not Responding**
```bash
# Solution:
gpgconf --kill gpg-agent
gpgconf --launch gpg-agent
```

#### **Permission Denied Errors**
```bash
# Solution:
chmod 700 ~/.gnupg
chmod 600 ~/.gnupg/*
```

#### **Key Import Failures**
The script automatically handles this with fallback logic:
1. Uses existing properly configured GPG keys
2. Tries all available Keybase keys (if available)
3. Offers to generate new key (interactive mode)
4. Provides clear error messages and next steps

#### **New Key Generation Issues**
If `--new` mode seems to reuse existing keys:
```bash
# The script now properly generates unique keys each time
# Previous issue was fixed in v2.1+ with improved key lookup logic
./setup-gpg-git.sh --new --auto --dry-run  # Preview first
./setup-gpg-git.sh --new --auto             # Generate new key
```

#### **Unsupported Operating System**
The script includes environment validation and will refuse to run on non-macOS systems:
```bash
# Error on Linux/Windows:
[ERROR] Unsupported operating system: Linux
[ERROR] This script is designed specifically for macOS (Darwin)

Supported environment:
  • macOS (any version with Homebrew support)

Your system:
  • OS: Linux
  • Architecture: x86_64

For other platforms, consider:
  • Linux: Use your distribution's package manager for GPG setup
  • Windows: Use GPG4Win or Windows Subsystem for Linux
```

**Workaround**: Use `./setup-gpg-git.sh --help` to view documentation on any system.

#### **Security Considerations**
**Auto Mode Key Generation**:
- Uses no passphrase for automation compatibility
- Shows clear security warning: "Auto mode: Generating key without passphrase protection for automation. This is less secure!"
- Recommended for CI/CD environments only

**Interactive Mode Key Generation**:
- Prompts for passphrase protection (more secure)
- Recommended for personal development environments

### **Manual Recovery**
```bash
# Find your backup
ls -la ~/.gnupg_backup_*

# Restore from backup
rm -rf ~/.gnupg
cp -r ~/.gnupg_backup_YYYYMMDD_HHMMSS ~/.gnupg
chmod 700 ~/.gnupg

# Reset git configuration
git config --global --unset commit.gpgsign
git config --global --unset user.signingkey
git config --global --unset gpg.program
```

## 🧪 Testing Your Setup

### **Basic Verification**
```bash
# Test GPG signing
echo "test" | gpg --clearsign

# Test git commit signing
git commit --allow-empty -m "Test GPG signing"

# Verify signature
git log --show-signature -1
```

### **Integration with GitHub**
If the script didn't automatically upload your key:
1. **Export your public key**:
   ```bash
   gpg --armor --export YOUR_EMAIL@example.com
   ```
2. **Add to GitHub**: Settings → SSH and GPG keys → New GPG key
3. **Verify**: Your commits will show "Verified" badges

Or use the GitHub CLI:
```bash
gh auth login
gh gpg-key add <(gpg --armor --export YOUR_EMAIL@example.com)
```

## 📈 Status & Monitoring

### **GitHub Actions CI**
The project includes comprehensive CI/CD workflows for maintaining code quality:

#### **🔍 ShellCheck Workflow**
- **Trigger**: Push/PR to main/develop branches with shell script changes
- **Purpose**: Lint shell scripts using ShellCheck
- **Features**:
  - Uses both action-shellcheck and direct shellcheck
  - Multiple output formats (GCC, TTY, JSON)
  - Uploads detailed results as artifacts
  - Summary report with pass/fail status

#### **🚀 CI Workflow**
- **Trigger**: Push/PR to main/develop branches
- **Purpose**: Comprehensive quality checks
- **Jobs**:
  - **Lint**: ShellCheck, syntax validation, permissions check, dry-run test
  - **Security**: Scans for hardcoded secrets, dangerous commands, error handling
  - **Documentation**: Checks for help text and README files

#### **📊 Badge Generator**
- **Trigger**: Push/PR to main branch
- **Purpose**: Generate status badges for ShellCheck results
- **Output**: Status information for potential badge generation

### **Automated Triggers**
The workflows run automatically on:
- Push to `main` or `develop` branches
- Pull requests targeting `main` or `develop` branches  
- Only when shell scripts (`.sh` files) are modified

### **Artifacts & Reports**
The ShellCheck workflow saves detailed analysis results as artifacts:
- `shellcheck-results/`: Contains analysis in multiple formats
- Retained for 30 days
- Available for download from the Actions tab

### **Badge Status**
- [![ShellCheck](https://github.com/mherod/gpg-setup/workflows/ShellCheck/badge.svg)](https://github.com/mherod/gpg-setup/actions/workflows/shellcheck.yml) - Code quality and linting
- [![CI](https://github.com/mherod/gpg-setup/workflows/CI/badge.svg)](https://github.com/mherod/gpg-setup/actions/workflows/ci.yml) - Full test suite with security scanning
- [![Commits](https://img.shields.io/github/commit-activity/m/mherod/gpg-setup)](https://github.com/mherod/gpg-setup/commits/main) - Development activity

## 🤝 Contributing

### **Development Setup**
```bash
# Clone repository
git clone https://github.com/mherod/gpg-setup.git
cd gpg-setup

# Make executable
chmod +x setup-gpg-git.sh

# Run tests
shellcheck setup-gpg-git.sh
./setup-gpg-git.sh --dry-run
```

### **Local Testing**
Before pushing, you can run the same checks locally:

```bash
# Install shellcheck
brew install shellcheck  # macOS
sudo apt-get install shellcheck  # Ubuntu

# Run shellcheck with style checks
shellcheck -S style setup-gpg-git.sh

# Check syntax
bash -n setup-gpg-git.sh

# Test help functionality
./setup-gpg-git.sh --help
./setup-gpg-git.sh --dry-run

# Test both modes
./setup-gpg-git.sh --auto --dry-run
./setup-gpg-git.sh --dry-run
```

### **Code Quality**
- All code must pass ShellCheck with zero issues
- Follow existing code style and patterns
- Add comprehensive error handling
- Update documentation for new features
- Use reusable helper functions to eliminate code duplication
- Ensure proper output capture and stderr redirection

## 🙏 Acknowledgments

Built to solve common macOS GPG integration issues based on real-world troubleshooting experience. Designed for both individual developers and enterprise CI/CD environments.