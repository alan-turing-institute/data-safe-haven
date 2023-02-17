from typing import Optional

from .api.application import Application as BaseApplication
from .api.args.raw_args import RawArgs
from .api.config.application_config import ApplicationConfig
from .api.io import InputStream, OutputStream

class ConsoleApplication(BaseApplication):
    def __init__(self, config: ApplicationConfig) -> None: ...
    def run(
        self,
        args: Optional[RawArgs],
        input_stream: Optional[InputStream],
        output_stream: Optional[OutputStream],
        error_stream: Optional[OutputStream],
    ) -> int: ...
