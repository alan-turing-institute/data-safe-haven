class DataSafeHavenException(Exception):
    pass


class DataSafeHavenCloudException(DataSafeHavenException):
    pass


class DataSafeHavenInputException(DataSafeHavenException):
    pass


class DataSafeHavenAzureException(DataSafeHavenCloudException):
    pass


class DataSafeHavenPulumiException(DataSafeHavenCloudException):
    pass
