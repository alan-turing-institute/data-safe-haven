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
    location,
    resource_group,
    sre_fqdn,
    subnet_application_gateway,
    subnet_guacamole_containers,
) -> SREApplicationGatewayProps:
    return SREApplicationGatewayProps(
        key_vault_certificate_id="key_vault_certificate_id",
        key_vault_identity=identity_key_vault_reader,
        location=location,
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
            partial(assert_equal, ["10.0.1.44", "10.0.1.45", "10.0.1.46"]),
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
                        "backend_addresses": [
                            {"ip_address": "10.0.1.44"},
                            {"ip_address": "10.0.1.45"},
                            {"ip_address": "10.0.1.46"},
                        ],
                        "backend_ip_configurations": None,
                        "etag": None,
                        "name": "appGatewayBackendGuacamole",
                        "provisioning_state": None,
                        "type": None,
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
                        "connection_draining": {
                            "drain_timeout_in_sec": 30,
                            "enabled": True,
                        },
                        "cookie_based_affinity": "Disabled",
                        "etag": None,
                        "name": "appGatewayBackendHttpSettings",
                        "port": 80,
                        "protocol": "Http",
                        "provisioning_state": None,
                        "request_timeout": 30,
                        "type": None,
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
                        "name": "appGatewayFrontendIP",
                        "private_ip_allocation_method": "Dynamic",
                        "provisioning_state": None,
                        "public_ip_address": {"id": None},
                        "type": None,
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
                        "name": "appGatewayFrontendHttp",
                        "port": 80,
                        "provisioning_state": None,
                        "type": None,
                    },
                    {
                        "etag": None,
                        "name": "appGatewayFrontendHttps",
                        "port": 443,
                        "provisioning_state": None,
                        "type": None,
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
                        "name": "appGatewayIP",
                        "provisioning_state": None,
                        "subnet": {"id": "subnet_application_gateway_id"},
                        "type": None,
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
                        "frontend_ip_configuration": {"id": None},
                        "frontend_port": {"id": None},
                        "host_name": "sre.example.com",
                        "name": "GuacamoleHttpListener",
                        "protocol": "Http",
                        "provisioning_state": None,
                        "type": None,
                    },
                    {
                        "etag": None,
                        "frontend_ip_configuration": {"id": None},
                        "frontend_port": {"id": None},
                        "host_name": "sre.example.com",
                        "name": "GuacamoleHttpsListener",
                        "protocol": "Https",
                        "provisioning_state": None,
                        "ssl_certificate": {"id": None},
                        "type": None,
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
        self,
        application_gateway_component: SREApplicationGatewayComponent,
        location: str,
    ):
        application_gateway_component.application_gateway.location.apply(
            partial(assert_equal, location),
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
                        "include_path": True,
                        "include_query_string": True,
                        "name": "GuacamoleHttpToHttpsRedirection",
                        "redirect_type": "Permanent",
                        "request_routing_rules": [{"id": None}],
                        "target_listener": {"id": None},
                        "type": None,
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
                        "http_listener": {"id": None},
                        "name": "GuacamoleHttpRouting",
                        "priority": 200,
                        "provisioning_state": None,
                        "redirect_configuration": {"id": None},
                        "rewrite_rule_set": {"id": None},
                        "rule_type": "Basic",
                        "type": None,
                    },
                    {
                        "backend_address_pool": {"id": None},
                        "backend_http_settings": {"id": None},
                        "etag": None,
                        "http_listener": {"id": None},
                        "name": "GuacamoleHttpsRouting",
                        "priority": 100,
                        "provisioning_state": None,
                        "rewrite_rule_set": {"id": None},
                        "rule_type": "Basic",
                        "type": None,
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
            partial(
                assert_equal_json,
                [
                    {
                        "etag": None,
                        "name": "ResponseHeaders",
                        "provisioning_state": None,
                        "rewrite_rules": [
                            {
                                "action_set": {
                                    "response_header_configurations": [
                                        {
                                            "header_name": "Content-Security-Policy",
                                            "header_value": "upgrade-insecure-requests; base-uri 'self'; frame-ancestors 'self'; form-action 'self'; object-src 'none';",
                                        }
                                    ]
                                },
                                "name": "content-security-policy",
                                "rule_sequence": 100,
                            },
                            {
                                "action_set": {
                                    "response_header_configurations": [
                                        {
                                            "header_name": "Permissions-Policy",
                                            "header_value": "accelerometer=(self), camera=(self), geolocation=(self), gyroscope=(self), magnetometer=(self), microphone=(self), payment=(self), usb=(self)",
                                        }
                                    ]
                                },
                                "name": "permissions-policy",
                                "rule_sequence": 200,
                            },
                            {
                                "action_set": {
                                    "response_header_configurations": [
                                        {
                                            "header_name": "Referrer-Policy",
                                            "header_value": "strict-origin-when-cross-origin",
                                        }
                                    ]
                                },
                                "name": "referrer-policy",
                                "rule_sequence": 300,
                            },
                            {
                                "action_set": {
                                    "response_header_configurations": [
                                        {"header_name": "Server", "header_value": ""}
                                    ]
                                },
                                "name": "server",
                                "rule_sequence": 400,
                            },
                            {
                                "action_set": {
                                    "response_header_configurations": [
                                        {
                                            "header_name": "Strict-Transport-Security",
                                            "header_value": "max-age=31536000; includeSubDomains; preload",
                                        }
                                    ]
                                },
                                "name": "strict-transport-security",
                                "rule_sequence": 500,
                            },
                            {
                                "action_set": {
                                    "response_header_configurations": [
                                        {
                                            "header_name": "X-Content-Type-Options",
                                            "header_value": "nosniff",
                                        }
                                    ]
                                },
                                "name": "x-content-type-options",
                                "rule_sequence": 600,
                            },
                            {
                                "action_set": {
                                    "response_header_configurations": [
                                        {
                                            "header_name": "X-Frame-Options",
                                            "header_value": "SAMEORIGIN",
                                        }
                                    ]
                                },
                                "name": "x-frame-options",
                                "rule_sequence": 700,
                            },
                        ],
                    },
                ],
            ),
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
                    name="Basic",
                    tier="Basic",
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
                        "key_vault_secret_id": "key_vault_certificate_id",
                        "name": "letsencryptcertificate",
                        "provisioning_state": None,
                        "public_cert_data": None,
                        "type": None,
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
            partial(assert_equal, {"key": "value", "component": "application gateway"}),
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
