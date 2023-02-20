import io

from clikit.api.io.output_stream import OutputStream

class StreamOutputStream(OutputStream):
    def __init__(self, stream: io.TextIOWrapper) -> None: ...
