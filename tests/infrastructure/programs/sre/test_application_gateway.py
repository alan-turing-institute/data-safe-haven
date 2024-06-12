from functools import partial

import pulumi
import pytest
from pulumi_azure_native import network

from data_safe_haven.infrastructure.programs.sre.application_gateway import (
    SREApplicationGatewayComponent,
    SREApplicationGatewayProps,
)

from ..resource_assertions import assert_equal, assert_equal_json


@pytest.fixture
def application_gateway_props(
    identity_key_vault_reader,
    resource_group,
    sre_fqdn,
    subnet_application_gateway,
    subnet_guacamole_containers,
) -> SREApplicationGatewayProps:
    return SREApplicationGatewayProps(
        key_vault_certificate_id="key_vault_certificate_id",
        key_vault_identity=identity_key_vault_reader,
        resource_group=resource_group,
        sre_fqdn=sre_fqdn,
        subnet_application_gateway=subnet_application_gateway,
        subnet_guacamole_containers=subnet_guacamole_containers,
    )


@pytest.fixture
def application_gateway_component(
    application_gateway_props,
    stack_name,
    tags,
) -> SREApplicationGatewayComponent:
    return SREApplicationGatewayComponent(
        name="ag-name",
        stack_name=stack_name,
        props=application_gateway_props,
        tags=tags,
    )


class TestSREApplicationGatewayProps:
    @pulumi.runtime.test
    def test_props(self, application_gateway_props: SREApplicationGatewayProps):
        assert isinstance(application_gateway_props, SREApplicationGatewayProps)

    @pulumi.runtime.test
    def test_props_key_vault_certificate_id(
        self, application_gateway_props: SREApplicationGatewayProps
    ):
        pulumi.Output.from_input(
            application_gateway_props.key_vault_certificate_id
        ).apply(
            partial(assert_equal, "key_vault_certificate_id"),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_props_resource_group_id(
        self, application_gateway_props: SREApplicationGatewayProps
    ):
        application_gateway_props.resource_group_id.apply(
            partial(assert_equal, pulumi.UNKNOWN),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_props_resource_group_name(
        self, application_gateway_props: SREApplicationGatewayProps
    ):
        application_gateway_props.resource_group_name.apply(
            partial(assert_equal, "None"),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_props_sre_fqdn(
        self, application_gateway_props: SREApplicationGatewayProps, sre_fqdn
    ):
        pulumi.Output.from_input(application_gateway_props.sre_fqdn).apply(
            partial(assert_equal, sre_fqdn),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_props_subnet_application_gateway_id(
        self, application_gateway_props: SREApplicationGatewayProps
    ):
        application_gateway_props.subnet_application_gateway_id.apply(
            partial(assert_equal, "subnet_application_gateway_id"),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_props_subnet_guacamole_containers_ip_addresses(
        self, application_gateway_props: SREApplicationGatewayProps
    ):
        application_gateway_props.subnet_guacamole_containers_ip_addresses.apply(
            partial(assert_equal, ["10.0.1.28", "10.0.1.29", "10.0.1.30"]),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_props_user_assigned_identities(
        self, application_gateway_props: SREApplicationGatewayProps
    ):
        application_gateway_props.user_assigned_identities.apply(
            partial(assert_equal, pulumi.UNKNOWN),
            run_with_unknowns=True,
        )


class TestSREApplicationGatewayComponent:
    @pulumi.runtime.test
    def test_application_gateway(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        assert isinstance(
            application_gateway_component.application_gateway,
            network.ApplicationGateway,
        )

    @pulumi.runtime.test
    def test_application_gateway_authentication_certificates(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.authentication_certificates.apply(
            partial(assert_equal, None),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_autoscale_configuration(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.autoscale_configuration.apply(
            partial(assert_equal, None),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_backend_address_pools(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.backend_address_pools.apply(
            partial(
                assert_equal_json,
                [
                    {
                        "backend_ip_configurations": None,
                        "etag": None,
                        "provisioning_state": None,
                        "type": None,
                        "backend_addresses": [
                            {"ip_address": "10.0.1.28"},
                            {"ip_address": "10.0.1.29"},
                            {"ip_address": "10.0.1.30"},
                        ],
                        "name": "appGatewayBackendGuacamole",
                    }
                ],
            ),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_backend_http_settings_collection(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.backend_http_settings_collection.apply(
            partial(
                assert_equal_json,
                [
                    {
                        "etag": None,
                        "provisioning_state": None,
                        "type": None,
                        "cookie_based_affinity": "Enabled",
                        "name": "appGatewayBackendHttpSettings",
                        "port": 80,
                        "protocol": "Http",
                        "request_timeout": 30,
                    }
                ],
            ),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_backend_settings_collection(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.backend_settings_collection.apply(
            partial(assert_equal, None),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_custom_error_configurations(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.custom_error_configurations.apply(
            partial(assert_equal, None),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_default_predefined_ssl_policy(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.default_predefined_ssl_policy.apply(
            partial(assert_equal, None),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_enable_fips(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.enable_fips.apply(
            partial(assert_equal, None),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_enable_http2(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.enable_http2.apply(
            partial(assert_equal, None),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_etag(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.etag.apply(
            partial(assert_equal, None),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_firewall_policy(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.firewall_policy.apply(
            partial(assert_equal, None),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_force_firewall_policy_association(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.force_firewall_policy_association.apply(
            partial(assert_equal, None),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_frontend_ip_configurations(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.frontend_ip_configurations.apply(
            partial(
                assert_equal_json,
                [
                    {
                        "etag": None,
                        "provisioning_state": None,
                        "type": None,
                        "name": "appGatewayFrontendIP",
                        "private_ip_allocation_method": "Dynamic",
                        "public_ip_address": {"id": None},
                    }
                ],
            ),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_frontend_ports(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.frontend_ports.apply(
            partial(
                assert_equal_json,
                [
                    {
                        "etag": None,
                        "provisioning_state": None,
                        "type": None,
                        "name": "appGatewayFrontendHttp",
                        "port": 80,
                    },
                    {
                        "etag": None,
                        "provisioning_state": None,
                        "type": None,
                        "name": "appGatewayFrontendHttps",
                        "port": 443,
                    },
                ],
            ),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_gateway_ip_configurations(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.gateway_ip_configurations.apply(
            partial(
                assert_equal_json,
                [
                    {
                        "etag": None,
                        "provisioning_state": None,
                        "type": None,
                        "name": "appGatewayIP",
                        "subnet": {"id": "subnet_application_gateway_id"},
                    }
                ],
            ),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_global_configuration(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.global_configuration.apply(
            partial(assert_equal, None),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_http_listeners(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.http_listeners.apply(
            partial(
                assert_equal_json,
                [
                    {
                        "etag": None,
                        "provisioning_state": None,
                        "type": None,
                        "frontend_ip_configuration": {"id": None},
                        "frontend_port": {"id": None},
                        "host_name": "sre.example.com",
                        "name": "GuacamoleHttpListener",
                        "protocol": "Http",
                    },
                    {
                        "etag": None,
                        "provisioning_state": None,
                        "type": None,
                        "frontend_ip_configuration": {"id": None},
                        "frontend_port": {"id": None},
                        "host_name": "sre.example.com",
                        "name": "GuacamoleHttpsListener",
                        "protocol": "Https",
                        "ssl_certificate": {"id": None},
                    },
                ],
            ),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_identity(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.identity.apply(
            partial(
                assert_equal_json,
                {"principal_id": None, "tenant_id": None, "type": "UserAssigned"},
            ),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_listeners(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.listeners.apply(
            partial(assert_equal, None),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_load_distribution_policies(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.load_distribution_policies.apply(
            partial(assert_equal, None),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_location(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.location.apply(
            partial(assert_equal, None),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_name(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.name.apply(
            partial(assert_equal, None),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_operational_state(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.operational_state.apply(
            partial(assert_equal, None),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_private_endpoint_connections(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.private_endpoint_connections.apply(
            partial(assert_equal, None),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_private_link_configurations(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.private_link_configurations.apply(
            partial(assert_equal, None),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_probes(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.probes.apply(
            partial(assert_equal, None),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_provisioning_state(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.provisioning_state.apply(
            partial(assert_equal, None),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_redirect_configurations(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.redirect_configurations.apply(
            partial(
                assert_equal_json,
                [
                    {
                        "etag": None,
                        "type": None,
                        "include_path": True,
                        "include_query_string": True,
                        "name": "GuacamoleHttpToHttpsRedirection",
                        "redirect_type": "Permanent",
                        "request_routing_rules": [{"id": None}],
                        "target_listener": {"id": None},
                    }
                ],
            ),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_request_routing_rules(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.request_routing_rules.apply(
            partial(
                assert_equal_json,
                [
                    {
                        "etag": None,
                        "provisioning_state": None,
                        "type": None,
                        "http_listener": {"id": None},
                        "name": "GuacamoleHttpRouting",
                        "priority": 200,
                        "redirect_configuration": {"id": None},
                        "rule_type": "Basic",
                    },
                    {
                        "etag": None,
                        "provisioning_state": None,
                        "type": None,
                        "backend_address_pool": {"id": None},
                        "backend_http_settings": {"id": None},
                        "http_listener": {"id": None},
                        "name": "GuacamoleHttpsRouting",
                        "priority": 100,
                        "rule_type": "Basic",
                    },
                ],
            ),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_resource_guid(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.resource_guid.apply(
            partial(assert_equal, None),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_rewrite_rule_sets(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.rewrite_rule_sets.apply(
            partial(assert_equal, None),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_routing_rules(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.routing_rules.apply(
            partial(assert_equal, None),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_sku(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.sku.apply(
            partial(
                assert_equal,
                network.outputs.ApplicationGatewaySkuResponse(
                    capacity=1,
                    name="Standard_v2",
                    tier="Standard_v2",
                ),
            ),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_ssl_certificates(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.ssl_certificates.apply(
            partial(
                assert_equal_json,
                [
                    {
                        "etag": None,
                        "provisioning_state": None,
                        "public_cert_data": None,
                        "type": None,
                        "key_vault_secret_id": "key_vault_certificate_id",
                        "name": "letsencryptcertificate",
                    }
                ],
            ),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_ssl_policy(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.ssl_policy.apply(
            partial(
                assert_equal_json,
                {
                    "cipher_suites": [
                        "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384",
                        "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384",
                        "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256",
                        "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256",
                    ],
                    "min_protocol_version": "TLSv1_2",
                    "policy_type": "CustomV2",
                },
            ),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_ssl_profiles(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.ssl_profiles.apply(
            partial(assert_equal, None),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_tags(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.tags.apply(
            partial(assert_equal, {"key": "value"}),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_trusted_client_certificates(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.trusted_client_certificates.apply(
            partial(assert_equal, None),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_type(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.type.apply(
            partial(assert_equal, None),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_url_path_maps(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.url_path_maps.apply(
            partial(assert_equal, None),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_web_application_firewall_configuration(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.web_application_firewall_configuration.apply(
            partial(assert_equal, None),
            run_with_unknowns=True,
        )

    @pulumi.runtime.test
    def test_application_gateway_zones(
        self, application_gateway_component: SREApplicationGatewayComponent
    ):
        application_gateway_component.application_gateway.zones.apply(
            partial(assert_equal, None),
            run_with_unknowns=True,
        )
