"""Read local files, handling template expansion if needed"""
# Standard library imports
import pathlib

# Third party imports
import chevron

# Local imports
from data_safe_haven.mixins import LoggingMixin
from pulumi import Output


class FileReader(LoggingMixin):
    """Read local files, handling template expansion if needed"""

    def __init__(self, file_path, *args, **kwargs):
        self.file_path = pathlib.Path(file_path).resolve()
        super().__init__(*args, **kwargs)

    @property
    def name(self):
        return self.file_path.name.replace(".mustache", "")

    def file_contents(self, mustache_values=None):
        """Read a local file into a string, expanding template values"""
        with open(self.file_path, "r") as source_file:
            if mustache_values:
                contents = chevron.render(source_file, mustache_values)
            else:
                contents = source_file.read()
        return contents

    def file_contents_secret(self, mustache_values=None):
        """Read local file contents into a pulumi secret."""
        return Output.secret(self.file_contents(mustache_values))
