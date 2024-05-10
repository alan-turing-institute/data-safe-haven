class DataSafeHavenError(Exception):
    pass


class DataSafeHavenCloudError(DataSafeHavenError):
    """
    Exception class for handling errors when interacting with the cloud.
    This is a parent class for the cloud-related exception classes
    `DataSafeHavenAzureError`, `DataSafeHavenEntraIDError` and
    `DataSafeHavenPulumiError`.
    """

    pass


class DataSafeHavenConfigError(DataSafeHavenError):
    """
    Exception class for handling errors related to configuration files.
    Examples include missing configuration files or invalid configuration values.
    """

    pass


class DataSafeHavenEntraIDError(DataSafeHavenCloudError):
    """
    Exception class for handling errors when interacting with Entra ID.
    For example, when adding users to an Entra group fails.
    """

    pass


class DataSafeHavenInputError(DataSafeHavenError):
    pass


class DataSafeHavenInternalError(DataSafeHavenError):
    pass


class DataSafeHavenIPRangeError(DataSafeHavenError):
    """
    Exception class for errors relating to the generation of IP ranges during SRE creation
    """

    pass


class DataSafeHavenNotImplementedError(DataSafeHavenInternalError):
    pass


class DataSafeHavenParameterError(DataSafeHavenError):
    pass


class DataSafeHavenSSLError(DataSafeHavenError):
    """
    Exception class for handling errors related to administration of SSL certificates.
    E.g. errors refreshing or creating SSL certificates

    """

    pass


class DataSafeHavenAzureError(DataSafeHavenCloudError):
    """
    Exception class for handling errors when interacting with Azure.
    For example
    """
    pass


class DataSafeHavenUserHandlingError(DataSafeHavenInternalError):
    pass


class DataSafeHavenMicrosoftGraphError(DataSafeHavenAzureError):
    pass


class DataSafeHavenPulumiError(DataSafeHavenCloudError):
    pass
