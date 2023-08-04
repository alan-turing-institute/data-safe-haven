from enum import Enum


class DatabaseSystem(str, Enum):
    MICROSOFT_SQL_SERVER = "mssql"
    POSTGRESQL = "postgresql"


class SoftwarePackageCategory(str, Enum):
    ANY = "any"
    PRE_APPROVED = "pre-approved"
    NONE = "none"
