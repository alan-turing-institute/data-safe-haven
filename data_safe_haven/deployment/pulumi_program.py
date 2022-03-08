"""Pulumi declarative program"""
# Standard library imports
import base64

# Third party imports
import ipaddress
import pulumi
from pulumi_azure_native import resources, containerservice, network


def get_ip_range(ip_address_first, ip_address_last):
    networks = list(
        ipaddress.summarize_address_range(
            ipaddress.ip_address(ip_address_first),
            ipaddress.ip_address(ip_address_last),
        )
    )
    if len(networks) != 1:
        raise ValueError(f"Found {len(networks)} networks when expecting one.")
    return networks[0]


class PulumiProgram:
    """Deploy with Pulumi"""

    def __init__(self, config):
        self.cfg = config

        # Define IP addresses and ranges
        self.ip4 = {
            "vnet": get_ip_range("10.0.0.0", "10.3.255.255"),
            "kubernetes_nodes": get_ip_range("10.0.0.0", "10.0.255.255"),
            "kubernetes_service": get_ip_range("10.4.0.0", "10.4.255.255"),
            "docker_bridge": get_ip_range("172.17.0.0", "172.17.255.255"),
        }
        self.ip4["dns_service_ip"] = self.ip4["kubernetes_service"][10]

    def run(self):
        # Define resource groups
        rg_kubernetes_cluster = resources.ResourceGroup(
            "rg_kubernetes_cluster",
            resource_group_name=f"rg-{self.cfg.deployment_name}-kubernetes-cluster",
        )
        rg_networking = resources.ResourceGroup(
            "rg_networking",
            resource_group_name=f"rg-{self.cfg.deployment_name}-networking",
        )
        # Kubernetes infrastructure cannot be a pre-existing resource group: https://github.com/Azure/azure-cli-extensions/issues/2072
        rg_kubernetes_infrastructure_name = (
            f"rg-{self.cfg.deployment_name}-kubernetes-infrastructure"
        )

        # Define networking
        nsg_kubernetes_nodes = network.NetworkSecurityGroup(
            "nsg-kubernetes-nodes",
            network_security_group_name=f"nsg-{self.cfg.deployment_name}-kubernetes-nodes",
            resource_group_name=rg_networking.name,
        )
        vnet = network.VirtualNetwork(
            "vnet",
            address_space=network.AddressSpaceArgs(
                address_prefixes=[str(self.ip4["vnet"])],
            ),
            resource_group_name=rg_networking.name,
            subnets=[  # Note that we need to define subnets inline or they will be destroyed/recreated on a new run
                network.SubnetArgs(
                    address_prefix=str(self.ip4["kubernetes_nodes"]),
                    name="KubernetesNodesSubnet",
                    network_security_group=network.NetworkSecurityGroupArgs(
                        id=nsg_kubernetes_nodes.id
                    ),
                    private_endpoint_network_policies="Disabled",  # needed by Kubernetes cluster
                )
            ],
            virtual_network_name=f"vnet-{self.cfg.deployment_name}",
        )
        # private_link_service_network_policies="Enabled",
        snet_kubernetes_nodes = network.get_subnet(
            subnet_name="KubernetesNodesSubnet",
            resource_group_name=rg_networking.name,
            virtual_network_name=vnet.name,
        )

        # Define Kubernetes cluster
        aks_cluster = containerservice.ManagedCluster(
            "aks_cluster",
            aad_profile=containerservice.ManagedClusterAADProfileArgs(
                admin_group_object_ids=[self.cfg.azure.admin_group_id],
                enable_azure_rbac=False,
                managed=True,
                tenant_id=self.cfg.azure.tenant_id,
            ),
            agent_pool_profiles=[
                containerservice.ManagedClusterAgentPoolProfileArgs(
                    count=3,
                    enable_node_public_ip=False,
                    mode="System",
                    name="nodepool",
                    os_type="Linux",
                    type="VirtualMachineScaleSets",
                    vm_size="Standard_D2s_v4",
                    vnet_subnet_id=snet_kubernetes_nodes.id,
                )
            ],
            api_server_access_profile=containerservice.ManagedClusterAPIServerAccessProfileArgs(
                enable_private_cluster=False
            ),
            dns_prefix=self.cfg.deployment_name,
            enable_rbac=True,
            identity=containerservice.ManagedClusterIdentityArgs(
                type=containerservice.ResourceIdentityType.SYSTEM_ASSIGNED
            ),
            kubernetes_version="1.22.6",  # "1.21.9",
            network_profile=containerservice.ContainerServiceNetworkProfileArgs(
                dns_service_ip=str(self.ip4["dns_service_ip"]),
                docker_bridge_cidr=str(self.ip4["docker_bridge"]),
                load_balancer_sku="standard",
                network_plugin="azure",
                outbound_type="loadBalancer",
                # pod_cidr=str(self.ip4["kubernetes_nodes"]), # IP range from which to assign pod IPs when kubenet is used
                service_cidr=str(self.ip4["kubernetes_service"]),
            ),
            node_resource_group=rg_kubernetes_infrastructure_name,
            resource_group_name=rg_kubernetes_cluster.name,
            resource_name_=f"aks-{self.cfg.deployment_name}-kubernetes",
            sku=containerservice.ManagedClusterSKUArgs(
                name="Basic",
                tier="Free",
            ),
        )

        # Save Kubernetes credentials
        credentials = containerservice.list_managed_cluster_user_credentials_output(
            resource_group_name=rg_kubernetes_cluster.name,
            resource_name=aks_cluster.name,
        )
        pulumi.export(
            "kubeconfig",
            credentials.kubeconfigs[0].value.apply(
                lambda enc: base64.b64decode(enc).decode()
            ),
        )
