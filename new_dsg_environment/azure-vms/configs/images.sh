# Options which are configurable at the command line
RESOURCEGROUP_BUILD="RG_SH_BUILD_CANDIDATES"
RESOURCEGROUP_IMAGES="RG_SH_IMAGE_STORAGE"
RESOURCEGROUP_GALLERY="RG_SH_IMAGE_GALLERY"
RESOURCEGROUP_NETWORK="RG_SH_NETWORKING"
SUBSCRIPTION="Safe Haven VM Images"
LOCATION="westeurope" # have to build in West Europe in order to use Shared Image Gallery

# Other useful constants
GALLERYNAME="SAFE_HAVEN_COMPUTE_IMAGES" # must be unique within this subscription

# Ensure required features for shared image galleries are enabled for this subscription
ensure_image_galleries_enabled() {
    source ${BASH_SOURCE%/*}/text.sh
    FEATURE="GalleryPreview"
    NAMESPACE="Microsoft.Compute"
    RESOURCE="galleries/images/versions"

    # Get current feature state and metadata
    FEATURE_STATE="$(az feature show --namespace $NAMESPACE --name $FEATURE --query 'properties.state' | xargs)"
    RESOURCE_STATE=$(az provider show --namespace $NAMESPACE --query "resourceTypes[?resourceType=='$RESOURCE'].resourceType" -o tsv)

    # Print out current status
    echo -e "${BOLD}Ensuring that this subscription has the ${BLUE}$FEATURE${END}${BOLD} feature and ${BLUE}$RESOURCE${END}${BOLD} resource from ${BLUE}$NAMESPACE${END}${BOLD} enabled (this may take some time).${END}"
    echo -e "${BOLD}Current ${BLUE}$FEATURE${END}${BOLD} feature state is ${BLUE}$FEATURE_STATE${END}${BOLD}.${END}"
    if [ "$RESOURCE_STATE" = "$RESOURCE" ]; then
        echo -e "${BOLD}Resource ${BLUE}$RESOURCE${END}${BOLD} is present.${END}"
    else
        echo -e "${BOLD}Resource ${BLUE}$RESOURCE${END}${BOLD} is ${RED}not${END} ${BOLD}present.${END}"
    fi
    # Loop until features are present
    while [ "$FEATURE_STATE" != "Registered"  -o  "$RESOURCE_STATE" != "$RESOURCE" ]; do
        if [ "$FEATURE_STATE" = "NotRegistered" ]; then
            # Register feature
            echo -e "${BOLD}Registering ${BLUE}$FEATURE${END} ${BOLD}for ${BLUE}$SUBSCRIPTION${END}"
            az feature register --namespace Microsoft.Compute --name "$FEATURE" --subscription "$SUBSCRIPTION"
            az provider register --namespace Microsoft.Compute
        elif [ "$FEATURE_STATE" = "Pending" -o "$FEATURE_STATE" = "Registering" -o "$RESOURCE_STATE" != "$RESOURCE" ]; then
            echo -ne "."
            sleep 30
        else
            echo -e "${RED}$FEATURE state or $RESOURCE resource could not be found. Try updating Azure CLI.${END}"
            exit 1
        fi
        FEATURE_STATE="$(az feature show --namespace $NAMESPACE --name $FEATURE --query 'properties.state' | xargs)"
        RESOURCE_STATE=$(az provider show --namespace $NAMESPACE --query "resourceTypes[?resourceType=='$RESOURCE'].resourceType" -o tsv)
    done
}