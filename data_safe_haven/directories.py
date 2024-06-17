from os import getenv
from pathlib import Path

import appdirs

_appname = "data_safe_haven"


def config_dir() -> Path:
    if config_directory_env := getenv("DSH_CONFIG_DIRECTORY"):
        config_directory = Path(config_directory_env).resolve()
    else:
        config_directory = Path(appdirs.user_config_dir(appname=_appname)).resolve()

    return config_directory


def log_dir() -> Path:
    if log_directory_env := getenv("DSH_LOG_DIRECTORY"):
        log_directory = Path(log_directory_env).resolve()
    else:
        log_directory = Path(appdirs.user_log_dir(appname=_appname)).resolve()
        log_directory.mkdir(parents=True, exist_ok=True)

    return log_directory
