#!/bin/bash
# =============================================================================
# FlagScale Dependency Installation
# =============================================================================
#
# Installs dependencies for FlagScale tasks.
# Supports conda, uv, and pip package managers.
#
# Usage:
#   ./install.sh --task TASK [--platform PLATFORM] [--dev] [--system]
#
# Examples:
#   ./install.sh --task train --platform cuda
#   ./install.sh --task train --pkg-mgr conda --env-name flagscale-train --env-path /opt/miniconda3
#   ./install.sh --task train --pkg-mgr uv --env-path /opt/venv
#   ./install.sh --task all --platform cuda --dev
#   ./install.sh --system-only --platform cuda
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils/utils.sh"
source "$SCRIPT_DIR/utils/pkg_utils.sh"
source "$SCRIPT_DIR/utils/retry_utils.sh"
source "$SCRIPT_DIR/utils/conda_utils.sh"

PROJECT_ROOT=$(get_project_root)

# =============================================================================
# Configuration
# =============================================================================
TASK=""
PLATFORM="cuda"
RETRY_COUNT=3
DEV_MODE=false
SYSTEM_MODE=false
SYSTEM_ONLY=false
PKG_MGR="uv"    # pip, uv, conda (default: uv)
ENV_NAME=""         # Environment name: conda env name (for conda only)
ENV_PATH=""         # Environment path: conda installation path (for conda) or venv path (for uv)

# PyPI index URLs (optional, for custom mirrors)
# These are exported as env vars for pip/uv to pick up automatically
INDEX_URL="${PIP_INDEX_URL:-}"
EXTRA_INDEX_URL="${PIP_EXTRA_INDEX_URL:-}"

# Get valid tasks from install scripts
get_valid_tasks() {
    local tasks=()
    if [ -d "$SCRIPT_DIR/$PLATFORM" ]; then
        for script in "$SCRIPT_DIR/$PLATFORM"/install_*.sh; do
            [ -f "$script" ] || continue
            local task=$(basename "$script" | sed 's/^install_//' | sed 's/\.sh$//')
            [ "$task" != "base" ] && tasks+=("$task")
        done
    fi
    tasks+=("all")
    echo "${tasks[@]}"
}

# =============================================================================
# Installation Functions
# =============================================================================
install_system_deps() {
    local system_script="$SCRIPT_DIR/install_system.sh"
    [ ! -f "$system_script" ] && { log_error "install_system.sh not found"; exit 1; }

    log_step "Installing system dependencies"
    local args=""
    [ "$DEV_MODE" = true ] && args="--dev"
    [ -n "$PLATFORM" ] && args="$args --platform $PLATFORM"
    [ -n "$PKG_MGR" ] && args="$args --pkg-mgr $PKG_MGR"
    "$system_script" $args
}

install_base_deps() {
    local base_script="$SCRIPT_DIR/$PLATFORM/install_base.sh"
    [ ! -f "$base_script" ] && { log_info "No base script for $PLATFORM"; return 0; }

    log_step "Installing base dependencies for $PLATFORM"
    "$base_script"
}

install_task_requirements() {
    local task=$1
    local req_file

    # Try dev file first if --dev flag set
    if [ "$DEV_MODE" = true ]; then
        req_file="$PROJECT_ROOT/requirements/$PLATFORM/${task}_dev.txt"
        [ ! -f "$req_file" ] && req_file="$PROJECT_ROOT/requirements/$PLATFORM/${task}.txt"
    else
        req_file="$PROJECT_ROOT/requirements/$PLATFORM/${task}.txt"
    fi

    [ ! -f "$req_file" ] && { log_info "No requirements for task: $task"; return 0; }

    log_step "Installing pip requirements: $task"
    retry_pip_install "$req_file" "$RETRY_COUNT"
}

install_task_source() {
    local task=$1
    local source_script="$SCRIPT_DIR/$PLATFORM/install_${task}.sh"

    [ ! -f "$source_script" ] && return 0

    log_step "Installing source dependencies: $task"
    "$source_script"
}

install_task() {
    local task=$1
    print_header "Installing: $task ($PLATFORM)"

    [ "$SYSTEM_MODE" = true ] && install_system_deps
    [ "$SYSTEM_ONLY" = true ] && { log_success "System-only complete"; return 0; }

    install_base_deps
    install_task_requirements "$task"
    install_task_source "$task"

    log_success "Task '$task' complete"
}

# =============================================================================
# Main
# =============================================================================
usage() {
    local tasks=($(get_valid_tasks))
    cat << EOF
Usage: $0 [OPTIONS]

OPTIONS:
    --task TASK            Task: ${tasks[*]}
    --platform NAME        Platform (default: cuda)
    --dev                  Include dev dependencies (build, lint, test)
    --system               Install system apt packages
    --system-only          Only install system packages (for Docker base)
    --pkg-mgr MGR          Package manager: pip, uv, conda (default: uv)
    --env-name NAME        Environment name: conda env name (for conda only)
    --env-path PATH        Environment path: venv path (for uv) or conda installation path (for conda)
    --index-url URL        PyPI index URL (for custom mirrors)
    --extra-index-url URL  Extra PyPI index URL
    --retry-count N        Retry attempts (default: 3)
    --help                 Show this help

PACKAGE MANAGERS:
    pip    - Use pip directly (standard Python)
    uv     - Use uv pip (fast, modern) [default]
    conda  - Use conda environment with pip for PyPI packages

EXAMPLES:
    $0 --task train --platform cuda
    $0 --task train --pkg-mgr uv --env-path /opt/venv
    $0 --task train --pkg-mgr conda --env-name flagscale-train --env-path /opt/miniconda3
    $0 --task all --platform cuda --dev
    $0 --system-only --platform cuda
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --task)            TASK="$2"; shift 2 ;;
            --platform)        PLATFORM="$2"; shift 2 ;;
            --dev)             DEV_MODE=true; shift ;;
            --system)          SYSTEM_MODE=true; shift ;;
            --system-only)     SYSTEM_ONLY=true; SYSTEM_MODE=true; shift ;;
            --pkg-mgr)         PKG_MGR="$2"; shift 2 ;;
            --env-name)        ENV_NAME="$2"; shift 2 ;;
            --env-path)        ENV_PATH="$2"; shift 2 ;;
            --index-url)       INDEX_URL="$2"; shift 2 ;;
            --extra-index-url) EXTRA_INDEX_URL="$2"; shift 2 ;;
            --retry-count)     RETRY_COUNT="$2"; shift 2 ;;
            --help|-h)         usage; exit 0 ;;
            *)                 log_error "Unknown option: $1"; usage; exit 1 ;;
        esac
    done
}

validate_inputs() {
    [ "$SYSTEM_ONLY" = true ] && return 0
    [ -z "$TASK" ] && { log_error "Task required (use --task)"; usage; exit 1; }

    local valid_tasks=($(get_valid_tasks))
    local valid=false
    for t in "${valid_tasks[@]}"; do
        [ "$TASK" = "$t" ] && valid=true && break
    done
    [ "$valid" = false ] && { log_error "Invalid task: $TASK. Valid: ${valid_tasks[*]}"; exit 1; }
}

setup_package_manager() {
    # Set package manager based on --package-manager option
    case "$PKG_MGR" in
        pip|uv|conda)
            set_pkg_manager "$PKG_MGR"
            ;;
        *)
            log_error "Invalid package manager: $PKG_MGR (use pip, uv, or conda)"
            exit 1
            ;;
    esac
}

setup_environment() {
    local manager=$(get_pkg_manager)
    log_info "Setting up environment for package manager: $manager"

    case "$manager" in
        conda)
            # ENV_NAME = conda environment name, ENV_PATH = conda installation path
            if [ -n "$ENV_NAME" ]; then
                log_step "Activating conda environment: $ENV_NAME"
                activate_conda "$ENV_NAME" "$ENV_PATH" || {
                    log_warn "Conda environment activation failed"
                    return 1
                }
            fi
            ;;
        uv)
            # ENV_PATH = venv path
            local venv_path="${ENV_PATH:-${UV_PROJECT_ENVIRONMENT:-/opt/venv}}"
            if [ -d "$venv_path" ]; then
                log_step "Activating uv environment: $venv_path"
                activate_uv_env "$venv_path" || {
                    log_warn "UV environment activation failed"
                    return 1
                }
            else
                log_info "UV venv not found at $venv_path, using system Python"
            fi
            ;;
        pip)
            # For pip, just ensure we have a working pip
            if ! has_pip; then
                log_warn "pip not found in PATH"
                return 1
            fi
            log_info "Using pip directly"
            ;;
    esac

    return 0
}

setup_index_urls() {
    # Export PyPI index URLs for pip/uv to pick up automatically
    if [ -n "$INDEX_URL" ]; then
        export PIP_INDEX_URL="$INDEX_URL"
        export UV_INDEX_URL="$INDEX_URL"
        log_info "Using index URL: $INDEX_URL"
    fi
    if [ -n "$EXTRA_INDEX_URL" ]; then
        export PIP_EXTRA_INDEX_URL="$EXTRA_INDEX_URL"
        export UV_EXTRA_INDEX_URL="$EXTRA_INDEX_URL"
        log_info "Using extra index URL: $EXTRA_INDEX_URL"
    fi
}

main() {
    parse_args "$@"
    validate_inputs

    print_header "FlagScale Installation"
    log_info "Task: ${TASK:-system-only}, Platform: $PLATFORM, Dev: $DEV_MODE"

    # Setup PyPI index URLs (before any pip/uv operations)
    setup_index_urls

    # Skip environment checks in system-only mode (Python may not be available)
    if [ "$SYSTEM_ONLY" != true ]; then
        # Setup package manager
        setup_package_manager

        # Setup environment based on package manager
        setup_environment || log_warn "Environment setup had issues"

        # Display environment info
        log_info "Environment: $(get_current_env)"
        log_info "Package manager: $(get_pkg_manager)"
        check_python_version || log_warn "Python version check failed"
    fi

    if [ "$TASK" = "all" ]; then
        local tasks=($(get_valid_tasks))
        for task in "${tasks[@]}"; do
            [ "$task" = "all" ] && continue
            install_task "$task"
        done
    else
        install_task "$TASK"
    fi

    print_header "Installation Complete"
}

main "$@"
