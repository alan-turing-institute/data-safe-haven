import pytest
import requests

from data_safe_haven.exceptions import DataSafeHavenValueError
from data_safe_haven.functions import current_ip_address


class TestCurrentIpAddress:
    def test_current_ip_address(self, requests_mock):
        requests_mock.get("https://api.ipify.org", text="1.2.3.4")
        ip_address = current_ip_address()
        assert ip_address == "1.2.3.4"

    def test_current_ip_address_as_cidr(self, requests_mock):
        requests_mock.get("https://api.ipify.org", text="1.2.3.4")
        ip_address = current_ip_address(as_cidr=True)
        assert ip_address == "1.2.3.4/32"

    def test_current_ip_address_timeout(self, requests_mock):
        requests_mock.get(
            "https://api.ipify.org", exc=requests.exceptions.ConnectTimeout
        )
        with pytest.raises(DataSafeHavenValueError) as exc_info:
            current_ip_address()
        assert exc_info.match(r"Could not determine IP address.")
