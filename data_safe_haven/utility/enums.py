from enum import Enum


class DatabaseSystem(str, Enum):
    POSTGRESQL = "postgresql"


class SoftwarePackageCategory(str, Enum):
    ANY = "any"
    PRE_APPROVED = "pre-approved"
    NONE = "none"
