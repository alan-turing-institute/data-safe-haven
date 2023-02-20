from typing import Optional

from .api.application import Application as BaseApplication
from .api.args.raw_args import RawArgs
from .api.config.application_config import ApplicationConfig
from .api.io import InputStream, OutputStream

class ConsoleApplication(BaseApplication):
    def __init__(self, config: ApplicationConfig) -> None: ...
    def run(
        self,
        args: Optional[RawArgs] = None,
        input_stream: Optional[InputStream] = None,
        output_stream: Optional[OutputStream] = None,
        error_stream: Optional[OutputStream] = None,
    ) -> int: ...
