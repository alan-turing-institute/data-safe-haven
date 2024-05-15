class DataSafeHavenError(Exception):
    """
    Parent class for all DataSafeHaven exceptions
    """

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
    """
    Exception class for handling errors related to input validation


    """

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
    Exception class for handling errors related to administration of SSL certificates

    For example, errors refreshing or creating SSL certificates
    """

    pass


class DataSafeHavenAzureError(DataSafeHavenCloudError):
    """
    Exception class for handling errors when interacting with Azure

    For example, when creating resources in Azure fails
    """

    pass


class DataSafeHavenUserHandlingError(DataSafeHavenInternalError):
    """
    Exception class for handling errors related to user handling

    For example, when listing or registering users fails
    """

    pass


class DataSafeHavenMicrosoftGraphError(DataSafeHavenAzureError):
    """
    Exception class for handling errors when interacting with the Microsoft Graph API

    """

    pass


class DataSafeHavenPulumiError(DataSafeHavenCloudError):
    """
    Exception class for handling errors when interacting with Pulumi

    For example, when a Pulumi operation such as a deployment fails
    """

    pass
