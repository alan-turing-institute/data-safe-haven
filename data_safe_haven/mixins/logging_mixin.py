import datetime
from cleo.io import ConsoleIO
from clikit.api.io.flags import NORMAL, DEBUG, VERBOSE


class LoggingMixin:
    def __init__(self, *args, **kwargs):
        self.fallback_io = ConsoleIO()
        super().__init__(*args, **kwargs)

    @property
    def prefix(self):
        return f"<fg=blue>[{datetime.datetime.now().isoformat(timespec='seconds')}]</>"

    def debug(self, message):
        self.log(f"{self.prefix} {message}", DEBUG)

    def error(self, message):
        self.log(f"{self.prefix} <error>{message}</error>", NORMAL)

    def info(self, message):
        self.log(f"{self.prefix} {message}", NORMAL)

    def verbose(self, message):
        self.log(f"{self.prefix} {message}", VERBOSE)

    def warning(self, message):
        self.log(f"{self.prefix} <warning>{message}</warning>", NORMAL)

    def log(self, message, verbosity):
        if hasattr(self, "line"):
            self.line(message, verbosity=verbosity)
        else:
            self.fallback_io.write_line(message, verbosity)
