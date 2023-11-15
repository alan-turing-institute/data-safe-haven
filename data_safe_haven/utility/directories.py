from os import getenv
from pathlib import Path

import appdirs


def config_dir() -> Path:
    if config_directory_env := getenv("DSH_CONFIG_DIRECTORY"):
        config_directory = Path(config_directory_env).resolve()
    else:
        config_directory = Path(
            appdirs.user_config_dir(appname="data_safe_haven")
        ).resolve()

    return config_directory
