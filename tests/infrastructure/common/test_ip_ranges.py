from data_safe_haven.external import AzureIPv4Range
from data_safe_haven.infrastructure.common import SREDnsIpRanges, SREIpRanges


class TestSREIpRanges:

    def test_vnet_and_subnets(self):
        assert SREIpRanges.vnet == AzureIPv4Range("10.0.0.0", "10.0.255.255")
        assert SREIpRanges.application_gateway == AzureIPv4Range(
            "10.0.0.0", "10.0.0.255"
        )
        assert SREIpRanges.apt_proxy_server == AzureIPv4Range("10.0.1.0", "10.0.1.7")
        assert SREIpRanges.clamav_mirror == AzureIPv4Range("10.0.1.8", "10.0.1.15")
        assert SREIpRanges.data_configuration == AzureIPv4Range(
            "10.0.1.16", "10.0.1.23"
        )
        assert SREIpRanges.data_private == AzureIPv4Range("10.0.1.24", "10.0.1.31")
        assert SREIpRanges.desired_state == AzureIPv4Range("10.0.1.32", "10.0.1.39")
        assert SREIpRanges.firewall == AzureIPv4Range("10.0.1.64", "10.0.1.127")
        assert SREIpRanges.firewall_management == AzureIPv4Range(
            "10.0.1.128", "10.0.1.191"
        )
        assert SREIpRanges.guacamole_containers == AzureIPv4Range(
            "10.0.1.40", "10.0.1.47"
        )
        assert SREIpRanges.guacamole_containers_support == AzureIPv4Range(
            "10.0.1.48", "10.0.1.55"
        )
        assert SREIpRanges.identity_containers == AzureIPv4Range(
            "10.0.1.56", "10.0.1.63"
        )
        assert SREIpRanges.monitoring == AzureIPv4Range("10.0.1.192", "10.0.1.223")
        assert SREIpRanges.user_services_containers == AzureIPv4Range(
            "10.0.1.224", "10.0.1.231"
        )
        assert SREIpRanges.user_services_containers_support == AzureIPv4Range(
            "10.0.1.232", "10.0.1.239"
        )
        assert SREIpRanges.user_services_databases == AzureIPv4Range(
            "10.0.1.240", "10.0.1.247"
        )
        assert SREIpRanges.user_services_software_repositories == AzureIPv4Range(
            "10.0.1.248", "10.0.1.255"
        )
        assert SREIpRanges.workspaces == AzureIPv4Range("10.0.2.0", "10.0.2.255")


class TestSREDnsIpRanges:
    def test_vnet(self):
        assert SREDnsIpRanges.vnet == AzureIPv4Range("192.168.0.0", "192.168.0.7")
