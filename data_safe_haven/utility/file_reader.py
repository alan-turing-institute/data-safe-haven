"""Read local files, handling template expansion if needed"""
# Standard library imports
import pathlib
from typing import Any, Dict, Optional

# Third party imports
import chevron

# Local imports
from data_safe_haven.functions import sha256hash
from .types import PathType


class FileReader:
    """Read local files, handling template expansion if needed"""

    def __init__(self, file_path: PathType, *args: Any, **kwargs: Any):
        self.file_path = pathlib.Path(file_path).resolve()
        super().__init__(*args, **kwargs)

    @property
    def name(self) -> str:
        return self.file_path.name.replace(".mustache", "")

    def file_contents(self, mustache_values: Optional[Dict[str, Any]] = None) -> str:
        """Read a local file into a string, expanding template values"""
        with open(self.file_path, "r", encoding="utf-8") as source_file:
            if mustache_values:
                contents = chevron.render(source_file, mustache_values)
            else:
                contents = source_file.read()
        return contents

    def sha256(self) -> str:
        return sha256hash(self.file_contents())
