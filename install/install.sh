#!/bin/bash
# Master installation orchestrator script
# Delegates to task-specific install scripts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils/utils.sh"

# Get project root
PROJECT_ROOT=$(get_project_root)

# Default values
TASK=""
PLATFORM="cuda"  # Default to CUDA platform
ENV_NAME=""
SKIP_BASE="false"
SKIP_MEGATRON="false"
SKIP_CONDA_CREATE="false"
RETRY_COUNT="3"

# Valid tasks and platforms
VALID_TASKS=("train" "hetero_train" "inference" "rl" "all")
VALID_PLATFORMS=("cuda" "cpu")

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Master installation script for FlagScale dependencies.

OPTIONS:
    --task TASK              Task type: train, hetero_train, inference, rl, all (required)
    --platform PLATFORM      Platform: cuda, cpu (default: cuda)
    --env-name NAME          Custom conda environment name (optional)
    --skip-base              Skip base dependency installation
    --skip-megatron          Skip Megatron-LM-FL installation
    --skip-conda-create      Skip conda environment creation (use existing)
    --retry-count N          Number of retry attempts (default: 3)
    --help                   Show this help message

EXAMPLES:
    # Install training dependencies for CUDA platform
    $0 --task train --platform cuda --skip-conda-create

    # Install hetero_train dependencies (defaults to CUDA)
    $0 --task hetero_train --skip-conda-create

    # Install all task dependencies
    $0 --task all --platform cuda

    # Install with custom retry count
    $0 --task train --skip-conda-create --retry-count 5

VALID TASKS:
    train          - Training task dependencies
    hetero_train   - Heterogeneous training task dependencies
    inference      - Inference task dependencies (placeholder)
    rl             - Reinforcement learning task dependencies (placeholder)
    all            - Install all task dependencies

VALID PLATFORMS:
    cuda           - NVIDIA CUDA platform (default)
    cpu            - CPU-only platform (future)

EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --task)
                TASK="$2"
                shift 2
                ;;
            --platform)
                PLATFORM="$2"
                shift 2
                ;;
            --env-name)
                ENV_NAME="$2"
                shift 2
                ;;
            --skip-base)
                SKIP_BASE="true"
                shift
                ;;
            --skip-megatron)
                SKIP_MEGATRON="true"
                shift
                ;;
            --skip-conda-create)
                SKIP_CONDA_CREATE="true"
                shift
                ;;
            --retry-count)
                RETRY_COUNT="$2"
                shift 2
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

validate_inputs() {
    # Check if task is specified
    if [ -z "$TASK" ]; then
        log_error "Task not specified. Use --task to specify a task."
        usage
        exit 1
    fi

    # Check if task is valid
    local valid=false
    for valid_task in "${VALID_TASKS[@]}"; do
        if [ "$TASK" = "$valid_task" ]; then
            valid=true
            break
        fi
    done

    if [ "$valid" = "false" ]; then
        log_error "Invalid task: $TASK"
        log_error "Valid tasks: ${VALID_TASKS[*]}"
        exit 1
    fi

    # Check if platform is valid
    valid=false
    for valid_platform in "${VALID_PLATFORMS[@]}"; do
        if [ "$PLATFORM" = "$valid_platform" ]; then
            valid=true
            break
        fi
    done

    if [ "$valid" = "false" ]; then
        log_error "Invalid platform: $PLATFORM"
        log_error "Valid platforms: ${VALID_PLATFORMS[*]}"
        exit 1
    fi

    # Validate retry count
    if ! [[ "$RETRY_COUNT" =~ ^[0-9]+$ ]] || [ "$RETRY_COUNT" -lt 1 ]; then
        log_error "Invalid retry count: $RETRY_COUNT (must be positive integer)"
        exit 1
    fi

    log_success "Input validation passed"
}

export_env_vars() {
    export PLATFORM
    export ENV_NAME
    export SKIP_BASE
    export SKIP_MEGATRON
    export RETRY_COUNT
    export PROJECT_ROOT

    log_info "Environment variables exported:"
    log_info "  PLATFORM=$PLATFORM"
    log_info "  ENV_NAME=$ENV_NAME"
    log_info "  SKIP_BASE=$SKIP_BASE"
    log_info "  SKIP_MEGATRON=$SKIP_MEGATRON"
    log_info "  RETRY_COUNT=$RETRY_COUNT"
    log_info "  PROJECT_ROOT=$PROJECT_ROOT"
}

install_task() {
    local task=$1
    local install_script="$SCRIPT_DIR/$PLATFORM/install_${task}.sh"

    if [ ! -f "$install_script" ]; then
        log_error "Install script not found for task '$task' on platform '$PLATFORM'"
        log_error "Expected: $install_script"
        exit 1
    fi

    if [ ! -x "$install_script" ]; then
        log_warn "Install script not executable, making it executable"
        chmod +x "$install_script"
    fi

    log_step "Running install script for task '$task' on platform '$PLATFORM'"
    "$install_script"
}

main() {
    print_header "FlagScale Dependency Installation"

    # Parse command line arguments
    parse_args "$@"

    # Validate inputs
    validate_inputs

    # Export environment variables for sub-scripts
    export_env_vars

    # Display current environment
    log_info "Current conda environment: $(get_conda_env)"
    check_python_version || log_warn "Python version check failed (continuing anyway)"

    # Install dependencies based on task
    if [ "$TASK" = "all" ]; then
        log_info "Installing dependencies for all tasks"
        for task in train hetero_train inference rl; do
            print_separator
            install_task "$task"
        done
    else
        install_task "$TASK"
    fi

    print_header "Installation Complete"
    log_success "All dependencies installed successfully for task: $TASK"
}

# Make all install scripts executable
chmod +x "$SCRIPT_DIR"/*/install_*.sh 2>/dev/null || true
chmod +x "$SCRIPT_DIR"/utils/*.sh 2>/dev/null || true

# Run main function
main "$@"
