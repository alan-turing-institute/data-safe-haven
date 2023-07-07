from enum import Enum


class SoftwarePackageCategory(str, Enum):
    any = "any"
    pre_approved = "pre-approved"
    none = "none"
