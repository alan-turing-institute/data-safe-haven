class DataSafeHavenException(Exception):
    pass


class DataSafeHavenCloudException(DataSafeHavenException):
    pass


class DataSafeHavenInputException(DataSafeHavenException):
    pass


class DataSafeHavenInternalException(DataSafeHavenException):
    pass


class DataSafeHavenAzureException(DataSafeHavenCloudException):
    pass


class DataSafeHavenUserHandlingException(DataSafeHavenInternalException):
    pass


class DataSafeHavenMicrosoftGraphException(DataSafeHavenAzureException):
    pass


class DataSafeHavenPulumiException(DataSafeHavenCloudException):
    pass
