#!/bin/bash
# Retry utilities for network-dependent operations
# Extracted from .github/workflows/scripts/retry_functions.sh

# Source utils for logging functions and package manager
_RETRY_UTILS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_RETRY_UTILS_DIR/utils.sh"
source "$_RETRY_UTILS_DIR/pkg_utils.sh"

# Retry a single command with a specified number of attempts
# Usage: retry <retry_count> <command>
retry() {
    local retries=$1
    shift
    local cmd="$*"
    local count=0

    until eval "$cmd"; do
        count=$((count + 1))
        if [ $count -ge $retries ]; then
            log_error "Command failed after $retries retries: $cmd"
            return 1
        fi
        log_warn "Command failed (attempt $count/$retries), retrying in 5 seconds..."
        sleep 5
    done

    if [ $count -gt 0 ]; then
        log_success "Command succeeded after $count retries: $cmd"
    fi
    return 0
}

# Retry a batch of commands sequentially
# Usage: retry_commands <retry_count> <command1> <command2> ...
retry_commands() {
    local retries=$1
    shift
    local -a cmds=("$@")

    log_info "Retry config: max retries = $retries"
    log_info "Total commands to execute: ${#cmds[@]}"

    for cmd in "${cmds[@]}"; do
        log_info "Executing command: $cmd"
        retry $retries "$cmd"
        local cmd_exit_code=$?
        if [ $cmd_exit_code -ne 0 ]; then
            log_error "Batch commands failed at: $cmd"
            return $cmd_exit_code
        fi
    done

    log_success "All batch commands executed successfully!"
    return 0
}

# Retry pip/uv/conda install with a requirements file
# Usage: retry_pip_install <requirements_file> [retry_count]
# Note: Uses pkg_utils.sh to support pip, uv, and conda package managers
retry_pip_install() {
    local requirements_file=$1
    local retries=${2:-3}

    if [ ! -f "$requirements_file" ]; then
        log_error "Requirements file not found: $requirements_file"
        return 1
    fi

    local manager=$(get_pkg_manager)
    log_info "Installing from $requirements_file with $retries retries (using $manager)"

    case "$manager" in
        uv)
            retry $retries "uv pip install -r '$requirements_file'"
            ;;
        conda)
            # In conda environments, use pip for requirements files
            retry $retries "pip install -r '$requirements_file'"
            ;;
        pip|*)
            retry $retries "pip install -r '$requirements_file'"
            ;;
    esac
}

# Retry package install (supports pip, uv, and conda)
# Usage: retry_pkg_install <retry_count> <install_args...>
retry_pkg_install() {
    local retries=$1
    shift
    local install_args="$*"

    local manager=$(get_pkg_manager)
    log_info "Installing packages with $retries retries (using $manager)"

    case "$manager" in
        uv)
            retry $retries "uv pip install $install_args"
            ;;
        conda)
            # In conda environments, use pip for PyPI packages
            retry $retries "pip install $install_args"
            ;;
        pip|*)
            retry $retries "pip install $install_args"
            ;;
    esac
}

# Retry conda install (only for conda-specific packages)
# Usage: retry_conda_install <retry_count> <packages...>
retry_conda_install() {
    local retries=$1
    shift
    local packages="$*"

    if ! command -v conda &> /dev/null; then
        log_error "Conda not available"
        return 1
    fi

    log_info "Installing conda packages with $retries retries"
    retry $retries "conda install -y $packages"
}

# Retry git clone operation
# Usage: retry_git_clone <repo_url> <target_dir> [retry_count]
retry_git_clone() {
    local repo_url=$1
    local target_dir=$2
    local retries=${3:-3}

    log_info "Cloning $repo_url to $target_dir with $retries retries"
    retry $retries "rm -rf '$target_dir' && git clone '$repo_url' '$target_dir'"
}
