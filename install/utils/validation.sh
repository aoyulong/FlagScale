#!/bin/bash
# Installation validation utilities

# Source utils for logging
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Validate that a Python package is installed
# Usage: validate_package <package_name>
validate_package() {
    local package=$1

    log_step "Validating package: $package"

    if python -c "import $package" 2>/dev/null; then
        log_success "Package '$package' is installed"
        return 0
    else
        log_error "Package '$package' is not installed or cannot be imported"
        return 1
    fi
}

# Validate multiple packages
# Usage: validate_packages <package1> <package2> ...
validate_packages() {
    local failed=0
    local packages=("$@")

    log_info "Validating ${#packages[@]} packages"

    for package in "${packages[@]}"; do
        if ! validate_package "$package"; then
            failed=$((failed + 1))
        fi
    done

    if [ $failed -eq 0 ]; then
        log_success "All packages validated successfully"
        return 0
    else
        log_error "$failed package(s) failed validation"
        return 1
    fi
}

# Validate Megatron-LM installation
# Usage: validate_megatron
validate_megatron() {
    log_step "Validating Megatron-LM installation"

    if python -c "import megatron.core; print('Megatron-LM OK')" 2>/dev/null; then
        log_success "Megatron-LM is properly installed"
        return 0
    else
        log_error "Megatron-LM validation failed"
        return 1
    fi
}

# Validate base installation
# Usage: validate_base_install
validate_base_install() {
    log_info "Validating base installation"

    local core_packages=("numpy" "torch")
    local failed=0

    for package in "${core_packages[@]}"; do
        if ! validate_package "$package"; then
            failed=$((failed + 1))
        fi
    done

    if [ $failed -eq 0 ]; then
        log_success "Base installation validated"
        return 0
    else
        log_error "Base installation validation failed"
        return 1
    fi
}

# Validate training installation
# Usage: validate_train_install
validate_train_install() {
    log_info "Validating training installation"

    local train_packages=("httpx" "fastapi")
    local failed=0

    for package in "${train_packages[@]}"; do
        if ! validate_package "$package"; then
            failed=$((failed + 1))
        fi
    done

    if [ $failed -eq 0 ]; then
        log_success "Training installation validated"
        return 0
    else
        log_warn "Some training packages failed validation (non-critical)"
        return 0  # Non-critical, don't fail
    fi
}
