# GitHub Actions Workflows

This directory contains automated workflows for maintaining code quality and CI/CD.

## Workflows

### 🔍 [ShellCheck](.github/workflows/shellcheck.yml)
- **Trigger**: Push/PR to main/develop branches with shell script changes
- **Purpose**: Lint shell scripts using ShellCheck
- **Features**:
  - Uses both action-shellcheck and direct shellcheck
  - Multiple output formats (GCC, TTY, JSON)
  - Uploads detailed results as artifacts
  - Summary report with pass/fail status

### 🚀 [CI](.github/workflows/ci.yml)
- **Trigger**: Push/PR to main/develop branches
- **Purpose**: Comprehensive quality checks
- **Jobs**:
  - **Lint**: ShellCheck, syntax validation, permissions check, dry-run test
  - **Security**: Scans for hardcoded secrets, dangerous commands, error handling
  - **Documentation**: Checks for help text and README files

### 📊 [Badge Generator](.github/workflows/badge.yml)
- **Trigger**: Push/PR to main branch
- **Purpose**: Generate status badges for ShellCheck results
- **Output**: Status information for potential badge generation

## Usage

The workflows run automatically on:
- Push to `main` or `develop` branches
- Pull requests targeting `main` or `develop` branches
- Only when shell scripts (`.sh` files) are modified

## Local Testing

Before pushing, you can run the same checks locally:

```bash
# Install shellcheck
brew install shellcheck  # macOS
sudo apt-get install shellcheck  # Ubuntu

# Run shellcheck
shellcheck -S style setup-gpg-git.sh

# Check syntax
bash -n setup-gpg-git.sh

# Test help functionality
./setup-gpg-git.sh --help
./setup-gpg-git.sh --dry-run
```

## Artifacts

The ShellCheck workflow saves detailed analysis results as artifacts:
- `shellcheck-results/`: Contains analysis in multiple formats
- Retained for 30 days
- Available for download from the Actions tab

## Badge Integration

Add a ShellCheck status badge to your README:

```markdown
![ShellCheck](https://github.com/yourusername/yourrepo/workflows/ShellCheck/badge.svg)
```