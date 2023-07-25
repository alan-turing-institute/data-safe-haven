"""Pulumi component for SRE application gateway"""
from typing import Any

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import managedidentity, network, resources

from data_safe_haven.pulumi.common.transformations import (
    get_available_ips_from_subnet,
    get_id_from_rg,
    get_id_from_subnet,
    get_name_from_rg,
)


class SREApplicationGatewayProps:
    """Properties for SREApplicationGatewayComponent"""

    user_assigned_identities: Output[dict[str, dict[Any, Any]]]

    def __init__(
        self,
        key_vault_certificate_id: Input[str],
        key_vault_identity: Input[managedidentity.UserAssignedIdentity],
        resource_group: Input[resources.ResourceGroup],
        sre_fqdn: Input[str],
        subnet_application_gateway: Input[network.GetSubnetResult],
        subnet_guacamole_containers: Input[network.GetSubnetResult],
    ):
        self.key_vault_certificate_id = key_vault_certificate_id
        self.resource_group_id = Output.from_input(resource_group).apply(get_id_from_rg)
        self.resource_group_name = Output.from_input(resource_group).apply(get_name_from_rg)
        self.sre_fqdn = sre_fqdn
        self.subnet_application_gateway_id = Output.from_input(subnet_application_gateway).apply(get_id_from_subnet)
        self.subnet_guacamole_containers_ip_addresses = Output.from_input(subnet_guacamole_containers).apply(
            get_available_ips_from_subnet
        )
        # Unwrap key vault identity so that it has the required type
        self.user_assigned_identities = Output.from_input(key_vault_identity).apply(
            lambda identity: identity.id.apply(lambda id_: {str(id_): {}})
        )


class SREApplicationGatewayComponent(ComponentResource):
    """Deploy application gateway with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SREApplicationGatewayProps,
        opts: ResourceOptions | None = None,
    ):
        super().__init__("dsh:sre:ApplicationGatewayComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(ResourceOptions(parent=self), opts)

        # Define public IP address
        public_ip = network.PublicIPAddress(
            f"{self._name}_public_ip",
            public_ip_address_name=f"{stack_name}-public-ip",
            public_ip_allocation_method=network.IpAllocationMethod.STATIC,
            resource_group_name=props.resource_group_name,
            sku=network.PublicIPAddressSkuArgs(name=network.PublicIPAddressSkuName.STANDARD),
            opts=child_opts,
        )

        # Link the public IP address to the SRE domain
        network.RecordSet(
            f"{self._name}_a_record",
            a_records=public_ip.ip_address.apply(lambda ip: [network.ARecordArgs(ipv4_address=ip)] if ip else []),
            record_type="A",
            relative_record_set_name="@",
            resource_group_name=props.resource_group_name,
            ttl=30,
            zone_name=props.sre_fqdn,
            opts=child_opts,
        )

        # Define application gateway
        application_gateway_name = f"{stack_name}-ag-entrypoint"
        network.ApplicationGateway(
            f"{self._name}_application_gateway",
            application_gateway_name=application_gateway_name,
            backend_address_pools=[
                # Guacamole private IP addresses
                network.ApplicationGatewayBackendAddressPoolArgs(
                    backend_addresses=props.subnet_guacamole_containers_ip_addresses.apply(
                        lambda ip_addresses: [
                            network.ApplicationGatewayBackendAddressArgs(ip_address=ip_address)
                            for ip_address in ip_addresses
                        ]
                    ),
                    name="appGatewayBackendGuacamole",
                ),
            ],
            backend_http_settings_collection=[
                network.ApplicationGatewayBackendHttpSettingsArgs(
                    name="appGatewayBackendHttpSettings",
                    port=80,
                    protocol="Http",
                    request_timeout=30,
                ),
            ],
            frontend_ip_configurations=[
                network.ApplicationGatewayFrontendIPConfigurationArgs(
                    name="appGatewayFrontendIP",
                    private_ip_allocation_method="Dynamic",
                    public_ip_address=network.SubResourceArgs(id=public_ip.id),
                )
            ],
            frontend_ports=[
                network.ApplicationGatewayFrontendPortArgs(
                    name="appGatewayFrontendHttp",
                    port=80,
                ),
                network.ApplicationGatewayFrontendPortArgs(
                    name="appGatewayFrontendHttps",
                    port=443,
                ),
            ],
            gateway_ip_configurations=[
                network.ApplicationGatewayIPConfigurationArgs(
                    name="appGatewayIP",
                    subnet=network.SubResourceArgs(id=props.subnet_application_gateway_id),
                )
            ],
            http_listeners=[
                # Guacamole listeners
                network.ApplicationGatewayHttpListenerArgs(
                    frontend_ip_configuration=network.SubResourceArgs(
                        id=Output.concat(
                            props.resource_group_id,
                            f"/providers/Microsoft.Network/applicationGateways/{application_gateway_name}/frontendIPConfigurations/appGatewayFrontendIP",
                        )
                    ),
                    frontend_port=network.SubResourceArgs(
                        id=Output.concat(
                            props.resource_group_id,
                            f"/providers/Microsoft.Network/applicationGateways/{application_gateway_name}/frontendPorts/appGatewayFrontendHttp",
                        )
                    ),
                    host_name=props.sre_fqdn,
                    name="GuacamoleHttpListener",
                    protocol="Http",
                ),
                network.ApplicationGatewayHttpListenerArgs(
                    frontend_ip_configuration=network.SubResourceArgs(
                        id=Output.concat(
                            props.resource_group_id,
                            f"/providers/Microsoft.Network/applicationGateways/{application_gateway_name}/frontendIPConfigurations/appGatewayFrontendIP",
                        )
                    ),
                    frontend_port=network.SubResourceArgs(
                        id=Output.concat(
                            props.resource_group_id,
                            f"/providers/Microsoft.Network/applicationGateways/{application_gateway_name}/frontendPorts/appGatewayFrontendHttps",
                        )
                    ),
                    host_name=props.sre_fqdn,
                    name="GuacamoleHttpsListener",
                    protocol="Https",
                    ssl_certificate=network.SubResourceArgs(
                        id=Output.concat(
                            props.resource_group_id,
                            f"/providers/Microsoft.Network/applicationGateways/{application_gateway_name}/sslCertificates/letsencryptcertificate",
                        ),
                    ),
                    ssl_profile=network.SubResourceArgs(
                        id=Output.concat(
                            props.resource_group_id,
                            f"/providers/Microsoft.Network/applicationGateways/{application_gateway_name}/sslProfiles/sslProfile",
                        ),
                    ),
                ),
            ],
            identity=network.ManagedServiceIdentityArgs(
                type=network.ResourceIdentityType.USER_ASSIGNED,
                user_assigned_identities=props.user_assigned_identities,
            ),
            redirect_configurations=[
                # Guacamole HTTP redirect
                network.ApplicationGatewayRedirectConfigurationArgs(
                    include_path=True,
                    include_query_string=True,
                    name="GuacamoleHttpToHttpsRedirection",
                    redirect_type="Permanent",
                    request_routing_rules=[
                        network.SubResourceArgs(
                            id=Output.concat(
                                props.resource_group_id,
                                f"/providers/Microsoft.Network/applicationGateways/{application_gateway_name}/requestRoutingRules/HttpToHttpsRedirection",
                            ),
                        )
                    ],
                    target_listener=network.SubResourceArgs(
                        id=Output.concat(
                            props.resource_group_id,
                            f"/providers/Microsoft.Network/applicationGateways/{application_gateway_name}/httpListeners/GuacamoleHttpsListener",
                        )
                    ),
                ),
            ],
            request_routing_rules=[
                # Guacamole routing
                network.ApplicationGatewayRequestRoutingRuleArgs(
                    http_listener=network.SubResourceArgs(
                        id=Output.concat(
                            props.resource_group_id,
                            f"/providers/Microsoft.Network/applicationGateways/{application_gateway_name}/httpListeners/GuacamoleHttpListener",
                        )
                    ),
                    redirect_configuration=network.SubResourceArgs(
                        id=Output.concat(
                            props.resource_group_id,
                            f"/providers/Microsoft.Network/applicationGateways/{application_gateway_name}/redirectConfigurations/GuacamoleHttpToHttpsRedirection",
                        )
                    ),
                    name="GuacamoleHttpRouting",
                    rule_type="Basic",
                ),
                network.ApplicationGatewayRequestRoutingRuleArgs(
                    backend_address_pool=network.SubResourceArgs(
                        id=Output.concat(
                            props.resource_group_id,
                            f"/providers/Microsoft.Network/applicationGateways/{application_gateway_name}/backendAddressPools/appGatewayBackendGuacamole",
                        )
                    ),
                    backend_http_settings=network.SubResourceArgs(
                        id=Output.concat(
                            props.resource_group_id,
                            f"/providers/Microsoft.Network/applicationGateways/{application_gateway_name}/backendHttpSettingsCollection/appGatewayBackendHttpSettings",
                        )
                    ),
                    http_listener=network.SubResourceArgs(
                        id=Output.concat(
                            props.resource_group_id,
                            f"/providers/Microsoft.Network/applicationGateways/{application_gateway_name}/httpListeners/GuacamoleHttpsListener",
                        )
                    ),
                    name="GuacamoleHttpsRouting",
                    rule_type="Basic",
                ),
            ],
            resource_group_name=props.resource_group_name,
            sku=network.ApplicationGatewaySkuArgs(
                capacity=1,
                name="Standard_v2",
                tier="Standard_v2",
            ),
            ssl_certificates=[
                network.ApplicationGatewaySslCertificateArgs(
                    key_vault_secret_id=props.key_vault_certificate_id,
                    name="letsencryptcertificate",
                ),
            ],
            ssl_profiles=[
                network.ApplicationGatewaySslProfileArgs(
                    client_auth_configuration=network.ApplicationGatewayClientAuthConfigurationArgs(
                        verify_client_cert_issuer_dn=True,
                    ),
                    name="sslProfile",
                    ssl_policy=network.ApplicationGatewaySslPolicyArgs(
                        # We take the ones recommended by SSL Labs
                        # (https://github.com/ssllabs/research/wiki/SSL-and-TLS-Deployment-Best-Practices)
                        # excluding any that are unsupported
                        cipher_suites=[
                            "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256",
                            "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384",
                            "TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA",
                            "TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA",
                            "TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256",
                            "TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA384",
                            "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256",
                            "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384",
                            "TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA",
                            "TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA",
                            "TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256",
                            "TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384",
                            "TLS_DHE_RSA_WITH_AES_128_GCM_SHA256",
                            "TLS_DHE_RSA_WITH_AES_256_GCM_SHA384",
                            "TLS_DHE_RSA_WITH_AES_128_CBC_SHA",
                            "TLS_DHE_RSA_WITH_AES_256_CBC_SHA",
                        ],
                        min_protocol_version="TLSv1_1",
                        policy_type="Custom",
                    ),
                )
            ],
            opts=child_opts,
        )
