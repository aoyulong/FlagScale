#!/bin/bash
# =============================================================================
# Version Loading Utility
# =============================================================================
#
# Loads version information from versions.json (single source of truth)
# located at the project root.
#
# Structure of versions.json:
#   common     - Versions shared by all platforms
#   <platform> - Platform-specific versions (e.g., cuda)
#
# Each entry has: {"version": "x.y.z", "pip": true/false}
#   pip: true  - Python package (pip install)
#   pip: false - System tool (build arg)
#
# Usage:
#   source utils/versions.sh
#   python_ver=$(get_common "python")
#   torch_ver=$(get_platform "cuda" "torch")
# =============================================================================

# Get the project root directory
_get_versions_project_root() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    cd "$script_dir/../../.."
    pwd
}

# Path to versions.json
VERSIONS_FILE="$(_get_versions_project_root)/versions.json"

# Check if jq is available (required for JSON parsing)
_check_jq() {
    if ! command -v jq &> /dev/null; then
        return 1
    fi
    return 0
}

# =============================================================================
# Version getters
# =============================================================================

# Get version from common section (with fallback defaults)
# Usage: python_ver=$(get_common "python")
get_common() {
    local name=$1
    local version=""

    if _check_jq && [ -f "$VERSIONS_FILE" ]; then
        version=$(jq -r ".common.\"${name}\".version // empty" "$VERSIONS_FILE")
    fi

    # Fallback defaults for critical tools when jq unavailable
    if [ -z "$version" ]; then
        case "$name" in
            python)   version="3.12" ;;
            uv)       version="0.7.2" ;;
            openmpi)  version="4.1.6" ;;
        esac
    fi

    echo "$version"
}

# Get version from platform section
# Usage: torch_ver=$(get_platform "cuda" "torch")
get_platform() {
    local platform=$1
    local name=$2

    if _check_jq && [ -f "$VERSIONS_FILE" ]; then
        jq -r ".\"${platform}\".\"${name}\".version // empty" "$VERSIONS_FILE"
    fi
}

# Check if entry is a pip package
# Usage: if is_pip "common" "hydra-core"; then ...
is_pip() {
    local section=$1
    local name=$2

    if _check_jq && [ -f "$VERSIONS_FILE" ]; then
        local result=$(jq -r ".\"${section}\".\"${name}\".pip // false" "$VERSIONS_FILE")
        [ "$result" = "true" ]
    else
        return 1
    fi
}

# =============================================================================
# Section helpers
# =============================================================================

# Get all keys from a section
# Usage: for key in $(get_section_keys "common"); do ...
get_section_keys() {
    local section=$1

    if _check_jq && [ -f "$VERSIONS_FILE" ]; then
        jq -r ".\"${section}\" | keys[]" "$VERSIONS_FILE"
    fi
}

# Get all platforms (excluding "common" and "dev")
# Usage: for platform in $(get_all_platforms); do ...
get_all_platforms() {
    if _check_jq && [ -f "$VERSIONS_FILE" ]; then
        jq -r 'keys[] | select(. != "common" and . != "dev")' "$VERSIONS_FILE"
    fi
}

# =============================================================================
# Display helpers
# =============================================================================

# Print all versions (for debugging)
print_versions() {
    if ! _check_jq || [ ! -f "$VERSIONS_FILE" ]; then
        echo "[WARN] Cannot read versions.json" >&2
        return 1
    fi

    echo "Versions from: $VERSIONS_FILE"
    echo ""
    echo "Common:"
    for key in $(get_section_keys "common"); do
        local version=$(get_common "$key")
        local pip_flag=""
        is_pip "common" "$key" && pip_flag=" (pip)"
        printf "  %-14s %s%s\n" "$key:" "$version" "$pip_flag"
    done

    for platform in $(get_all_platforms); do
        echo ""
        echo "${platform^}:"
        for key in $(get_section_keys "$platform"); do
            local version=$(get_platform "$platform" "$key")
            local pip_flag=""
            is_pip "$platform" "$key" && pip_flag=" (pip)"
            printf "  %-14s %s%s\n" "$key:" "$version" "$pip_flag"
        done
    done
}

# Print pip package versions for requirements files
print_package_versions() {
    if ! _check_jq || [ ! -f "$VERSIONS_FILE" ]; then
        echo "[ERROR] Cannot read versions without jq and versions.json" >&2
        return 1
    fi

    echo "# Package versions from versions.json"
    echo ""
    echo "# Common packages (requirements/common.txt):"
    jq -r '.common | to_entries[] | select(.value.pip == true) | "\(.key)==\(.value.version)"' "$VERSIONS_FILE"
    echo ""
    echo "# CUDA packages (requirements/cuda/base.txt):"
    jq -r '.cuda | to_entries[] | select(.value.pip == true) | "\(.key)==\(.value.version)"' "$VERSIONS_FILE"
}
