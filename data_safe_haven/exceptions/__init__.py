class DataSafeHavenError(Exception):
    pass


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


class DataSafeHavenAzureAPIError(DataSafeHavenAzureError):
    pass


class DataSafeHavenAzureAPIAuthenticationError(DataSafeHavenAzureAPIError):
    pass


class DataSafeHavenUserHandlingError(DataSafeHavenInternalError):
    pass


class DataSafeHavenMicrosoftGraphError(DataSafeHavenAzureError):
    pass


class DataSafeHavenPulumiError(DataSafeHavenCloudError):
    pass
