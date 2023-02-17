from typing import Optional

from clikit.api.application import Application
from clikit.api.args.raw_args import RawArgs
from clikit.api.config import ApplicationConfig
from clikit.api.io import IO, InputStream, OutputStream

class DefaultApplicationConfig(ApplicationConfig):
    def configure(self) -> None: ...
    def create_io(
        self,
        application: Application,
        args: RawArgs,
        input_stream: Optional[InputStream],
        output_stream: Optional[OutputStream],
        error_stream: Optional[OutputStream],
    ) -> IO: ...
