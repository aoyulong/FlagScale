#!/bin/bash
# =============================================================================
# Package Manager Utilities
# =============================================================================
#
# Provides a unified interface for package installation supporting:
#   - pip: Standard Python package installer
#   - uv: Fast, modern Python package installer (uses uv pip)
#   - conda: Conda package manager (uses conda install for conda packages,
#            pip for PyPI packages within conda environments)
#
# Usage:
#   source pkg_utils.sh
#   set_pkg_manager "uv"  # or "pip" or "conda"
#   pkg_install -r requirements.txt
#   pkg_install package1 package2
#
# Environment:
#   FLAGSCALE_PKG_MANAGER - Set to "uv", "pip", or "conda" (default: uv)
#
# =============================================================================

_PKG_UTILS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_PKG_UTILS_DIR/utils.sh"

# =============================================================================
# Package Manager Functions
# =============================================================================

# Check if uv is available
has_uv() {
    command -v uv &> /dev/null
}

# Check if pip is available
has_pip() {
    command -v pip &> /dev/null
}

# Check if conda is available
has_conda() {
    command -v conda &> /dev/null
}

# Get current package manager
# Returns: "uv", "pip", or "conda"
get_pkg_manager() {
    echo "${FLAGSCALE_PKG_MANAGER:-uv}"
}

# Set package manager
# Usage: set_pkg_manager <uv|pip|conda>
set_pkg_manager() {
    local manager=$1
    case "$manager" in
        uv|pip|conda)
            export FLAGSCALE_PKG_MANAGER="$manager"
            log_info "Package manager set to: $manager"
            ;;
        *)
            log_error "Unknown package manager: $manager (use 'uv', 'pip', or 'conda')"
            return 1
            ;;
    esac
}

# =============================================================================
# Installation Functions
# =============================================================================

# Install packages using the configured package manager
# Usage: pkg_install [-r requirements.txt] [package1 package2 ...]
#
# For conda: Uses pip within the conda environment for requirements files
#            (conda install is used for conda-specific packages via pkg_conda_install)
pkg_install() {
    local manager=$(get_pkg_manager)
    local args=("$@")

    case "$manager" in
        uv)
            _uv_install "${args[@]}"
            ;;
        pip)
            _pip_install "${args[@]}"
            ;;
        conda)
            # For requirements files, use pip within conda environment
            # This is the standard approach for PyPI packages in conda
            _conda_pip_install "${args[@]}"
            ;;
        *)
            log_error "Unknown package manager: $manager"
            return 1
            ;;
    esac
}

# Install from requirements file
# Usage: pkg_install_requirements <requirements_file>
pkg_install_requirements() {
    local req_file=$1

    if [ ! -f "$req_file" ]; then
        log_error "Requirements file not found: $req_file"
        return 1
    fi

    pkg_install -r "$req_file"
}

# Install conda packages directly (only for conda manager)
# Usage: pkg_conda_install package1 package2 ...
pkg_conda_install() {
    local manager=$(get_pkg_manager)

    if [ "$manager" != "conda" ]; then
        log_warn "pkg_conda_install called but manager is $manager, using pip instead"
        pkg_install "$@"
        return
    fi

    if ! has_conda; then
        log_error "Conda not available"
        return 1
    fi

    conda install -y "$@"
}

# Install package from source (editable mode)
# Usage: pkg_install_editable <path> [extra_args...]
pkg_install_editable() {
    local path=$1
    shift
    local extra_args=("$@")
    local manager=$(get_pkg_manager)

    case "$manager" in
        uv)
            uv pip install -e "$path" "${extra_args[@]}"
            ;;
        pip|conda)
            pip install -e "$path" "${extra_args[@]}"
            ;;
    esac
}

# Install package without build isolation (for packages with complex builds)
# Usage: pkg_install_no_isolation <path>
pkg_install_no_isolation() {
    local path=$1
    local manager=$(get_pkg_manager)

    case "$manager" in
        uv)
            uv pip install --no-build-isolation "$path" -v
            ;;
        pip|conda)
            pip install --no-build-isolation "$path" -vvv
            ;;
    esac
}

# =============================================================================
# Internal Functions
# =============================================================================

# pip install wrapper
_pip_install() {
    pip install "$@"
}

# uv pip install wrapper
_uv_install() {
    uv pip install "$@"
}

# conda pip install wrapper (uses pip within conda environment)
_conda_pip_install() {
    # In conda environments, pip is the standard way to install PyPI packages
    pip install "$@"
}

# =============================================================================
# Display Functions
# =============================================================================

# Display package manager info
display_pkg_info() {
    local manager=$(get_pkg_manager)

    echo "Package Manager: $manager"

    case "$manager" in
        uv)
            if has_uv; then
                echo "UV Version: $(uv --version 2>/dev/null || echo 'unknown')"
                echo "UV Environment: ${UV_PROJECT_ENVIRONMENT:-${VIRTUAL_ENV:-not set}}"
            fi
            ;;
        pip)
            if has_pip; then
                echo "Pip Version: $(pip --version 2>/dev/null | awk '{print $2}' || echo 'unknown')"
            fi
            ;;
        conda)
            if has_conda; then
                echo "Conda Version: $(conda --version 2>/dev/null | awk '{print $2}' || echo 'unknown')"
                echo "Conda Environment: ${CONDA_DEFAULT_ENV:-base}"
            fi
            if has_pip; then
                echo "Pip Version: $(pip --version 2>/dev/null | awk '{print $2}' || echo 'unknown')"
            fi
            ;;
    esac
}

# Get install command for display purposes
get_install_cmd() {
    local manager=$(get_pkg_manager)
    case "$manager" in
        uv)    echo "uv pip install" ;;
        pip)   echo "pip install" ;;
        conda) echo "pip install (in conda)" ;;
    esac
}
