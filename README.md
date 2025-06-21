# GPG and Git Setup Script

Automates GPG and Git signing setup on macOS using Keybase keys.

## Features

- ✅ Auto-detects Homebrew installation (Intel/Apple Silicon)
- ✅ Validates PGP fingerprint format
- ✅ Backs up existing GPG configuration
- ✅ Checks for duplicate keys before import
- ✅ Dry-run mode for safe testing
- ✅ Automatic rollback on errors
- ✅ Native macOS PIN entry integration

## Requirements

- **Homebrew** - [Install from brew.sh](https://brew.sh/)
- **Keybase** - [Install from keybase.io](https://keybase.io/)
- **Git** - Usually pre-installed on macOS

## Usage

```bash
# Test what the script would do (recommended first run)
./setup-gpg-git.sh --dry-run

# Run the actual setup
./setup-gpg-git.sh

# Show help
./setup-gpg-git.sh --help
```

## What It Does

1. **Prerequisites Check** - Verifies required tools are installed
2. **Path Detection** - Auto-detects Homebrew paths for your system
3. **Backup Creation** - Backs up existing GPG configuration
4. **Tool Installation** - Installs GPG and pinentry-mac via Homebrew
5. **GPG Database Fix** - Repairs any corrupted GPG databases
6. **Agent Configuration** - Sets up native macOS PIN entry
7. **Key Import** - Imports your selected Keybase PGP key
8. **Git Configuration** - Configures Git for automatic commit signing

## Safety Features

- **Backup & Restore** - Automatic backup with timestamped directory
- **Error Rollback** - Reverts changes if setup fails
- **Duplicate Detection** - Skips import if key already exists
- **Input Validation** - Validates fingerprint format before import

## Post-Setup

After successful setup:
1. Make a test commit to verify GPG signing works
2. Enter your Keybase passphrase when prompted
3. All future commits will be automatically signed

## Troubleshooting

If setup fails, the script automatically rolls back changes and restores your backup from `~/.gnupg_backup_*`.

To manually restore:
```bash
# Find your backup
ls -la ~/.gnupg_backup_*

# Restore manually if needed
rm -rf ~/.gnupg
cp -r ~/.gnupg_backup_YYYYMMDD_HHMMSS ~/.gnupg
chmod 700 ~/.gnupg
```