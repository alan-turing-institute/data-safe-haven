from typing import Optional

from .config import Config

class ApplicationConfig(Config):
    def __init__(self, name: Optional[str], version: Optional[str]) -> None: ...
