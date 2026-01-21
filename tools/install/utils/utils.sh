#!/bin/bash
# Common utility functions for install scripts

# Logging functions with emojis for better visibility
log_info() {
    echo "🔍 [INFO] $*"
}

log_warn() {
    echo "⚠️  [WARN] $*" >&2
}

log_error() {
    echo "❌ [ERROR] $*" >&2
}

log_success() {
    echo "✅ [SUCCESS] $*"
}

log_step() {
    echo "🔧 [STEP] $*"
}

# Get the project root directory
get_project_root() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    cd "$script_dir/../../.."
    pwd
}

# Check if Python version meets minimum requirement
# Usage: check_python_version [min_version]
check_python_version() {
    local min_version=${1:-"3.10"}

    if ! command -v python &> /dev/null; then
        log_error "Python not found in PATH"
        return 1
    fi

    local python_version=$(python --version 2>&1 | awk '{print $2}')
    log_info "Found Python version: $python_version"

    # Simple version check - checks if version starts with 3.1x where x >= 0
    if ! python --version 2>&1 | grep -qE "Python 3\.([1-9][0-9]|1[0-9])"; then
        log_error "Python $min_version+ required, found $python_version"
        return 1
    fi

    log_success "Python version check passed"
    return 0
}

# Check if we're in a conda environment
is_conda_env() {
    if [ -n "$CONDA_DEFAULT_ENV" ]; then
        return 0
    else
        return 1
    fi
}

# Get current conda environment name
get_conda_env() {
    if is_conda_env; then
        echo "$CONDA_DEFAULT_ENV"
    else
        echo "none"
    fi
}

# Check if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Print a separator line for better output formatting
print_separator() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Print a section header
print_header() {
    echo ""
    print_separator
    echo "  $*"
    print_separator
    echo ""
}
