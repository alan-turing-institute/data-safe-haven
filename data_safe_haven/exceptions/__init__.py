class DataSafeHavenException(Exception):
    pass


class DataSafeHavenCloudException(DataSafeHavenException):
    pass


class DataSafeHavenConfigException(DataSafeHavenException):
    pass


class DataSafeHavenInputException(DataSafeHavenException):
    pass


class DataSafeHavenInternalException(DataSafeHavenException):
    pass


class DataSafeHavenIPRangeException(DataSafeHavenException):
    pass


class DataSafeHavenNotImplementedException(DataSafeHavenInternalException):
    pass


class DataSafeHavenSSLException(DataSafeHavenException):
    pass


class DataSafeHavenAzureException(DataSafeHavenCloudException):
    pass


class DataSafeHavenUserHandlingException(DataSafeHavenInternalException):
    pass


class DataSafeHavenMicrosoftGraphException(DataSafeHavenAzureException):
    pass


class DataSafeHavenPulumiException(DataSafeHavenCloudException):
    pass
