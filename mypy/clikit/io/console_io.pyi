from typing import Optional

from clikit.api.io import IO, Input, Output

class ConsoleIO(IO):
    def __init__(
        self,
        input: Optional[Input],
        output: Optional[Output],
        error_output: Optional[Output],
    ) -> None: ...
