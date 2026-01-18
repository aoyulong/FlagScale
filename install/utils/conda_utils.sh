#!/bin/bash
# Conda environment management utilities

# Source utils for logging
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Create a new conda environment
# Usage: create_conda_env <env_name> [python_version]
create_conda_env() {
    local env_name=$1
    local python_version=${2:-3.12}

    if ! command_exists conda; then
        log_error "Conda not found in PATH"
        return 1
    fi

    # Check if environment already exists
    if conda env list | grep -q "^${env_name} "; then
        log_info "Conda environment '$env_name' already exists"
        return 0
    fi

    log_step "Creating conda environment: $env_name (Python $python_version)"
    if conda create -n "$env_name" python="$python_version" -y; then
        log_success "Conda environment '$env_name' created successfully"
        return 0
    else
        log_error "Failed to create conda environment '$env_name'"
        return 1
    fi
}

# Activate a conda environment
# Usage: activate_conda_env <env_name>
activate_conda_env() {
    local env_name=$1

    if ! command_exists conda; then
        log_error "Conda not found in PATH"
        return 1
    fi

    # Get conda base directory
    local conda_base=$(conda info --base)

    if [ ! -f "$conda_base/bin/activate" ]; then
        log_error "Conda activate script not found at $conda_base/bin/activate"
        return 1
    fi

    log_step "Activating conda environment: $env_name"
    source "$conda_base/bin/activate" "$env_name"

    if [ $? -eq 0 ]; then
        log_success "Conda environment '$env_name' activated"
        log_info "Current environment: $(get_conda_env)"
        return 0
    else
        log_error "Failed to activate conda environment '$env_name'"
        return 1
    fi
}

# Check if a conda environment exists
# Usage: conda_env_exists <env_name>
conda_env_exists() {
    local env_name=$1

    if ! command_exists conda; then
        return 1
    fi

    if conda env list | grep -q "^${env_name} "; then
        return 0
    else
        return 1
    fi
}

# List all conda environments
list_conda_envs() {
    if ! command_exists conda; then
        log_error "Conda not found in PATH"
        return 1
    fi

    log_info "Available conda environments:"
    conda env list
}
