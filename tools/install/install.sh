#!/bin/bash
# Master installation orchestrator script
# Delegates to task-specific install scripts
#
# Task Discovery:
#   Valid tasks are discovered from platform configuration files
#   (tests/test_utils/config/platforms/*.yaml) which define supported
#   tasks under the functional tests section. Install scripts serve
#   as a fallback to ensure all tasks with implementations are recognized.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils/utils.sh"

# Get project root
PROJECT_ROOT=$(get_project_root)

# Default values
TASK=""
PLATFORM="cuda"  # Default to CUDA platform
ENV_NAME=""
SKIP_CONDA_CREATE="false"
RETRY_COUNT="3"

# Dynamically discover valid tasks from platform configuration
discover_valid_tasks() {
    local tasks=()
    local parse_config="$PROJECT_ROOT/tests/test_utils/runners/parse_config.py"

    # Primary method: Get tasks from platform configuration
    # This is the source of truth for which tasks are supported on the platform
    if [ -f "$parse_config" ] && command -v python >/dev/null 2>&1; then
        # Use parse_config.py to get functional tests from platform config
        # Extract task names (top-level keys) from the JSON output
        while IFS= read -r task; do
            if [ -n "$task" ]; then
                tasks+=("$task")
            fi
        done < <(python "$parse_config" --platform "$PLATFORM" --type functional 2>/dev/null | \
                 python -c "import sys, json; data = json.load(sys.stdin); print('\\n'.join(data.keys()))" 2>/dev/null || true)
    fi

    # Fallback method: Get tasks from install scripts that exist
    # This ensures tasks with install scripts but no tests yet are still valid
    if [ -d "$SCRIPT_DIR/$PLATFORM" ]; then
        for script in "$SCRIPT_DIR/$PLATFORM"/install_*.sh; do
            if [ -f "$script" ]; then
                task=$(basename "$script" | sed 's/^install_//' | sed 's/\.sh$//')
                if [ "$task" != "base" ]; then
                    # Add task if not already in array
                    if [[ ! " ${tasks[@]} " =~ " ${task} " ]]; then
                        tasks+=("$task")
                    fi
                fi
            fi
        done
    fi

    # Always add 'all' as a valid task for installing all dependencies
    tasks+=("all")

    # Return space-separated list
    echo "${tasks[@]}"
}

# Dynamically discover valid platforms from test config
discover_valid_platforms() {
    local platforms=()

    # Get platforms from test_utils/config/platforms/*.yaml files
    local config_dir="$PROJECT_ROOT/tests/test_utils/config/platforms"
    if [ -d "$config_dir" ]; then
        for config_file in "$config_dir"/*.yaml; do
            if [ -f "$config_file" ]; then
                platform=$(basename "$config_file" .yaml)
                # Skip template files
                if [ "$platform" != "template" ]; then
                    platforms+=("$platform")
                fi
            fi
        done
    fi

    # Return space-separated list
    echo "${platforms[@]}"
}

# Discover valid tasks and platforms
VALID_TASKS=($(discover_valid_tasks))
VALID_PLATFORMS=($(discover_valid_platforms))

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Master installation script for FlagScale dependencies.

OPTIONS:
    --task TASK              Task type: ${VALID_TASKS[*]} (required)
    --platform PLATFORM      Platform: ${VALID_PLATFORMS[*]} (default: cuda)
    --env-name NAME          Custom conda environment name (optional)
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

TASK DISCOVERY:
    Tasks are discovered from platform configuration files:
      - Primary: tests/test_utils/config/platforms/\${PLATFORM}.yaml
      - Fallback: install/\${PLATFORM}/install_*.sh scripts

DISCOVERED VALID TASKS:
$(printf '    %s\n' "${VALID_TASKS[@]}")

DISCOVERED VALID PLATFORMS:
$(printf '    %s\n' "${VALID_PLATFORMS[@]}")

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
    export RETRY_COUNT
    export PROJECT_ROOT

    log_info "Environment variables exported:"
    log_info "  PLATFORM=$PLATFORM"
    log_info "  ENV_NAME=$ENV_NAME"
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
        # Install all valid tasks except 'all' itself
        for task in "${VALID_TASKS[@]}"; do
            if [ "$task" != "all" ]; then
                print_separator
                install_task "$task"
            fi
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
