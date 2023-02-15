"""Pulumi component for SRE application gateway"""
# Standard library imports
from typing import Optional

# Third party imports
from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import managedidentity, network, resources

# Local imports
from data_safe_haven.external.interface import AzureIPv4Range


class SREApplicationGatewayProps:
    """Properties for SREApplicationGatewayComponent"""

    def __init__(
        self,
        ip_address_public_id: Input[str],
        ip_addresses_guacamole: Input[Sequence[str]],
        key_vault_certificate_id: Input[str],
        key_vault_identity: Input[str],
        resource_group_name: Input[str],
        sre_fqdn: Input[str],
        subnet_name: Input[str],
        virtual_network_name: Input[str],
    ):
        self.key_vault_certificate_id = key_vault_certificate_id
        self.ip_address_public_id = ip_address_public_id
        self.ip_addresses_guacamole = ip_addresses_guacamole
        self.resource_group_name = resource_group_name
        self.sre_fqdn = sre_fqdn
        self.subnet_name = subnet_name
        self.virtual_network_name = virtual_network_name
        # Unwrap key vault identity so that it has type Output[dict(str, Any)] not dict(Output[str], Any)
        self.user_assigned_identities = Output.from_input(key_vault_identity).apply(
            lambda identity: {identity: {}}
        )


class SREApplicationGatewayComponent(ComponentResource):
    """Deploy application gateway with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        sre_name: str,
        props: SREApplicationGatewayProps,
        opts: Optional[ResourceOptions] = None,
    ):
        super().__init__("dsh:sre:ApplicationGatewayComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(ResourceOptions(parent=self), opts)

        # Retrieve existing resource group and subnet
        resource_group = Output.from_input(props.resource_group_name).apply(
            lambda n: resources.get_resource_group(n)
        )
        snet_application_gateway = network.get_subnet_output(
            subnet_name="ApplicationGatewaySubnet",
            resource_group_name=props.resource_group_name,
            virtual_network_name=props.virtual_network_name,
        )

        # Define application gateway
        application_gateway_name = f"ag-{stack_name}-entrypoint"
        application_gateway = network.ApplicationGateway(
            f"{self._name}_application_gateway",
            application_gateway_name=application_gateway_name,
            backend_address_pools=[
                # Guacamole private IP address
                network.ApplicationGatewayBackendAddressPoolArgs(
                    backend_addresses=props.ip_addresses_guacamole.apply(
                        lambda ip_addresses: [
                            network.ApplicationGatewayBackendAddressArgs(
                                ip_address=ip_address
                            )
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
                    public_ip_address=network.SubResourceArgs(
                        id=props.ip_address_public_id
                    ),
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
                    subnet=network.SubResourceArgs(id=snet_application_gateway.id),
                )
            ],
            http_listeners=[
                # Guacamole listeners
                network.ApplicationGatewayHttpListenerArgs(
                    frontend_ip_configuration=network.SubResourceArgs(
                        id=Output.concat(
                            resource_group.id,
                            f"/providers/Microsoft.Network/applicationGateways/{application_gateway_name}/frontendIPConfigurations/appGatewayFrontendIP",
                        )
                    ),
                    frontend_port=network.SubResourceArgs(
                        id=Output.concat(
                            resource_group.id,
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
                            resource_group.id,
                            f"/providers/Microsoft.Network/applicationGateways/{application_gateway_name}/frontendIPConfigurations/appGatewayFrontendIP",
                        )
                    ),
                    frontend_port=network.SubResourceArgs(
                        id=Output.concat(
                            resource_group.id,
                            f"/providers/Microsoft.Network/applicationGateways/{application_gateway_name}/frontendPorts/appGatewayFrontendHttps",
                        )
                    ),
                    host_name=props.sre_fqdn,
                    name="GuacamoleHttpsListener",
                    protocol="Https",
                    ssl_certificate=network.SubResourceArgs(
                        id=Output.concat(
                            resource_group.id,
                            f"/providers/Microsoft.Network/applicationGateways/{application_gateway_name}/sslCertificates/letsencryptcertificate",
                        ),
                    ),
                    ssl_profile=network.SubResourceArgs(
                        id=Output.concat(
                            resource_group.id,
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
                                resource_group.id,
                                f"/providers/Microsoft.Network/applicationGateways/{application_gateway_name}/requestRoutingRules/HttpToHttpsRedirection",
                            ),
                        )
                    ],
                    target_listener=network.SubResourceArgs(
                        id=Output.concat(
                            resource_group.id,
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
                            resource_group.id,
                            f"/providers/Microsoft.Network/applicationGateways/{application_gateway_name}/httpListeners/GuacamoleHttpListener",
                        )
                    ),
                    redirect_configuration=network.SubResourceArgs(
                        id=Output.concat(
                            resource_group.id,
                            f"/providers/Microsoft.Network/applicationGateways/{application_gateway_name}/redirectConfigurations/GuacamoleHttpToHttpsRedirection",
                        )
                    ),
                    name="GuacamoleHttpRouting",
                    rule_type="Basic",
                ),
                network.ApplicationGatewayRequestRoutingRuleArgs(
                    backend_address_pool=network.SubResourceArgs(
                        id=Output.concat(
                            resource_group.id,
                            f"/providers/Microsoft.Network/applicationGateways/{application_gateway_name}/backendAddressPools/appGatewayBackendGuacamole",
                        )
                    ),
                    backend_http_settings=network.SubResourceArgs(
                        id=Output.concat(
                            resource_group.id,
                            f"/providers/Microsoft.Network/applicationGateways/{application_gateway_name}/backendHttpSettingsCollection/appGatewayBackendHttpSettings",
                        )
                    ),
                    http_listener=network.SubResourceArgs(
                        id=Output.concat(
                            resource_group.id,
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
                        # We take the ones recommended by SSL Labs (https://github.com/ssllabs/research/wiki/SSL-and-TLS-Deployment-Best-Practices) excluding any that are unsupported
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

        # Register outputs
        self.resource_group_name = Output.from_input(props.resource_group_name)
