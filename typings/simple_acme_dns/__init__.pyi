from typing import List, Optional, Tuple
from _typeshed import Incomplete

class ACMEClient:
    domains: List[str]
    email: str
    directory: str
    certificate: str
    private_key: bytes
    csr: bytes
    verification_tokens: List[Incomplete]
    account_key: Incomplete
    account: Incomplete
    account_path: Incomplete
    nameservers: Incomplete
    def __init__(
        self,
        domains: Optional[List[str]] = ...,
        email: Optional[str] = ...,
        directory: Optional[str] = ...,
        nameservers: Optional[List[str]] = ...,
        new_account: Optional[bool] = ...,
        generate_csr: Optional[bool] = ...,
    ) -> None: ...
    def generate_csr(self) -> bytes: ...
    def generate_private_key(self, key_type: str = ...) -> bytes: ...
    def generate_private_key_and_csr(
        self, key_type: str = ...
    ) -> Tuple[bytes, bytes]: ...
    def request_verification_tokens(self) -> List[Tuple[str, str]]: ...
    def request_certificate(self, wait: int = ..., timeout: int = ...) -> bytes: ...
    def revoke_certificate(self, reason: int = ...) -> None: ...
    def new_account(self) -> None: ...
    def deactivate_account(self, delete: bool = ...) -> None: ...
    def export_account(
        self, save_certificate: bool = ..., save_private_key: bool = ...
    ) -> str: ...
    def export_account_to_file(
        self,
        path: str = ...,
        name: str = ...,
        save_certificate: bool = ...,
        save_private_key: bool = ...,
    ) -> None: ...
    @staticmethod
    def load_account(json_data: str) -> ACMEClient: ...
    @staticmethod
    def load_account_from_file(filepath: str) -> ACMEClient: ...
    def check_dns_propagation(
        self,
        timeout: int = ...,
        interval: int = ...,
        authoritative: bool = ...,
        round_robin: bool = ...,
        verbose: bool = ...,
    ) -> bool: ...
