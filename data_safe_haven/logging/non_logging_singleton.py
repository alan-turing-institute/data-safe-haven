import logging

from data_safe_haven.singleton import Singleton


class NonLoggingSingleton(logging.Logger, metaclass=Singleton):
    """
    Non-logging singleton that can be used by anything needing logs to be consumed
    """

    def __init__(self) -> None:
        super().__init__(name="non-logger", level=logging.CRITICAL + 10)
        while self.handlers:
            self.removeHandler(self.handlers[0])
