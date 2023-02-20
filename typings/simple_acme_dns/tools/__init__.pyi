from _typeshed import Incomplete

class DNSQuery:
    round_robin: Incomplete
    type: Incomplete
    domain: Incomplete
    nameservers: Incomplete
    values: Incomplete
    answers: Incomplete
    last_nameserver: str
    def __init__(
        self,
        domain: str,
        rtype: str = ...,
        nameservers: list = ...,
        authoritative: bool = ...,
        round_robin: bool = ...,
    ) -> None: ...
    def resolve(self) -> list: ...
    def __get_authoritative_nameservers__(self) -> list: ...
    @staticmethod
    def __resolve__(domain: str, rtype: str = ..., nameservers: list = ...) -> list: ...
    @staticmethod
    def __filter_list__(data: list) -> list: ...
    @staticmethod
    def __parse_values__(answers: list) -> list: ...
