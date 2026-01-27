#!/bin/bash
# =============================================================================
# FlagScale Common Environment Variables
# =============================================================================
#
# This file sets up the runtime environment for FlagScale.
# Platform-specific variables are defined in <platform>/env.sh files.
#
# Usage:
#   - Docker: Sourced via /etc/profile.d/flagscale-env.sh
#   - Non-container: Source this file in your shell profile (~/.bashrc)
#
# Variables can be overridden by setting them before sourcing this file.
# =============================================================================

# -----------------------------------------------------------------------------
# Default Configuration
# -----------------------------------------------------------------------------
: "${UV_PROJECT_ENVIRONMENT:=/opt/venv}"
: "${CONDA_PATH:=/opt/miniconda3}"
: "${MPI_HOME:=/usr/local/mpi}"
: "${UV_HTTP_TIMEOUT:=500}"
: "${UV_INDEX_STRATEGY:=unsafe-best-match}"
: "${UV_LINK_MODE:=copy}"

export UV_PROJECT_ENVIRONMENT CONDA_PATH MPI_HOME
export UV_HTTP_TIMEOUT UV_INDEX_STRATEGY UV_LINK_MODE
export VIRTUAL_ENV="$UV_PROJECT_ENVIRONMENT"

# -----------------------------------------------------------------------------
# Library Paths
# -----------------------------------------------------------------------------
# Build LD_LIBRARY_PATH (prepend to existing)
_add_lib_path() {
    [ -d "$1" ] && export LD_LIBRARY_PATH="$1${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
}
_add_lib_path "$MPI_HOME/lib64"
_add_lib_path "$MPI_HOME/lib"
_add_lib_path "/usr/local/lib"
unset -f _add_lib_path

# -----------------------------------------------------------------------------
# PATH Configuration
# -----------------------------------------------------------------------------
_add_to_path() {
    case ":$PATH:" in
        *":$1:"*) ;;
        *) [ -d "$1" ] && export PATH="$1:$PATH" ;;
    esac
}

# Add paths in order of priority (last added = highest priority)
_add_to_path "$MPI_HOME/bin"
_add_to_path "$HOME/.local/bin"
_add_to_path "$CONDA_PATH/bin"
_add_to_path "$UV_PROJECT_ENVIRONMENT/bin"

unset -f _add_to_path
