from data_safe_haven.logging import get_logger


class DataSafeHavenError(Exception):
    """
    Parent class for all DataSafeHaven exceptions.

    This class is not intended to be instantiated directly. Developers should use one of the subclasses instead.
    """

    def __init__(self, message: str | bytes):
        super().__init__(message)

        # Log exception message as an error
        logger = get_logger()
        message_str = message if isinstance(message, str) else message.decode("utf-8")
        # Replace line breaks with escape code
        logger.error(message_str.replace("\n", r"\n"))


class DataSafeHavenAzureError(DataSafeHavenError):
    """
    Exception class for handling errors when interacting with Azure.

    For example, when creating resources in Azure fails.
    """

    pass


class DataSafeHavenAzureAPIAuthenticationError(DataSafeHavenAzureError):
    """
    Exception class for handling errors when authenticating against the Azure API

    Used to capture exceptions generated when the user is not authenticated or that the authentication has expired
    """

    pass


class DataSafeHavenConfigError(DataSafeHavenError):
    """
    Exception class for handling errors related to configuration files.

    Examples include missing configuration files or invalid configuration values.
    """

    pass


class DataSafeHavenEntraIDError(DataSafeHavenError):
    """
    Exception class for handling errors when interacting with Entra ID.

    For example, when adding users to an Entra group fails.
    """

    pass


class DataSafeHavenInputError(DataSafeHavenError):
    """
    Exception class for handling errors related to input validation

    Not used consistently, will be removed. Perhaps replace with ValueError
    """

    pass


class DataSafeHavenInternalError(DataSafeHavenError):
    """
    Exception class for handling internal errors

    Usage of this one seems inconsistent. Will be removed. Check subclasses first.
    """

    pass


class DataSafeHavenIPRangeError(DataSafeHavenError):
    """
    Exception class raised when it is not possible to generate a valid IPv4 range
    """

    pass

class DataSafeHavenMicrosoftGraphError(DataSafeHavenAzureError):
    """
    Exception class for handling errors when interacting with the Microsoft Graph API

    """

    pass


class DataSafeHavenParameterError(DataSafeHavenError):
    """
    Possibly replace with ValueError or TypeError. See also InputError - potentially merge.

    """

    pass

class DataSafeHavenPulumiError(DataSafeHavenError):
    """
    Exception class for handling errors when interacting with Pulumi

    For example, when a Pulumi operation such as a deployment fails
    """

    pass

class DataSafeHavenSSLError(DataSafeHavenError):
    """
    Exception class for handling errors related to administration of SSL certificates.

    For example, errors refreshing or creating SSL certificates
    """

    pass


class DataSafeHavenUserHandlingError(DataSafeHavenInternalError):
    """
    Exception class for handling errors related to user handling

    For example, when listing or registering users fails
    """

    pass
