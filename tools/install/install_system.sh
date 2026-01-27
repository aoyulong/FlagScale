#!/bin/bash
# =============================================================================
# FlagScale System Dependencies Installation
# =============================================================================
#
# Installs system-level dependencies: apt packages, OpenMPI, Python environment
# Supports multiple package managers: pip, uv (default), conda
#
# Usage:
#   ./install_system.sh [--dev] [--platform PLATFORM] [--pkg-mgr PKG_MGR]
#
# Examples:
#   ./install_system.sh                           # Basic installation (uv)
#   ./install_system.sh --pkg-mgr uv              # Use uv package manager
#   ./install_system.sh --pkg-mgr conda           # Use conda package manager
#   ./install_system.sh --pkg-mgr pip             # Use pip (system Python)
#   ./install_system.sh --dev --platform cuda     # Include dev tools for CUDA
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils/utils.sh"
source "$SCRIPT_DIR/utils/versions.sh"

# =============================================================================
# Configuration
# =============================================================================
DEV_MODE=false
PLATFORM="${PLATFORM:-}"
PKG_MGR="${PKG_MGR:-uv}"  # pip, uv, conda (default: uv)

# Versions (from versions.json - single source of truth)
# Validate against env vars if set (catches Dockerfile/versions.json drift)
_PYTHON_VERSION="$(get_common "python")"
_UV_VERSION="$(get_common "uv")"
_OPENMPI_VERSION="$(get_common "openmpi")"

# Validation function - warns if env var differs from versions.json
validate_version() {
    local name=$1
    local expected=$2
    local actual=${!name:-}  # Get env var value by name

    if [ -n "$actual" ] && [ "$actual" != "$expected" ]; then
        log_warn "Version mismatch: $name=$actual (env) vs $expected (versions.json)"
        log_warn "Using versions.json value: $expected"
    fi
}

validate_version "PYTHON_VERSION" "$_PYTHON_VERSION"
validate_version "UV_VERSION" "$_UV_VERSION"
validate_version "OPENMPI_VERSION" "$_OPENMPI_VERSION"

# Use versions.json values (authoritative)
PYTHON_VERSION="$_PYTHON_VERSION"
UV_VERSION="$_UV_VERSION"
OPENMPI_VERSION="$_OPENMPI_VERSION"

# Environment paths
UV_PROJECT_ENVIRONMENT="${UV_PROJECT_ENVIRONMENT:-/opt/venv}"
CONDA_PATH="${CONDA_PATH:-/opt/miniconda3}"

# =============================================================================
# Package Lists
# =============================================================================
# Core system packages (common across deepspeed, vllm, sglang, megatron)
# Note: Python is installed via install_python (supports uv, conda, pip)
BASE_PACKAGES="
    software-properties-common ca-certificates curl wget sudo
    git git-lfs unzip tzdata locales gettext
    build-essential cmake ninja-build perl pkg-config
    openssh-client openssh-server
    rsync lsof kmod netcat-openbsd psmisc uuid-runtime
    net-tools iputils-ping
"

# InfiniBand/RDMA packages (common for distributed training)
RDMA_PACKAGES="
    libibverbs-dev libibverbs1 librdmacm1 rdma-core
    ibverbs-providers infiniband-diags perftest
    libnuma-dev libnuma1 numactl
"

# Libraries for ML frameworks (image, audio, async IO)
# Note: Platform-specific packages (e.g., libcupti-dev) should be in platform install scripts
ML_PACKAGES="
    ffmpeg libsm6 libxext6 libgl1
    libsndfile-dev libjpeg-dev libpng-dev
    libaio-dev libssl-dev libcurl4-openssl-dev
    ccache patchelf
"

DEV_PACKAGES="vim tmux screen htop iftop iotop gdb less tree"

# =============================================================================
# Installation Functions
# =============================================================================
install_apt_packages() {
    local packages="$BASE_PACKAGES $RDMA_PACKAGES $ML_PACKAGES"
    [ "$DEV_MODE" = true ] && packages="$packages $DEV_PACKAGES"

    log_step "Installing apt packages"
    apt-get update
    # shellcheck disable=SC2086
    apt-get install -y --no-install-recommends $packages
    rm -rf /var/lib/apt/lists/*
    apt-get clean
    log_success "Apt packages installed"
}

# Install Python using uv (fast, modern package manager)
install_python_uv() {
    log_step "Installing uv ${UV_VERSION} and Python ${PYTHON_VERSION}"

    # Install uv
    curl -LsSf "https://astral.sh/uv/${UV_VERSION}/install.sh" | sh

    # Create venv
    "$HOME/.local/bin/uv" venv "${UV_PROJECT_ENVIRONMENT}" --python "${PYTHON_VERSION}"

    # System symlinks
    ln -sf "${UV_PROJECT_ENVIRONMENT}/bin/python3" /usr/bin/python3
    ln -sf "${UV_PROJECT_ENVIRONMENT}/bin/python3-config" /usr/bin/python3-config
    ln -sf "${UV_PROJECT_ENVIRONMENT}/bin/pip" /usr/bin/pip
    ln -sf /usr/bin/python3 /usr/bin/python

    log_success "Python ${PYTHON_VERSION} environment ready at ${UV_PROJECT_ENVIRONMENT}"
}

# Install Python using conda (Miniconda)
install_python_conda() {
    log_step "Installing Miniconda with Python ${PYTHON_VERSION}"

    local conda_installer="/tmp/miniconda.sh"

    # Download Miniconda installer
    wget -q "https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh" -O "$conda_installer"

    # Install Miniconda
    bash "$conda_installer" -b -u -p "${CONDA_PATH}"
    rm -f "$conda_installer"

    # Initialize conda
    "${CONDA_PATH}/bin/conda" init bash
    "${CONDA_PATH}/bin/conda" config --set auto_activate_base false

    # Set default Python version
    "${CONDA_PATH}/bin/conda" install -y python="${PYTHON_VERSION}"

    # System symlinks (point to conda's python)
    ln -sf "${CONDA_PATH}/bin/python3" /usr/bin/python3
    ln -sf "${CONDA_PATH}/bin/python3-config" /usr/bin/python3-config 2>/dev/null || true
    ln -sf "${CONDA_PATH}/bin/pip" /usr/bin/pip
    ln -sf /usr/bin/python3 /usr/bin/python

    log_success "Miniconda with Python ${PYTHON_VERSION} installed at ${CONDA_PATH}"
}

# Install Python using system apt (for pip-only mode)
install_python_pip() {
    log_step "Installing system Python ${PYTHON_VERSION}"

    # Add deadsnakes PPA for newer Python versions if needed
    add-apt-repository -y ppa:deadsnakes/ppa 2>/dev/null || true
    apt-get update

    # Install Python and required packages
    apt-get install -y --no-install-recommends \
        "python${PYTHON_VERSION}" \
        "python${PYTHON_VERSION}-dev" \
        "python${PYTHON_VERSION}-venv" \
        python3-pip

    # Set as default Python
    update-alternatives --install /usr/bin/python3 python3 "/usr/bin/python${PYTHON_VERSION}" 1
    update-alternatives --set python3 "/usr/bin/python${PYTHON_VERSION}"

    # Create symlinks
    ln -sf "/usr/bin/python${PYTHON_VERSION}-config" /usr/bin/python3-config 2>/dev/null || true
    ln -sf /usr/bin/python3 /usr/bin/python

    # Upgrade pip
    python3 -m pip install --upgrade pip

    log_success "System Python ${PYTHON_VERSION} installed"
}

# Install Python based on package manager selection
install_python() {
    log_step "Setting up Python environment (pkg_mgr: ${PKG_MGR})"

    case "$PKG_MGR" in
        uv)
            install_python_uv
            ;;
        conda)
            install_python_conda
            ;;
        pip)
            install_python_pip
            ;;
        *)
            log_error "Unknown package manager: $PKG_MGR (use pip, uv, or conda)"
            exit 1
            ;;
    esac
}

install_openmpi() {
    local version="$OPENMPI_VERSION"
    local base_version="${version%.*}"
    local prefix="/usr/local/openmpi-${version}"

    log_step "Installing OpenMPI ${version}"

    # Download and build
    cd /tmp
    wget -q -O - "https://download.open-mpi.org/release/open-mpi/v${base_version}/openmpi-${version}.tar.gz" | tar xzf -
    cd "openmpi-${version}"
    ./configure --prefix="${prefix}" --quiet
    make -j"$(nproc)" install

    # Create standard symlink
    ln -sf "${prefix}" /usr/local/mpi

    # Create wrapper for root execution
    mv /usr/local/mpi/bin/mpirun /usr/local/mpi/bin/mpirun.real
    cat > /usr/local/mpi/bin/mpirun << 'EOF'
#!/bin/bash
exec mpirun.real --allow-run-as-root --prefix /usr/local/mpi "$@"
EOF
    chmod +x /usr/local/mpi/bin/mpirun

    # Cleanup
    rm -rf /tmp/openmpi-${version}

    log_success "OpenMPI ${version} installed"
}

install_env_scripts() {
    local profile_dir="/etc/profile.d"

    log_step "Installing environment scripts"

    # Install platform env (self-contained) or fallback to common
    if [ -n "$PLATFORM" ] && [ -f "$SCRIPT_DIR/$PLATFORM/env.sh" ]; then
        cp "$SCRIPT_DIR/$PLATFORM/env.sh" "$profile_dir/flagscale-env.sh"
        log_info "Installed $PLATFORM environment"
    else
        cp "$SCRIPT_DIR/env.sh" "$profile_dir/flagscale-env.sh"
        log_info "Installed common environment"
    fi

    # Enable in bash.bashrc for non-login shells
    if ! grep -q "flagscale-env.sh" /etc/bash.bashrc 2>/dev/null; then
        cat >> /etc/bash.bashrc << 'EOF'

# FlagScale environment
[ -f /etc/profile.d/flagscale-env.sh ] && . /etc/profile.d/flagscale-env.sh
EOF
    fi

    log_success "Environment scripts installed"
}

# =============================================================================
# Main
# =============================================================================
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    --dev              Include development tools (vim, tmux, htop, etc.)
    --platform NAME    Platform for env scripts (cuda, rocm, etc.)
    --pkg-mgr MGR      Package manager: pip, uv, conda (default: uv)
    --help             Show this help

Package Managers:
    uv     - Fast, modern package manager with venv (default)
    conda  - Miniconda installation
    pip    - System Python with pip

Versions (override via environment variables):
    PYTHON_VERSION     Python version (default: ${PYTHON_VERSION})
    UV_VERSION         uv version (default: ${UV_VERSION})
    OPENMPI_VERSION    OpenMPI version (default: ${OPENMPI_VERSION})

Environment paths (override via environment variables):
    UV_PROJECT_ENVIRONMENT  uv venv path (default: ${UV_PROJECT_ENVIRONMENT})
    CONDA_PATH              Miniconda path (default: ${CONDA_PATH})
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dev)      DEV_MODE=true; shift ;;
            --platform) PLATFORM="$2"; shift 2 ;;
            --pkg-mgr)  PKG_MGR="$2"; shift 2 ;;
            --help|-h)  usage; exit 0 ;;
            *)          log_error "Unknown option: $1"; exit 1 ;;
        esac
    done
}

main() {
    parse_args "$@"

    print_header "FlagScale System Dependencies"
    log_info "Python: ${PYTHON_VERSION}, Package manager: ${PKG_MGR}"
    log_info "OpenMPI: ${OPENMPI_VERSION}, Platform: ${PLATFORM:-none}, Dev mode: ${DEV_MODE}"

    install_apt_packages
    install_python
    install_openmpi
    install_env_scripts

    print_header "Installation Complete"
}

main "$@"
