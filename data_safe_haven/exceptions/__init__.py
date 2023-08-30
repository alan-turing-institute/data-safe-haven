class DataSafeHavenError(BaseException):
    pass


class DataSafeHavenCloudError(DataSafeHavenError):
    pass


class DataSafeHavenConfigError(DataSafeHavenError):
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


class DataSafeHavenUserHandlingError(DataSafeHavenInternalError):
    pass


class DataSafeHavenMicrosoftGraphError(DataSafeHavenAzureError):
    pass


class DataSafeHavenPulumiError(DataSafeHavenCloudError):
    pass


class DataSafeHavenActiveDirectoryError(DataSafeHavenCloudError):
    pass
