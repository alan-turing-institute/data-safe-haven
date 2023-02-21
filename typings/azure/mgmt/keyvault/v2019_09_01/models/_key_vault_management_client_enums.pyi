class CertificatePermissions:
    ALL: str
    GET: str
    LIST: str
    DELETE: str
    CREATE: str
    IMPORT_ENUM: str
    UPDATE: str
    MANAGECONTACTS: str
    GETISSUERS: str
    LISTISSUERS: str
    SETISSUERS: str
    DELETEISSUERS: str
    MANAGEISSUERS: str
    RECOVER: str
    PURGE: str
    BACKUP: str
    RESTORE: str

class CreateMode:
    RECOVER: str
    DEFAULT: str

class KeyPermissions:
    ALL: str
    ENCRYPT: str
    DECRYPT: str
    WRAP_KEY: str
    UNWRAP_KEY: str
    SIGN: str
    VERIFY: str
    GET: str
    LIST: str
    CREATE: str
    UPDATE: str
    IMPORT_ENUM: str
    DELETE: str
    BACKUP: str
    RESTORE: str
    RECOVER: str
    PURGE: str

class NetworkRuleAction:
    ALLOW: str
    DENY: str

class NetworkRuleBypassOptions:
    AZURE_SERVICES: str
    NONE: str

class SecretPermissions:
    ALL: str
    GET: str
    LIST: str
    SET: str
    DELETE: str
    BACKUP: str
    RESTORE: str
    RECOVER: str
    PURGE: str

class SkuFamily:
    A: str

class SkuName:
    STANDARD: str
    PREMIUM: str

class StoragePermissions:
    ALL: str
    GET: str
    LIST: str
    DELETE: str
    SET: str
    UPDATE: str
    REGENERATEKEY: str
    RECOVER: str
    PURGE: str
    BACKUP: str
    RESTORE: str
    SETSAS: str
    LISTSAS: str
    GETSAS: str
    DELETESAS: str

class VaultProvisioningState:
    SUCCEEDED: str
    REGISTERING_DNS: str
