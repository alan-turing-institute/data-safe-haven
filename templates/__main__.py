"""An Azure RM Python Pulumi program"""

import pulumi
# from pulumi_azure_native import storage
# from pulumi_azure_native import resources

# # Create an Azure Resource Group
# resource_group = resources.ResourceGroup("rg")

# import base64
# import pulumi
# from pulumi import ResourceOptions
from pulumi_azure_native import resources, containerservice, network, authorization
# import pulumi_azuread as azuread
# from pulumi_kubernetes import Provider
# from pulumi_kubernetes.apps.v1 import Deployment
# from pulumi_kubernetes.core.v1 import Service, Namespace

config = pulumi.Config()
# prefix = config.require("prefix")
# password = config.require("password")
# ssh_public_key = config.require("sshkey")
#location = config.get("location") #or "east us"
deployment_name = config.require("deployment_name")
print(deployment_name)
# subscription_id = authorization.get_client_config().subscription_id

# # Create Azure AD Application for AKS
# app = azuread.Application(
#     f"{prefix}-aks-app",
#     display_name=f"{prefix}-aks-app"
# )

# # Create service principal for the application so AKS can act on behalf of the application
# sp = azuread.ServicePrincipal(
#     "aks-sp",
#     application_id=app.application_id
# )

# # Create the service principal password
# sppwd = azuread.ServicePrincipalPassword(
#     "aks-sp-pwd",
#     service_principal_id=sp.id,
#     end_date="2099-01-01T00:00:00Z",
#     value=password
# )

rg = resources.ResourceGroup(
    f"rg-{deployment_name}-kubernetes",
)

vnet = network.VirtualNetwork(
    f"vnet-{deployment_name}-kubernetes",
    location=rg.location,
    resource_group_name=rg.name,
    address_space={
        "address_prefixes": ["10.0.0.0/16"],
    }
)

# subnet = network.Subnet(
#     f"{prefix}-subnet",
#     resource_group_name=rg.name,
#     address_prefix="10.0.0.0/24",
#     virtual_network_name=vnet.name
# )

# subnet_assignment = authorization.RoleAssignment(
#     "subnet-permissions",
#     principal_id=sp.id,
#     principal_type=authorization.PrincipalType.SERVICE_PRINCIPAL,
#     role_definition_id=f"/subscriptions/{subscription_id}/providers/Microsoft.Authorization/roleDefinitions/4d97b98b-1d4f-4787-a291-c67834d212e7", # ID for Network Contributor role
#     scope=subnet.id
# )

# aks = containerservice.ManagedCluster(
#     f"{prefix}-aks",
#     location=rg.location,
#     resource_group_name=rg.name,
#     kubernetes_version="1.18.14",
#     dns_prefix="dns",
#     agent_pool_profiles=[{
#         "name": "type1",
#         "mode": "System",
#         "count": 2,
#         "vm_size": "Standard_B2ms",
#         "os_type": containerservice.OSType.LINUX,
#         "max_pods": 110,
#         "vnet_subnet_id": subnet.id
#     }],
#     linux_profile={
#         "admin_username": "azureuser",
#         "ssh": {
#             "public_keys": [{
#                 "key_data": ssh_public_key
#             }]
#         }
#     },
#     service_principal_profile={
#         "client_id": app.application_id,
#         "secret": sppwd.value
#     },
#     enable_rbac=True,
#     network_profile={
#         "network_plugin": "azure",
#         "service_cidr": "10.10.0.0/16",
#         "dns_service_ip": "10.10.0.10",
#         "docker_bridge_cidr": "172.17.0.1/16"
#     }, opts=ResourceOptions(depends_on=[subnet_assignment])
# )

# kube_creds = pulumi.Output.all(rg.name, aks.name).apply(
#     lambda args:
#     containerservice.list_managed_cluster_user_credentials(
#         resource_group_name=args[0],
#         resource_name=args[1]))

# kube_config = kube_creds.kubeconfigs[0].value.apply(
#     lambda enc: base64.b64decode(enc).decode())

# custom_provider = Provider(
#     "inflation_provider", kubeconfig=kube_config
# )

# pulumi.export("kubeconfig", kube_config)



# # # Create an Azure resource (Storage Account)
# # account = storage.StorageAccount(
# #     "sa",
# #     resource_group_name=resource_group.name,
# #     sku=storage.SkuArgs(
# #         name=storage.SkuName.STANDARD_LRS,
# #     ),
# #     kind=storage.Kind.STORAGE_V2,
# # )

# # # Export the primary key of the Storage Account
# # primary_key = (
# #     pulumi.Output.all(resource_group.name, account.name)
# #     .apply(
# #         lambda args: storage.list_storage_account_keys(
# #             resource_group_name=args[0], account_name=args[1]
# #         )
# #     )
# #     .apply(lambda accountKeys: accountKeys.keys[0].value)
# # )

# # pulumi.export("primary_storage_key", primary_key)
