from enum import Enum


class SoftwarePackageCategory(str, Enum):
    ANY = "any"
    PRE_APPROVED = "pre-approved"
    NONE = "none"
