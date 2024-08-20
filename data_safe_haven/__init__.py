"""Data Safe Haven"""

from .logging import init_logging
from .version import __version__, __version_info__

init_logging()

__all__ = ["__version__", "__version_info__"]
