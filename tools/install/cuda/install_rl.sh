#!/bin/bash
# RL (Reinforcement Learning) dependency installation script for CUDA platform
# Installs rl-specific dependencies (requirements is one type of dependency)
# - Package requirements: pip packages from requirements folder
# - Source dependencies: git repositories (to be added when needed)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/utils.sh"
source "$SCRIPT_DIR/../utils/retry_utils.sh"

# Get project root
PROJECT_ROOT=$(get_project_root)

# Platform and task name
PLATFORM="cuda"
TASK_NAME="rl"
DEFAULT_ENV_NAME="flagscale-rl"

# Configuration from environment or defaults
ENV_NAME="${ENV_NAME:-$DEFAULT_ENV_NAME}"
RETRY_COUNT="${RETRY_COUNT:-3}"

main() {
    print_header "Installing Dependencies for Task: $TASK_NAME (CUDA Platform)"

    log_info "Project root: $PROJECT_ROOT"
    log_info "Platform: $PLATFORM"
    log_info "Conda environment: $(get_conda_env)"
    log_info "Target environment: $ENV_NAME"

    # Install base dependencies (always required)
    install_base_dependencies

    # Install task-specific dependencies (multiple types)
    install_task_dependencies

    print_header "Installation Complete for Task: $TASK_NAME"
}

install_base_dependencies() {
    log_step "Installing base dependencies"
    "$SCRIPT_DIR/install_base.sh"
}

install_task_dependencies() {
    log_step "Installing $TASK_NAME-specific dependencies for $PLATFORM"

    # Install multiple types of dependencies:
    # 1. Package requirements (pip packages from requirements folder)
    install_package_requirements

    # 2. Source dependencies (git repositories) - uncomment when needed
    # install_source_dependencies
}

install_package_requirements() {
    local requirements_file="$PROJECT_ROOT/requirements/$PLATFORM/${TASK_NAME}.txt"

    if [ ! -f "$requirements_file" ]; then
        log_warn "Task requirements file not found: $requirements_file (skipping)"
        return 0
    fi

    log_step "Installing package requirements (pip packages) from $requirements_file"
    retry_pip_install "$requirements_file" "$RETRY_COUNT"
}

# Uncomment and implement when source dependencies (git repositories) are needed
# install_source_dependencies() {
#     log_step "Installing source dependencies (git repositories)"
#     # Add source dependency installations here
# }

# Run main function
main "$@"
