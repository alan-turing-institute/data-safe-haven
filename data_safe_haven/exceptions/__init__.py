from data_safe_haven.logging import get_logger


class DataSafeHavenError(Exception):
    def __init__(self, message: str | bytes):
        super().__init__(message)

        # Log exception message as an error
        logger = get_logger()
        # Pad additional lines with spaces to ensure they line-up
        padding = " " * 34  # date (10) + 1 + time (12) + 3 + log_level (5) + 3
        message_str = message if isinstance(message, str) else message.decode("utf-8")
        logger.error(message_str.replace("\n", f"\n{padding}"))


class DataSafeHavenCloudError(DataSafeHavenError):
    pass


class DataSafeHavenConfigError(DataSafeHavenError):
    pass


class DataSafeHavenEntraIDError(DataSafeHavenCloudError):
    pass


class DataSafeHavenInputError(DataSafeHavenError):
    pass


class DataSafeHavenInternalError(DataSafeHavenError):
    pass


class DataSafeHavenIPRangeError(DataSafeHavenError):
    pass


class DataSafeHavenNotImplementedError(DataSafeHavenInternalError):
    pass


class DataSafeHavenParameterError(DataSafeHavenError):
    pass


class DataSafeHavenSSLError(DataSafeHavenError):
    pass


class DataSafeHavenAzureError(DataSafeHavenCloudError):
    pass


class DataSafeHavenAzureAPIError(DataSafeHavenError):
    pass


class DataSafeHavenAzureAPIAuthenticationError(DataSafeHavenAzureAPIError):
    pass


class DataSafeHavenUserHandlingError(DataSafeHavenInternalError):
    pass


class DataSafeHavenMicrosoftGraphError(DataSafeHavenAzureError):
    pass


class DataSafeHavenPulumiError(DataSafeHavenCloudError):
    pass
