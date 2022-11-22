# Standard library imports
from pathlib import Path
from typing import Any, Dict, List, Union

# Third party imports
from dotmap import DotMap

ConfigType = Union[str, DotMap]
PathType = Union[str, Path]
JSONType = Union[str, int, float, bool, None, Dict[str, Any], List[Any]]
