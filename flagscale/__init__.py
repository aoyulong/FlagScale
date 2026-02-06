# Version is defined in pyproject.toml - keep in sync
__version__ = "1.0.0"

try:
    # When installed as a package, use importlib.metadata for accurate version
    from importlib.metadata import version as get_version

    __version__ = get_version("flagscale")
except Exception:
    pass  # Use hardcoded version above
