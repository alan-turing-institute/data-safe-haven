# Standard library imports
from typing import Any, Dict, List, Union

# Third party imports
from dotmap import DotMap

ConfigType = Union[str, DotMap]
JSONType = Union[str, int, float, bool, None, Dict[str, Any], List[Any]]

