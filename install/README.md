# FlagScale Installation Scripts

This directory contains modular installation scripts for FlagScale dependencies organized by platform and task type.

## Quick Start

```bash
# Install training dependencies for CUDA platform
./install/install.sh --platform cuda --task train --skip-conda-create

# Install hetero_train dependencies (defaults to CUDA)
./install/install.sh --task hetero_train --skip-conda-create

# Install all task dependencies
./install/install.sh --platform cuda --task all
```

## Directory Structure

```
install/
├── install.sh                    # Master orchestrator script
├── utils/                        # Shared utility libraries
│   ├── utils.sh                  # Logging and helper functions
│   ├── conda_utils.sh            # Conda environment management
│   ├── retry_utils.sh            # Retry logic for network operations
│   └── validation.sh             # Installation validation
├── cuda/                         # CUDA platform scripts
│   ├── install_base.sh           # Base dependencies for CUDA
│   ├── install_train.sh          # Training-specific dependencies
│   ├── install_hetero_train.sh   # Heterogeneous training dependencies
│   ├── install_inference.sh      # Inference dependencies (placeholder)
│   └── install_rl.sh             # RL dependencies (placeholder)
├── cpu/                          # CPU platform scripts (future)
│   └── ...
└── README.md                     # This file
```

## Master Script Usage

The `install.sh` script is the main entry point for installing dependencies:

```bash
./install/install.sh [OPTIONS]

OPTIONS:
    --task TASK              Task type: train, hetero_train, inference, rl, all (required)
    --platform PLATFORM      Platform: cuda, cpu (default: cuda)
    --env-name NAME          Custom conda environment name (optional)
    --skip-base              Skip base dependency installation
    --skip-megatron          Skip Megatron-LM-FL installation
    --skip-conda-create      Skip conda environment creation (use existing)
    --retry-count N          Number of retry attempts (default: 3)
    --help                   Show help message
```

## Available Tasks

| Task | Description | Status |
|------|-------------|--------|
| `train` | Training task dependencies | ✅ Implemented |
| `hetero_train` | Heterogeneous training dependencies | ✅ Implemented |
| `inference` | Inference task dependencies | 🚧 Placeholder |
| `rl` | Reinforcement learning dependencies | 🚧 Placeholder |
| `all` | Install all task dependencies | ✅ Implemented |

## Examples

### Install training dependencies
```bash
# In CI environment (with conda already activated)
./install/install.sh --platform cuda --task train --skip-conda-create --retry-count 3
```

### Install without Megatron-LM
```bash
# Skip Megatron-LM installation (e.g., for unit tests)
./install/install.sh --platform cuda --task train --skip-conda-create --skip-megatron
```

### Install base dependencies only
```bash
# Install only base requirements for CUDA
./install/cuda/install_base.sh
```

### Local development setup
```bash
# Install with defaults (CUDA platform)
./install/install.sh --task train

# Install with custom environment name
./install/install.sh --platform cuda --task train --env-name my-env
```

## Requirements Files

Requirements are organized by platform in `requirements/`:

- `common.txt` - Platform-agnostic common dependencies (numpy, pandas, etc.)
- `cuda/base.txt` - CUDA-specific base packages (torch+cuda, etc.)
- `cuda/train.txt` - Training task dependencies for CUDA
- `cuda/hetero_train.txt` - Hetero training dependencies for CUDA
- `cuda/inference.txt` - Inference dependencies for CUDA (placeholder)
- `cuda/rl.txt` - RL dependencies for CUDA (placeholder)
- `cpu/` - CPU platform requirements (future)

## Utility Libraries

### retry_utils.sh
Functions for retrying operations:
- `retry <count> <command>` - Retry a command N times
- `retry_commands <count> <cmd1> <cmd2> ...` - Retry batch of commands
- `retry_pip_install <file> [count]` - Retry pip install from requirements file
- `retry_git_clone <url> <dir> [count]` - Retry git clone operation

### utils.sh
Logging and helper functions:
- `log_info`, `log_warn`, `log_error`, `log_success` - Logging with emojis
- `get_project_root` - Get FlagScale project root directory
- `check_python_version` - Validate Python version

### conda_utils.sh
Conda environment management:
- `create_conda_env <name> [python_version]` - Create new environment
- `activate_conda_env <name>` - Activate environment
- `conda_env_exists <name>` - Check if environment exists

### validation.sh
Installation validation:
- `validate_package <name>` - Check if package is installed
- `validate_megatron` - Validate Megatron-LM installation
- `validate_base_install` - Validate core packages
- `validate_train_install` - Validate training packages

## Environment Variables

The scripts use these environment variables (set automatically by `install.sh`):

- `ENV_NAME` - Conda environment name
- `SKIP_BASE` - Skip base dependency installation (true/false)
- `SKIP_MEGATRON` - Skip Megatron-LM installation (true/false)
- `RETRY_COUNT` - Number of retry attempts
- `PROJECT_ROOT` - FlagScale project root directory

## Adding New Tasks

To add a new task (e.g., `multimodal`) for CUDA platform:

1. Create requirements file: `requirements/cuda/multimodal.txt`
2. Create install script: `install/cuda/install_multimodal.sh` (copy from `install/cuda/install_train.sh` as template)
3. Update `VALID_TASKS` array in `install/install.sh`
4. Test locally: `./install/install.sh --platform cuda --task multimodal --skip-conda-create`

## Adding New Platforms

To add a new platform (e.g., `rocm`):

1. Create platform directory: `install/rocm/`
2. Copy and adapt scripts from `install/cuda/`:
   - `install_base.sh` - Update PLATFORM variable
   - `install_train.sh`, etc. - Update PLATFORM variable
3. Create requirements directory: `requirements/rocm/`
4. Create requirements files:
   - `base.txt` - Platform-specific base packages
   - `train.txt`, `hetero_train.txt`, etc.
5. Add `rocm` to `VALID_PLATFORMS` in `install/install.sh`
6. Test: `./install/install.sh --platform rocm --task train --skip-conda-create`

## Troubleshooting

### Script not executable
```bash
chmod +x install/*.sh install/utils/*.sh
```

### Python version check fails
Ensure Python 3.10+ is installed and in PATH:
```bash
python --version
```

### Conda environment not found
Ensure conda is initialized and environment exists:
```bash
conda env list
```

### Package import fails after installation
Try reinstalling in clean environment:
```bash
pip uninstall <package> -y
./install/install.sh --task train --skip-conda-create
```

## CI/CD Integration

These scripts are used by GitHub Actions workflows:

- [unit_tests_common.yml](/.github/workflows/unit_tests_common.yml) - Uses `--platform cuda --task train`
- [functional_tests_train.yml](/.github/workflows/functional_tests_train.yml) - Uses `--platform cuda --task train`
- [functional_tests_hetero_train.yml](/.github/workflows/functional_tests_hetero_train.yml) - Uses `--platform cuda --task hetero_train`

Example workflow usage:
```yaml
- name: Install dependencies
  run: |
    source /root/miniconda3/bin/activate flagscale-train
    ./install/install.sh --platform cuda --task train --skip-conda-create --retry-count 3
```

## Support

For issues or questions:
- Check the [troubleshooting section](#troubleshooting)
- Review workflow logs in GitHub Actions
- See [docs/adding_new_tasks.md](/docs/adding_new_tasks.md) for detailed task addition guide
