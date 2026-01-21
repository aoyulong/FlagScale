#!/bin/bash
# Base dependency installation script for CUDA platform
# Installs core dependencies (requirements is one type of dependency)
# - Package requirements: common packages and CUDA base packages from requirements folder

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/utils.sh"
source "$SCRIPT_DIR/../utils/retry_utils.sh"

# Platform
PLATFORM="cuda"

# Get project root
PROJECT_ROOT=$(get_project_root)

# Configuration
RETRY_COUNT="${RETRY_COUNT:-3}"

main() {
    print_header "Installing Base Dependencies (CUDA Platform)"

    log_info "Project root: $PROJECT_ROOT"
    log_info "Platform: $PLATFORM"
    log_info "Conda environment: $(get_conda_env)"

    # Install dependencies (requirements is one type of dependency)
    # This script installs package requirements (pip packages from requirements folder)
    install_package_requirements

    print_header "Base Dependencies Installation Complete"
}

install_package_requirements() {
    log_step "Installing package requirements (pip packages from requirements folder)"

    # Install platform-agnostic common requirements
    install_common_requirements

    # Install platform-specific base requirements
    install_platform_base_requirements
}

install_common_requirements() {
    local requirements_file="$PROJECT_ROOT/requirements/common.txt"

    if [ ! -f "$requirements_file" ]; then
        log_error "Common requirements file not found: $requirements_file"
        return 1
    fi

    log_step "Installing platform-agnostic common requirements"
    retry_pip_install "$requirements_file" "$RETRY_COUNT"
}

install_platform_base_requirements() {
    local requirements_file="$PROJECT_ROOT/requirements/$PLATFORM/base.txt"

    if [ ! -f "$requirements_file" ]; then
        log_warn "Platform base requirements file not found: $requirements_file (skipping)"
        return 0
    fi

    log_step "Installing $PLATFORM platform-specific base requirements"
    retry_pip_install "$requirements_file" "$RETRY_COUNT"
}

# Run main function
main "$@"
