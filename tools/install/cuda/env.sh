#!/bin/bash
# =============================================================================
# FlagScale CUDA Environment Variables
# =============================================================================
#
# Self-contained environment setup for CUDA platform.
# Includes all common + CUDA-specific variables.
#
# Usage:
#   - Development: source tools/install/cuda/env.sh
#   - Docker: Sourced via /etc/profile.d/flagscale-env.sh
#
# Variables can be overridden by setting them before sourcing this file.
# =============================================================================

# -----------------------------------------------------------------------------
# Common Configuration
# -----------------------------------------------------------------------------
: "${UV_PROJECT_ENVIRONMENT:=/opt/venv}"
: "${CONDA_PATH:=/opt/miniconda3}"
: "${MPI_HOME:=/usr/local/mpi}"
: "${UV_HTTP_TIMEOUT:=500}"
: "${UV_INDEX_STRATEGY:=unsafe-best-match}"
: "${UV_LINK_MODE:=copy}"

# -----------------------------------------------------------------------------
# CUDA Configuration
# -----------------------------------------------------------------------------
: "${CUDA_HOME:=/usr/local/cuda}"

# -----------------------------------------------------------------------------
# Export Variables
# -----------------------------------------------------------------------------
export UV_PROJECT_ENVIRONMENT CONDA_PATH MPI_HOME CUDA_HOME
export UV_HTTP_TIMEOUT UV_INDEX_STRATEGY UV_LINK_MODE
export VIRTUAL_ENV="$UV_PROJECT_ENVIRONMENT"

# -----------------------------------------------------------------------------
# PATH Configuration
# -----------------------------------------------------------------------------
export PATH="$UV_PROJECT_ENVIRONMENT/bin:$CONDA_PATH/bin:$HOME/.local/bin:$MPI_HOME/bin:$CUDA_HOME/bin:$PATH"
export LD_LIBRARY_PATH="$CUDA_HOME/lib64:$MPI_HOME/lib64:$MPI_HOME/lib:/usr/local/lib:$LD_LIBRARY_PATH"
