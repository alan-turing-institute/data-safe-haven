#!/usr/bin/env bash

# Constants for colourised output
BOLD="\033[1m"
RED="\033[0;31m"
BLUE="\033[0;36m"
END="\033[0m"

# Environment
SUBSCRIPTION="DSG - Imperial/LANL"
STORAGE_ACCOUNT="dsgimperiallanl"
STORAGE_CONTAINER="lanl-data"

# Ensure we are using the right subscritpion
az account set --subscription "$SUBSCRIPTION"
# Generate SAS token
SAS_EXPIRY=$(date -v+2d '+%Y-%m-%dT%H:%MZ')
SAS_PERMISSIONS="rw"
SAS_SERVICES="b"
SAS_RESOURCE_TYPES="co"

REQUEST_DELAY=0.5
# Transfer netflow data (2-90)
echo ""
echo "Transferring netflow data"
echo "========================="
for i in $(seq -f "%02g" 2 90); do
    SOURCE_URL="https://csr.lanl.gov/data/unified-host-network-dataset-2017/netflow/netflow_day-$i.bz2"
    BLOB_NAME="unified-host-network-dataset-2017/netflow/netflow_day-$i.bz2"
    BLOB_EXISTS="$(az storage blob exists --account-name $STORAGE_ACCOUNT --container-name $STORAGE_CONTAINER --name $BLOB_NAME --query 'exists' | xargs echo)"

    echo -n "- netflow ${i}: ${BLOB_NAME}..."
    if [ "$BLOB_EXISTS" = "false" ]; then
        echo -n "starting copy..."
        RESULT=$(az storage blob copy start \
            --account-name $STORAGE_ACCOUNT \
            --destination-blob $BLOB_NAME \
            --destination-container $STORAGE_CONTAINER \
            --source-uri $SOURCE_URL --query 'status')
        echo "done (status = $RESULT)"
    else
        COPY_STATUS=$(az storage blob show --account-name $STORAGE_ACCOUNT --container-name $STORAGE_CONTAINER --name $BLOB_NAME --query "join(' - copied ', [properties.copy.status, properties.copy.progress])" | xargs echo)
        echo "skipping (copy status: $COPY_STATUS)"
    fi
    # Throttle requests to avoid failures due to Azure throttling us
    sleep REQUEST_DELAY
done

# Transfer wls data (1-90)
echo ""
echo "Transferring wls data"
echo "======================"
for i in $(seq -f "%02g" 1 90); do
    SOURCE_URL="https://csr.lanl.gov/data/unified-host-network-dataset-2017/wls/wls_day-$i.bz2"
    BLOB_NAME="unified-host-network-dataset-2017/wls/wls_day-$i.bz2"
    BLOB_EXISTS="$(az storage blob exists --account-name $STORAGE_ACCOUNT --container-name $STORAGE_CONTAINER --name $BLOB_NAME --query 'exists' | xargs echo)"

    echo -n " - wls ${i}: ${BLOB_NAME}..."
    if [ "$BLOB_EXISTS" = "false" ]; then
        echo -n "starting copy..."
        RESULT=$(az storage blob copy start \
            --account-name $STORAGE_ACCOUNT \
            --destination-blob $BLOB_NAME \
            --destination-container $STORAGE_CONTAINER \
            --source-uri $SOURCE_URL --query 'status')
        echo "done (status = $RESULT)"
    else
        COPY_STATUS=$(az storage blob show --account-name $STORAGE_ACCOUNT --container-name $STORAGE_CONTAINER --name $BLOB_NAME --query "join(' - copied ', [properties.copy.status, properties.copy.progress])" | xargs echo)
        echo "skipping (copy status: $COPY_STATUS)"
    fi
    # Throttle requests to avoid failures due to Azure throttling us
    sleep REQUEST_DELAY
done
