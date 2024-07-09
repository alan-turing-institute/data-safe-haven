from dataclasses import dataclass


@dataclass
class DockerHubCredentials:
    access_token: str
    server: str
    username: str
