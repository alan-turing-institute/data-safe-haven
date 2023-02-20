from azure.core.credentials import TokenCredential

class ChainedTokenCredential(object):
    def __init__(self, *credentials: TokenCredential) -> None: ...
