import os
import subprocess

from setuptools import setup

# Version is defined in pyproject.toml - keep in sync
FLAGSCALE_VERSION = "1.0.0"

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
INSTALL_SCRIPT = os.path.join(SCRIPT_DIR, "tools", "install", "install.sh")


def is_pip_isolated_build():
    """Check if we're running in pip's isolated build environment.

    Isolated builds copy source to a temp directory. We detect this by checking
    if we're running from a temp location (e.g., /tmp/pip-*, /var/folders/*).
    """
    import tempfile

    script_dir = os.path.dirname(os.path.abspath(__file__))
    temp_dir = tempfile.gettempdir()

    # Check if we're in a temp directory
    if script_dir.startswith(temp_dir):
        return True

    # Check for common pip isolated build directory patterns
    if "/pip-build-env-" in script_dir or "/pip-wheel-" in script_dir:
        return True

    # macOS temp directories
    return script_dir.startswith("/var/folders/")


def run_install_script():
    """Invoke tools/install/install.sh for dependency installation."""
    if not os.path.exists(INSTALL_SCRIPT):
        print(f"[flagscale] Warning: Install script not found: {INSTALL_SCRIPT}")
        return

    platform = os.environ.get("FLAGSCALE_PLATFORM", "cuda")
    task = os.environ.get("FLAGSCALE_TASK", "all")

    cmd = [
        INSTALL_SCRIPT,
        "--platform",
        platform,
        "--task",
        task,
        "--pkg-mgr",
        "pip",
        "--no-system",
        "--only-pip",
        "--src-deps",
        "megatron-lm",
    ]

    print(f"[flagscale] Running: {' '.join(cmd)}")
    result = subprocess.run(cmd, check=False)
    if result.returncode != 0:
        raise RuntimeError(f"Installation failed with exit code {result.returncode}")


# Run install.sh when using: pip install --no-build-isolation .
# Control via env vars: FLAGSCALE_PLATFORM (default: cuda), FLAGSCALE_TASK (default: all)
if not is_pip_isolated_build():
    run_install_script()

# NOTE: Installation methods:
# 1. pip install .                      -> Installs flagscale CLI only (isolated build)
# 2. pip install --no-build-isolation . -> Installs CLI + pip deps + megatron-lm (no apt)
#    Control with: FLAGSCALE_PLATFORM=cuda FLAGSCALE_TASK=train pip install --no-build-isolation .
# 3. flagscale install                  -> Full installation (apt + pip + all source deps)

setup(
    name="flagscale",
    version=FLAGSCALE_VERSION,
    description="FlagScale is a comprehensive toolkit designed to support the entire lifecycle of large models, developed with the backing of the Beijing Academy of Artificial Intelligence (BAAI).",
    url="https://github.com/FlagOpen/FlagScale",
    packages=["flagscale"],
    package_dir={"flagscale": "flagscale"},
    install_requires=["typer>=0.9.0"],
    entry_points={"console_scripts": ["flagscale=flagscale.cli:flagscale"]},
)
