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
- ✅ **Interactive Mode** - Guided setup with manual key selection
- ✅ **Existing Key Detection** - Uses your current GPG keys if properly configured
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

## 📋 Requirements

| Tool | Purpose | Installation |
|------|---------|-------------|
| **Homebrew** | Package manager | [brew.sh](https://brew.sh/) |
| **Git** | Version control | Usually pre-installed |
| **Keybase** *(optional)* | PGP key import | [keybase.io](https://keybase.io/) |

> **Note**: Keybase is completely optional - the script works with existing GPG keys and can generate new ones if needed.

## 🎯 Quick Start

### **Automatic Mode** (Recommended)
```bash
# Fully automated setup - uses existing keys or finds best match
./setup-gpg-git.sh --auto

# Preview what auto mode would do
./setup-gpg-git.sh --auto --dry-run
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
2. **Configuration Check** - Validates existing GPG setup and git configuration
3. **Smart Key Selection** - Uses existing keys or finds best match from Keybase
4. **Automated Import** - Tries keys in priority order until one succeeds
5. **Git Configuration** - Sets up automatic commit signing
6. **Verification** - Tests the complete setup

### **Interactive Mode Workflow**
1. **Environment Setup** - Same as automatic mode
2. **Configuration Check** - Reviews existing setup and offers to use if valid
3. **Key Discovery** - Shows existing GPG keys and Keybase keys if available
4. **Smart Recommendations** - Highlights keys matching your git email
5. **Fallback Options** - Offers to generate new key if needed
6. **Manual Selection** - User chooses key or approves generation
7. **Configuration & Testing** - Same as automatic mode

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
| `--dry-run` | Preview mode (no changes) | Testing, validation |
| `--help` | Show detailed help | Learning, reference |

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
1. **Export your public key**:
   ```bash
   gpg --armor --export YOUR_EMAIL@example.com
   ```
2. **Add to GitHub**: Settings → SSH and GPG keys → New GPG key
3. **Verify**: Your commits will show "Verified" badges

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

## 🙏 Acknowledgments

Built to solve common macOS GPG integration issues based on real-world troubleshooting experience. Designed for both individual developers and enterprise CI/CD environments.