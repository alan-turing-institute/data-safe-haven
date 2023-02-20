from _typeshed import Incomplete

class ChallengeUnavailable(Exception):
    message: Incomplete
    def __init__(self, message: str) -> None: ...

class InvalidKeyType(Exception):
    message: Incomplete
    def __init__(self, message: str) -> None: ...

class InvalidPrivateKey(Exception):
    message: Incomplete
    def __init__(self, message) -> None: ...

class InvalidCertificate(Exception):
    message: Incomplete
    def __init__(self, message: str) -> None: ...

class InvalidAccount(Exception):
    message: Incomplete
    def __init__(self, message: str) -> None: ...

class InvalidEmail(Exception):
    message: Incomplete
    def __init__(self, message: str) -> None: ...

class InvalidVerificationToken(Exception):
    message: Incomplete
    def __init__(self, message: str) -> None: ...

class InvalidDomain(Exception):
    message: Incomplete
    def __init__(self, message: str) -> None: ...

class InvalidACMEDirectoryURL(Exception):
    message: Incomplete
    def __init__(self, message: str) -> None: ...

class InvalidPath(Exception):
    message: Incomplete
    def __init__(self, message: str) -> None: ...

class ACMETimeout(Exception):
    message: Incomplete
    def __init__(self, message: str) -> None: ...
