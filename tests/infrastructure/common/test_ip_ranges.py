import pytest

from data_safe_haven.exceptions import DataSafeHavenParameterError
from data_safe_haven.external import AzureIPv4Range
from data_safe_haven.infrastructure.common import SREIpRanges


class TestSREIpRanges:

    def test_invalid_low_index(self):
        with pytest.raises(DataSafeHavenParameterError) as exc_info:
            SREIpRanges(-1)
        assert exc_info.match("Index '-1' must be between 1 and 256")

    def test_invalid_high_index(self):
        with pytest.raises(DataSafeHavenParameterError) as exc_info:
            SREIpRanges(999)
        assert exc_info.match("Index '999' must be between 1 and 256")

    def test_vnet_and_subnets(self):
        ips = SREIpRanges(5)
        assert ips.vnet == AzureIPv4Range("10.5.0.0", "10.5.255.255")
        assert ips.application_gateway == AzureIPv4Range("10.5.0.0", "10.5.0.255")
        assert ips.apt_proxy_server == AzureIPv4Range("10.5.1.0", "10.5.1.7")
        assert ips.data_configuration == AzureIPv4Range("10.5.1.8", "10.5.1.15")
        assert ips.data_private == AzureIPv4Range("10.5.1.16", "10.5.1.23")
        assert ips.firewall == AzureIPv4Range("10.5.1.64", "10.5.1.127")
        assert ips.firewall_management == AzureIPv4Range("10.5.1.128", "10.5.1.191")
        assert ips.guacamole_containers == AzureIPv4Range("10.5.1.24", "10.5.1.31")
        assert ips.guacamole_containers_support == AzureIPv4Range(
            "10.5.1.32", "10.5.1.39"
        )
        assert ips.identity_containers == AzureIPv4Range("10.5.1.40", "10.5.1.47")
        assert ips.user_services_containers == AzureIPv4Range("10.5.1.48", "10.5.1.55")
        assert ips.user_services_containers_support == AzureIPv4Range(
            "10.5.1.56", "10.5.1.63"
        )
        assert ips.user_services_databases == AzureIPv4Range("10.5.1.192", "10.5.1.199")
        assert ips.user_services_software_repositories == AzureIPv4Range(
            "10.5.1.200", "10.5.1.207"
        )
        assert ips.workspaces == AzureIPv4Range("10.5.2.0", "10.5.2.255")
