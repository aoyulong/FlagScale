#!/bin/bash
# Training dependency installation script for CUDA platform
# Installs training-specific dependencies

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/utils.sh"
source "$SCRIPT_DIR/../utils/retry_utils.sh"
source "$SCRIPT_DIR/../utils/validation.sh"

# Get project root
PROJECT_ROOT=$(get_project_root)

# Platform and task name
PLATFORM="cuda"
TASK_NAME="train"
DEFAULT_ENV_NAME="flagscale-train"

# Configuration from environment or defaults
ENV_NAME="${ENV_NAME:-$DEFAULT_ENV_NAME}"
SKIP_BASE="${SKIP_BASE:-false}"
SKIP_MEGATRON="${SKIP_MEGATRON:-false}"
RETRY_COUNT="${RETRY_COUNT:-3}"

main() {
    print_header "Installing Dependencies for Task: $TASK_NAME (CUDA Platform)"

    log_info "Project root: $PROJECT_ROOT"
    log_info "Platform: $PLATFORM"
    log_info "Conda environment: $(get_conda_env)"
    log_info "Target environment: $ENV_NAME"

    # Install base dependencies unless skipped
    if [ "$SKIP_BASE" != "true" ]; then
        install_base_dependencies
    else
        log_info "Skipping base dependencies (SKIP_BASE=true)"
    fi

    # Install task-specific dependencies
    install_task_dependencies

    # Install Megatron-LM-FL unless skipped
    if [ "$SKIP_MEGATRON" != "true" ]; then
        install_megatron_lm
    else
        log_info "Skipping Megatron-LM installation (SKIP_MEGATRON=true)"
    fi

    # Install additional dependencies (robotics, etc.)
    install_additional_dependencies

    # Validate installation
    validate_installation

    print_header "Installation Complete for Task: $TASK_NAME"
}

install_base_dependencies() {
    log_step "Installing base dependencies"
    "$SCRIPT_DIR/install_base.sh"
}

install_task_dependencies() {
    local requirements_file="$PROJECT_ROOT/requirements/$PLATFORM/${TASK_NAME}.txt"

    if [ ! -f "$requirements_file" ]; then
        log_warn "Task requirements file not found: $requirements_file"
        return 0
    fi

    log_step "Installing $TASK_NAME-specific dependencies for $PLATFORM"
    retry_pip_install "$requirements_file" "$RETRY_COUNT"
}

install_megatron_lm() {
    log_step "Installing Megatron-LM-FL"

    local megatron_dir="$PROJECT_ROOT/Megatron-LM-FL"
    local megatron_url="https://github.com/flagos-ai/Megatron-LM-FL.git"

    # Clone and install Megatron-LM-FL
    retry_git_clone "$megatron_url" "$megatron_dir" "$RETRY_COUNT"

    # Install Megatron-LM
    log_step "Installing Megatron-LM from source"
    cd "$megatron_dir"
    retry $RETRY_COUNT "pip install --no-build-isolation . -vvv"
    cd "$PROJECT_ROOT"
}

install_additional_dependencies() {
    # Install robotics-specific dependencies if they exist
    local robotics_req="$PROJECT_ROOT/requirements/${TASK_NAME}/robotics/requirements.txt"
    if [ -f "$robotics_req" ]; then
        log_step "Installing robotics dependencies"
        retry_pip_install "$robotics_req" "$RETRY_COUNT"
    fi
}

validate_installation() {
    log_step "Validating $TASK_NAME installation"

    # Validate core packages
    if ! validate_base_install; then
        log_error "Base installation validation failed"
        return 1
    fi

    # Validate Megatron if it was installed
    if [ "$SKIP_MEGATRON" != "true" ]; then
        if ! validate_megatron; then
            log_warn "Megatron-LM validation failed (non-critical)"
        fi
    fi

    # Validate training packages
    validate_train_install

    log_success "Validation complete for $TASK_NAME"
}

# Run main function
main "$@"
