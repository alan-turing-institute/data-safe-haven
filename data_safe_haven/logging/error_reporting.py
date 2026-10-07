"""Explicitly report Data Safe Haven errors at user-facing failure boundaries."""

from data_safe_haven.exceptions import DataSafeHavenError

from .logger import get_logger


def log_unhandled_dsh_exception(exc: DataSafeHavenError) -> None:
    """Log an unhandled DSH error and explicitly chained DSH causes.

    Constructing or catching an exception never logs it implicitly. Call this
    helper only when an operation will be reported as a failure (for example,
    immediately before returning a nonzero CLI exit status).
    """
    messages: list[str] = []
    seen: set[int] = set()
    current: BaseException | None = exc
    while isinstance(current, DataSafeHavenError) and id(current) not in seen:
        seen.add(id(current))
        raw_message = current.args[0] if current.args else ""
        if isinstance(raw_message, bytes):
            message = raw_message.decode("utf-8", errors="replace")
        else:
            message = str(current)
        if message:
            messages.append(message.replace("\n", r"\n"))
        current = current.__cause__

    logger = get_logger()
    for message in reversed(messages):
        logger.error("%s", message)
