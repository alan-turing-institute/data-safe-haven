from enum import UNIQUE, Enum, verify


@verify(UNIQUE)
class DatabaseSystem(str, Enum):
    MICROSOFT_SQL_SERVER = "mssql"
    POSTGRESQL = "postgresql"


@verify(UNIQUE)
class SoftwarePackageCategory(str, Enum):
    ANY = "any"
    PRE_APPROVED = "pre-approved"
    NONE = "none"
