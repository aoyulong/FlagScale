#!/bin/bash
# =============================================================================
# Conda/UV Environment Utilities
# =============================================================================
#
# Provides environment management for both conda and uv.
# Supports conda for CI/CD compatibility and uv for modern workflows.
#
# Environment selection:
#   FLAGSCALE_ENV_MANAGER - Set to "conda", "uv", or "auto" (default: auto)
#
# Usage:
#   source conda_utils.sh
#   activate_env "env_name" [conda_path]   # For conda
#   activate_uv_env [venv_path]            # For uv
# =============================================================================

_CONDA_UTILS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_CONDA_UTILS_DIR/utils.sh"

# =============================================================================
# Environment Detection
# =============================================================================

# Check if running in uv environment
is_uv_env() {
    [ -n "${UV_PROJECT_ENVIRONMENT:-}" ] || \
    ([ -n "${VIRTUAL_ENV:-}" ] && [ -z "${CONDA_DEFAULT_ENV:-}" ])
}

# Check if running in conda environment
is_conda_active() {
    [ -n "${CONDA_DEFAULT_ENV:-}" ] && [ "${CONDA_DEFAULT_ENV}" != "base" ]
}

# Check if uv is available
has_uv() {
    command -v uv &> /dev/null
}

# Check if conda is available
has_conda() {
    command -v conda &> /dev/null
}

# Detect environment manager
detect_env_manager() {
    if [ -n "${FLAGSCALE_ENV_MANAGER:-}" ]; then
        echo "${FLAGSCALE_ENV_MANAGER}"
        return
    fi

    # Auto-detect based on environment
    if is_conda_active || has_conda; then
        echo "conda"
    elif is_uv_env || has_uv; then
        echo "uv"
    else
        echo "conda"  # Default fallback
    fi
}

# Get current environment name
get_current_env() {
    if [ -n "${CONDA_DEFAULT_ENV:-}" ]; then
        echo "$CONDA_DEFAULT_ENV"
    elif [ -n "${VIRTUAL_ENV:-}" ]; then
        basename "$VIRTUAL_ENV"
    else
        echo "base"
    fi
}

# =============================================================================
# UV Environment Activation
# =============================================================================

# Activate uv virtual environment
# Usage: activate_uv_env [venv_path]
activate_uv_env() {
    local venv_path=${1:-${UV_PROJECT_ENVIRONMENT:-"/opt/venv"}}

    # Check if venv exists
    if [ ! -d "$venv_path" ]; then
        log_warn "UV venv not found at $venv_path"

        # Try to create it if uv is available
        if has_uv; then
            log_info "Creating uv venv at $venv_path"
            uv venv "$venv_path"
        else
            log_error "Cannot create venv: uv not available"
            return 1
        fi
    fi

    # Activate the venv
    if [ -f "$venv_path/bin/activate" ]; then
        source "$venv_path/bin/activate"
        export UV_PROJECT_ENVIRONMENT="$venv_path"
        log_success "Activated uv environment: $venv_path"
        return 0
    else
        log_error "Invalid venv at $venv_path (no bin/activate)"
        return 1
    fi
}

# =============================================================================
# Conda Activation
# =============================================================================

# Activate conda environment with auto-detection
# Usage: activate_conda <env_name> [conda_path]
activate_conda() {
    local env_name=$1
    local conda_path=${2:-""}

    # Method 0: Use explicitly provided conda path
    if [ -n "$conda_path" ] && [ -f "$conda_path/bin/activate" ]; then
        log_info "Using provided conda path: $conda_path"
        source "$conda_path/bin/activate" "$env_name"
        if [ $? -eq 0 ]; then
            log_success "Activated conda environment: $env_name"
            return 0
        fi
    fi

    # Method 1: Check if conda is already in PATH
    if command -v conda &> /dev/null; then
        log_info "Found conda in PATH"
        eval "$(conda shell.bash hook)"
        conda activate "$env_name"
        if [ $? -eq 0 ]; then
            log_success "Activated conda environment: $env_name"
            return 0
        fi
    fi

    # Method 2: Search common conda locations
    local conda_paths=(
        "/opt/miniconda3"
        "/opt/conda"
        "/root/miniconda3"
        "/root/anaconda3"
        "$HOME/miniconda3"
        "$HOME/anaconda3"
        "/usr/local/miniconda3"
        "/usr/local/anaconda3"
    )

    for path in "${conda_paths[@]}"; do
        if [ -f "$path/bin/activate" ]; then
            log_info "Found conda at $path"
            source "$path/bin/activate" "$env_name"
            if [ $? -eq 0 ]; then
                log_success "Activated conda environment: $env_name"
                return 0
            fi
        fi
    done

    log_error "Failed to activate conda environment: $env_name"
    return 1
}

# =============================================================================
# Unified Environment Activation
# =============================================================================

# Activate environment (supports both conda and uv)
# Usage: activate_env <env_name_or_path> [conda_path] [--manager conda|uv|auto]
#
# The function auto-detects the environment manager based on:
#   1. FLAGSCALE_ENV_MANAGER environment variable
#   2. Whether UV_PROJECT_ENVIRONMENT is set
#   3. Whether conda is available
#
# Examples:
#   activate_env "flagscale-train"              # Activate conda env
#   activate_env "/opt/venv" "" --manager uv    # Activate uv venv
#   activate_env "myenv" "/opt/miniconda3"      # Conda with custom path
activate_env() {
    local env_name=$1
    local conda_path=${2:-""}
    local manager=""

    # Parse optional --manager argument
    shift 2 2>/dev/null || shift $# 2>/dev/null
    while [[ $# -gt 0 ]]; do
        case $1 in
            --manager) manager="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    # Determine manager if not specified
    if [ -z "$manager" ]; then
        manager=$(detect_env_manager)
    fi

    log_info "Environment manager: $manager"

    case "$manager" in
        uv)
            # For uv, env_name is the venv path
            local venv_path="${env_name:-${UV_PROJECT_ENVIRONMENT:-/opt/venv}}"
            if is_uv_env; then
                log_info "Using existing uv environment: ${UV_PROJECT_ENVIRONMENT:-$VIRTUAL_ENV}"
                return 0
            fi
            activate_uv_env "$venv_path"
            return $?
            ;;
        conda)
            # For conda, env_name is the environment name
            if [ -n "$env_name" ]; then
                activate_conda "$env_name" "$conda_path"
                return $?
            fi
            log_info "No conda environment specified"
            return 0
            ;;
        auto|*)
            # Auto mode: try uv first if configured, then conda
            if is_uv_env; then
                log_info "Using uv environment: ${UV_PROJECT_ENVIRONMENT:-$VIRTUAL_ENV}"
                return 0
            elif [ -n "$env_name" ] && has_conda; then
                activate_conda "$env_name" "$conda_path"
                return $?
            fi
            log_info "No environment activation needed"
            return 0
            ;;
    esac
}

# =============================================================================
# Legacy Functions (for backwards compatibility)
# =============================================================================

# Get current conda environment name
get_conda_env() {
    get_current_env
}

# Display environment info
display_env_info() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Environment Information"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if command -v python &> /dev/null; then
        echo "Python: $(which python)"
        echo "Version: $(python --version 2>&1)"
    else
        echo "Python: not found"
    fi

    local manager=$(detect_env_manager)
    echo "Env Manager: $manager"

    if [ -n "${CONDA_DEFAULT_ENV:-}" ]; then
        echo "Conda env: $CONDA_DEFAULT_ENV"
    fi

    if [ -n "${UV_PROJECT_ENVIRONMENT:-}" ]; then
        echo "UV venv: $UV_PROJECT_ENVIRONMENT"
    elif [ -n "${VIRTUAL_ENV:-}" ]; then
        echo "Virtual env: $VIRTUAL_ENV"
    fi

    if [ -z "${CONDA_DEFAULT_ENV:-}" ] && [ -z "${VIRTUAL_ENV:-}" ]; then
        echo "Environment: system"
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# =============================================================================
# Environment Setup Functions
# =============================================================================

# Setup environment based on manager type
# Usage: setup_env --manager <conda|uv> [--env-name NAME] [--conda-path PATH] [--uv-venv PATH]
setup_env() {
    local manager="auto"
    local env_name=""
    local conda_path=""
    local uv_venv=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --manager)     manager="$2"; shift 2 ;;
            --env-name)    env_name="$2"; shift 2 ;;
            --conda-path)  conda_path="$2"; shift 2 ;;
            --uv-venv)     uv_venv="$2"; shift 2 ;;
            *)             shift ;;
        esac
    done

    case "$manager" in
        uv)
            export FLAGSCALE_ENV_MANAGER="uv"
            if [ -n "$uv_venv" ]; then
                activate_uv_env "$uv_venv"
            elif [ -n "${UV_PROJECT_ENVIRONMENT:-}" ]; then
                activate_uv_env "${UV_PROJECT_ENVIRONMENT}"
            fi
            ;;
        conda)
            export FLAGSCALE_ENV_MANAGER="conda"
            if [ -n "$env_name" ]; then
                activate_conda "$env_name" "$conda_path"
            fi
            ;;
        auto|*)
            # Let activate_env handle auto-detection
            if [ -n "$env_name" ] || [ -n "$uv_venv" ]; then
                activate_env "${env_name:-$uv_venv}" "$conda_path"
            fi
            ;;
    esac
}
