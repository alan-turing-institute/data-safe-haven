#!/bin/bash

echo "Signing in with Azure CLI..."
# For authenticating with Azure CLI, it's necessary to allow traffic to the service tag AzureActiveDirectory.
if ! az login --identity --client-id "$CLIENT_ID"; then
    echo "Could not sign in with Azure CLI with managed identity."
    exit 1
fi

IFS=',' read -ra RECORD_NAME_CONTAINER_GROUP <<< "$RECORD_NAMES_CONTAINER_GROUPS"
for record_group in "${RECORD_NAME_CONTAINER_GROUP[@]}"; do
    read -r RECORD_NAME CONTAINER_GROUP_NAME <<< "$record_group"

    # A stopped Azure Container Instance can have no IP address. Updating its
    # DNS record would fail and must not prevent other running groups from being
    # repaired. Check state before requesting its address.
    echo "Checking state of container group $CONTAINER_GROUP_NAME..."
    if ! state=$(az container show --name "$CONTAINER_GROUP_NAME" --resource-group "$RESOURCE_GROUP" --subscription "$SUBSCRIPTION_ID" --query 'instanceView.state' -o tsv); then
        echo "Could not check state of container group $CONTAINER_GROUP_NAME."
        exit 1
    fi
    if [[ "$state" != "Running" ]]; then
        echo "Skipping container group $CONTAINER_GROUP_NAME (state: ${state:-unknown})."
        continue
    fi

    # The IP resolution and DNS update are done through the Azure Resource Manager REST API. Hence, we need to allow traffic to the service tag AzureResourceManager.
    echo "Finding container group IP address..."
    if ! private_ip=$(az container show --name "$CONTAINER_GROUP_NAME" --resource-group "$RESOURCE_GROUP" --subscription "$SUBSCRIPTION_ID" --query 'ipAddress.ip' -o tsv); then
        echo "Could not find private IP for container group $CONTAINER_GROUP_NAME."
        exit 1
    fi
    if [[ -z "$private_ip" || "$private_ip" == "None" || "$private_ip" == "null" ]]; then
        echo "Skipping container group $CONTAINER_GROUP_NAME (no private IP available)."
        continue
    fi
    echo "Private IP for container group $CONTAINER_GROUP_NAME: $private_ip"

    echo "Updating DNS record..."
    if ! az network private-dns record-set a update --name "$RECORD_NAME" --resource-group "$RESOURCE_GROUP" --subscription "$SUBSCRIPTION_ID" --zone-name "$PRIVATE_ZONE_NAME" --set "aRecords[0].ipv4Address=$private_ip"; then
        echo "Could not update DNS record $RECORD_NAME in private zone $PRIVATE_ZONE_NAME."
        exit 1
    fi
    echo "Record $RECORD_NAME updated in private zone $PRIVATE_ZONE_NAME"
done
