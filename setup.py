import os
import re
import subprocess
import sys

from setuptools import setup

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


def _get_version() -> str:
    """Read version from pyproject.toml (single source of truth, Python 3.11+)."""
    try:
        import tomllib

        pyproject_path = os.path.join(SCRIPT_DIR, "pyproject.toml")
        with open(pyproject_path, "rb") as f:
            data = tomllib.load(f)
            return data.get("project", {}).get("version", "0.0.0")
    except Exception:
        return "0.0.0"


def parse_requirements(req_file):
    """Parse a requirements file, recursively resolving -r includes.

    Returns (deps, pip_options, pkg_options) where:
      - deps: list of PEP 508 dependency specifiers (normal packages)
      - pip_options: list of pip option strings (e.g. '--extra-index-url https://...',
        '--trusted-host example.com', '--pre', etc.) preserved as-is from the file
      - pkg_options: dict mapping package specifier -> list of per-package pip
        options (e.g. ``{"megatron-core @ git+...": ["--no-build-isolation"]}``)

    A comment line matching ``# [--option1 --option2 ...]`` sets pending
    per-package options that apply to the **next package line only**, then
    reset.  Multiple such comments before a package line stack (options merge).
    The annotations are plain comments so the file remains valid for
    ``pip install -r``.
    """
    req_path = os.path.join(SCRIPT_DIR, req_file)
    if not os.path.isfile(req_path):
        return [], [], {}
    deps = []
    pip_options = []
    pkg_options = {}
    pending_options = []
    base_dir = os.path.dirname(req_path)
    with open(req_path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith("#"):
                m = re.match(r"^#\s*\[([^\]]+)\]\s*$", line)
                if m:
                    opts = m.group(1).split()
                    if opts and all(o.startswith("--") for o in opts):
                        pending_options.extend(opts)
                continue
            if line.startswith("-r "):
                included = line[3:].strip()
                included_path = os.path.normpath(os.path.join(base_dir, included))
                rel_path = os.path.relpath(included_path, SCRIPT_DIR)
                sub_deps, sub_opts, sub_pkg_opts = parse_requirements(rel_path)
                deps.extend(sub_deps)
                pip_options.extend(sub_opts)
                pkg_options.update(sub_pkg_opts)
            elif line.startswith("-"):
                pip_options.append(line)
            else:
                deps.append(line)
                if pending_options:
                    pkg_options[line] = list(pending_options)
                    pending_options = []
    return deps, pip_options, pkg_options


def build_extras():
    """Build extras_require by scanning requirements/ directory.

    Auto-discovers platforms (cuda, rocm, ...) and tasks (train, serve, ...).
    Maps: requirements/<platform>/<task>.txt -> extra "<platform>-<task>"
    Special: base.txt -> extra "<platform>", dev.txt -> extra "dev"

    Returns (extras, pip_options, pkg_options) where:
      - extras: dict mapping extra name -> list of PEP 508 specifiers
        (excludes packages with per-package options — those are installed
        separately via get_pip_install_cmd())
      - pip_options: dict mapping extra name -> list of pip option strings
      - pkg_options: dict mapping extra name -> dict of package -> list of options
    """
    extras = {}
    extra_pip_options = {}
    extra_pkg_options = {}
    req_dir = os.path.join(SCRIPT_DIR, "requirements")
    for entry in sorted(os.listdir(req_dir)):
        entry_path = os.path.join(req_dir, entry)
        if not os.path.isdir(entry_path):
            continue
        # Platform directory (cuda, rocm, ...)
        for filename in sorted(os.listdir(entry_path)):
            if not filename.endswith(".txt"):
                continue
            task = filename[:-4]  # strip .txt
            extra_name = entry if task == "base" else f"{entry}-{task}"
            deps, opts, pkg_opts = parse_requirements(os.path.join("requirements", entry, filename))
            # Exclude annotated packages from extras_require — they need
            # special pip flags and are installed separately.
            normal_deps = [d for d in deps if d not in pkg_opts]
            if normal_deps or pkg_opts:
                extras[extra_name] = normal_deps
            if opts:
                extra_pip_options[extra_name] = list(dict.fromkeys(opts))
            if pkg_opts:
                extra_pkg_options[extra_name] = pkg_opts
    # Dev extras (platform-independent)
    dev_deps, dev_opts, dev_pkg_opts = parse_requirements("requirements/dev.txt")
    dev_normal = [d for d in dev_deps if d not in dev_pkg_opts]
    if dev_normal or dev_pkg_opts:
        extras["dev"] = dev_normal
    if dev_opts:
        extra_pip_options["dev"] = list(dict.fromkeys(dev_opts))
    if dev_pkg_opts:
        extra_pkg_options["dev"] = dev_pkg_opts
    return extras, extra_pip_options, extra_pkg_options


EXTRAS, PIP_OPTIONS, PKG_OPTIONS = build_extras()


def get_pip_install_cmd(extra_name):
    """Return the pip install command(s) for a given extra.

    When an extra contains packages with per-package options (e.g.
    ``--no-build-isolation``), separate commands are generated for each
    distinct option set (chained with ``&&``).  Packages with options are
    NOT in ``extras_require`` so the first ``pip install ".[extra]"``
    command won't attempt to build them.

    Prints reminder notes to stderr for packages that need special options.

    Includes any pip options (--extra-index-url, --find-links, etc.)
    extracted from the requirements files.
    Returns None if the extra doesn't exist.
    """
    if extra_name not in EXTRAS and extra_name not in PKG_OPTIONS:
        return None
    opts = ""
    for opt in PIP_OPTIONS.get(extra_name, []):
        opts += f" {opt}"

    pkg_opts = PKG_OPTIONS.get(extra_name, {})
    if not pkg_opts:
        return f'pip install ".[{extra_name}]"{opts}'

    cmds = []
    # Install normal deps (those without per-package options) via extras
    if EXTRAS.get(extra_name):
        cmds.append(f'pip install ".[{extra_name}]"{opts}')

    # Group annotated packages by their option sets
    groups = {}
    for pkg, pkg_opt_list in pkg_opts.items():
        key = tuple(sorted(pkg_opt_list))
        groups.setdefault(key, []).append(pkg)

    for opt_tuple, pkgs in groups.items():
        opt_str = " ".join(opt_tuple)
        pkg_str = " ".join(f'"{p}"' for p in pkgs)
        cmds.append(f"pip install {opt_str} {pkg_str}{opts}")
        for p in pkgs:
            print(f"Note: {p.split('@')[0].strip()} requires: {opt_str}", file=sys.stderr)

    return " && ".join(cmds)


# NOTE: Installation methods:
# 1. pip install .                    -> CLI only (typer)
# 2. pip install ".[cuda-train]"      -> CLI + pip deps + auto-install annotated packages
#    Annotated packages (e.g. megatron-core with --no-build-isolation) are excluded from
#    extras_require and auto-installed via _auto_install_annotated_packages() after setup().
#    Requires torch to be pre-installed. Use -v/-vvv for detailed install output.
# 3. pip install ".[cuda-all,dev]"    -> CLI + all CUDA pip deps + dev tools
# 4. pip install -r requirements/cuda/train.txt  -> pip deps with index URLs (handled natively)
#    Packages annotated with "# [--option ...]" need separate install with those options.
#    The shell installer (tools/install) handles this via parse_pkg_annotations().
# 5. flagscale install                -> Full installation (apt + pip + ALL source deps including apex, flash-attn)

setup(
    name="flagscale",
    version=_get_version(),
    description="FlagScale is a comprehensive toolkit designed to support the entire lifecycle of large models, developed with the backing of the Beijing Academy of Artificial Intelligence (BAAI).",
    url="https://github.com/FlagOpen/FlagScale",
    packages=["flagscale"],
    package_dir={"flagscale": "flagscale"},
    extras_require=EXTRAS,
    entry_points={"console_scripts": ["flagscale=flagscale.cli:flagscale"]},
)

_BUILD_ISOLATION_VARS = (
    "PYTHONPATH",
    "PYTHONNOUSERSITE",
    "PEP517_BUILD_BACKEND",
    "PIP_BUILD_TRACKER",
    "PIP_REQ_TRACKER",
)


def _get_pip_verbosity():
    """Detect pip's verbosity level from environment.

    pip maps ``-v`` / ``--verbose`` flags to the ``PIP_VERBOSE``
    environment variable (standard pip config-via-env convention).
    Returns 0 when quiet, 1+ for increasing verbosity.
    """
    try:
        return int(os.environ.get("PIP_VERBOSE", "0"))
    except ValueError:
        return 0


def _get_clean_env():
    """Return a copy of os.environ with pip's build-isolation variables removed.

    pip's isolated build sets PYTHONPATH and PYTHONNOUSERSITE to sandbox the
    build, which prevents subprocesses from finding packages (including pip
    itself) in the user's real environment.  Removing these lets the
    subprocess use the original conda/venv site-packages.
    """
    env = os.environ.copy()
    for var in _BUILD_ISOLATION_VARS:
        env.pop(var, None)
    return env


def _auto_install_annotated_packages():
    """Auto-install packages that need special pip flags (e.g. --no-build-isolation).

    These are excluded from extras_require because pip can't pass per-package flags.
    Assumes build dependencies (e.g. torch) are already installed in the environment.
    """
    verbose = _get_pip_verbosity()
    clean_env = _get_clean_env()

    if verbose:
        print("[flagscale] Auto-installing annotated packages...", file=sys.stderr)
        print(f"[flagscale]   verbosity level: {verbose}", file=sys.stderr)
        print(
            f"[flagscale]   cleaned env vars: {', '.join(_BUILD_ISOLATION_VARS)}", file=sys.stderr
        )

    seen = set()
    for extra_name, pkg_opts in sorted(PKG_OPTIONS.items()):
        for pkg, opts in pkg_opts.items():
            if pkg in seen:
                continue
            seen.add(pkg)
            pkg_name = pkg.split("@")[0].strip()
            opt_str = " ".join(opts)
            pip_opts = " ".join(PIP_OPTIONS.get(extra_name, []))
            cmd = ["pip", "install"]
            cmd.extend(opts)
            if verbose:
                cmd.append("-" + "v" * verbose)
            if pip_opts:
                cmd.extend(pip_opts.split())
            cmd.append(pkg)

            if verbose:
                print(f"[flagscale]   command: {' '.join(cmd)}", file=sys.stderr)
            else:
                print(f"[flagscale] Installing {pkg_name} with {opt_str}...", file=sys.stderr)

            rc = subprocess.call(cmd, env=clean_env)
            if rc != 0:
                full_opts = f"{opt_str} {pip_opts}".strip()
                print(
                    f"[flagscale] Warning: auto-install of {pkg_name} failed (exit {rc}).",
                    file=sys.stderr,
                )
                print(
                    f'[flagscale] Install manually: pip install {full_opts} "{pkg}"',
                    file=sys.stderr,
                )


# Only auto-install when setup.py is executed directly (pip install, python setup.py ...),
# not when imported by tests or other modules.
if PKG_OPTIONS and __name__ == "__main__":
    _auto_install_annotated_packages()
