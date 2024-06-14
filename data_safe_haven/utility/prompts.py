from rich.prompt import Confirm

from .logger import LoggingSingleton


def confirm(message: str, *, default_to_yes: bool) -> bool:
    """Ask a user to confirm an action, formatted as a log message"""
    logger = LoggingSingleton()

    logger.debug(f"Prompting user to confirm '{message}'")
    response: bool = Confirm.ask(message, default=default_to_yes)
    response_text = "yes" if response else "no"
    logger.debug(f"User responded '{response_text}'")
    return response