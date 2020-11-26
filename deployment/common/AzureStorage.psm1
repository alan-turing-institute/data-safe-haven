Import-Module Az -ErrorAction Stop
Import-Module $PSScriptRoot/Deployments -ErrorAction Stop
Import-Module $PSScriptRoot/Logging -ErrorAction Stop


# Create storage account if it does not exist
# ------------------------------------------
function Deploy-StorageAccount {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of storage account to deploy")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Location of resource group to deploy into")]
        [string]$Location,
        [Parameter(Mandatory = $false, HelpMessage = "SKU name of the storage account to deploy")]
        [string]$SkuName = "Standard_LRS",
        [Parameter(Mandatory = $false, HelpMessage = "Kind of storage account to deploy")]
        [ValidateSet("StorageV2", "BlobStorage", "BlockBlobStorage", "FileStorage")]
        [string]$Kind = "StorageV2",
        [Parameter(Mandatory = $false, HelpMessage = "Access tier of the Storage account. Only used if 'Kind' is set to 'BlobStorage'")]
        [string]$AccessTier = "Hot",
        [Parameter(Mandatory = $false, HelpMessage = "Allow traffic over http as well as https (required for NFS file shares)")]
        [switch]$AllowHttpTraffic
    )
    Add-LogMessage -Level Info "Ensuring that storage account '$Name' exists in '$ResourceGroupName'..."
    $storageAccount = Get-AzStorageAccount -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating storage account '$Name'"
        $params = @{}
        if ($Kind -eq "BlobStorage") { $params["AccessTier"] = $AccessTier }
        if ($AllowHttpTraffic) {
            $params["EnableHttpsTrafficOnly"] = $false
            Add-LogMessage -Level Warning "Storage account '$Name' will be deployed with EnableHttpsTrafficOnly disabled. Note that this can take around 15 minutes to complete."
        }
        $storageAccount = New-AzStorageAccount -Name $Name -ResourceGroupName $ResourceGroupName -Location $Location -SkuName $SkuName -Kind $Kind @params
        if ($?) {
            Add-LogMessage -Level Success "Created storage account '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create storage account '$Name'!"
        }
    } else {
        Add-LogMessage -Level InfoSuccess "Storage account '$Name' already exists"
    }
    return $storageAccount
}
Export-ModuleMember -Function Deploy-StorageAccount


# Create storage account private endpoint if it does not exist
# ------------------------------------------------------------
function Deploy-StorageAccountEndpoint {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Storage account to generate a private endpoint for")]
        $StorageAccount,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy the endpoint into")]
        $ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Subnet to deploy the endpoint into")]
        $Subnet,
        [Parameter(Mandatory = $true, HelpMessage = "Type of storage to connect to (Blob, File or Default)")]
        [ValidateSet("Blob", "File", "Default")]
        $StorageType,
        [Parameter(Mandatory = $true, HelpMessage = "Location to deploy the endpoint into")]
        $Location
    )
    # Allow a default if we're using a storage account that is only compatible with one storage type
    if ($StorageType -eq "Default") {
        if ($StorageAccount.Kind -eq "BlobStorage") { $StorageType = "Blob" }
        if ($StorageAccount.Kind -eq "BlockBlobStorage") { $StorageType = "Blob" }
        if ($StorageAccount.Kind -eq "FileStorage") { $StorageType = "File" }
    }
    # Validate that the storage type is compatible with this storage account
    if ((($StorageAccount.Kind -eq "BlobStorage") -and ($StorageType -ne "Blob")) -or
        (($StorageAccount.Kind -eq "BlockBlobStorage") -and ($StorageType -ne "Blob")) -or
        (($StorageAccount.Kind -eq "FileStorage") -and ($StorageType -ne "File"))) {
        Add-LogMessage -Level Fatal "Storage type '$StorageType' is not compatible with '$($StorageAccount.StorageAccountName)' which uses '$($StorageAccount.Kind)'"
    }
    # Disable private endpoint network policies on the subnet
    # See here for further information: https://docs.microsoft.com/en-us/azure/private-link/disable-private-endpoint-network-policy
    # Note that this means that NSG rules will *not* apply to the private endpoint
    if ($Subnet.PrivateEndpointNetworkPolicies -ne "Disabled") {
        Add-LogMessage -Level Info "[ ] Disabling private endpoint network policies on '$($Subnet.Name)'..."
        $virtualNetwork = Get-VirtualNetworkFromSubnet -Subnet $Subnet
        ($virtualNetwork | Select-Object -ExpandProperty Subnets | Where-Object { $_.Name -eq $Subnet.Name }).PrivateEndpointNetworkPolicies = "Disabled"
        $virtualNetwork | Set-AzVirtualNetwork
        if ($?) {
            Add-LogMessage -Level Success "Disabled private endpoint network policies on '$($Subnet.Name)'"
        } else {
            Add-LogMessage -Level Fatal "Failed to disable private endpoint network policies on '$($Subnet.Name)'!"
        }
    }
    # Ensure that the private endpoint exists
    $privateEndpointName = "$($StorageAccount.StorageAccountName)-endpoint"
    Add-LogMessage -Level Info "Ensuring that private endpoint '$privateEndpointName' for storage account '$($StorageAccount.StorageAccountName)' exists..."
    try {
        $privateEndpoint = Get-AzPrivateEndpoint -Name $privateEndpointName -ResourceGroupName $ResourceGroupName -ErrorAction Stop
        if ($privateEndpoint.PrivateLinkServiceConnections.PrivateLinkServiceConnectionState.Status -eq "Disconnected") {
            $null = Remove-AzPrivateEndpoint -Name $privateEndpointName -ResourceGroupName $ResourceGroupName -Force
            Start-Sleep 5
            $privateEndpoint = Get-AzPrivateEndpoint -Name $privateEndpointName -ResourceGroupName $ResourceGroupName -ErrorAction Stop
        }
        Add-LogMessage -Level InfoSuccess "Private endpoint '$privateEndpointName' already exists for storage account '$($StorageAccount.StorageAccountName)'"
    } catch [Microsoft.Azure.Commands.Network.Common.NetworkCloudException] {
        Add-LogMessage -Level Info "[ ] Creating private endpoint '$privateEndpointName' for storage account '$($StorageAccount.StorageAccountName)'"
        $privateEndpointConnection = New-AzPrivateLinkServiceConnection -Name "${privateEndpointName}ServiceConnection" -PrivateLinkServiceId $StorageAccount.Id -GroupId $StorageType
        $success = $?
        $privateEndpoint = New-AzPrivateEndpoint -Name $privateEndpointName -ResourceGroupName $ResourceGroupName -Location $Location -Subnet $Subnet -PrivateLinkServiceConnection $privateEndpointConnection
        $success = $success -and $?
        if ($success) {
            Add-LogMessage -Level Success "Created private endpoint '$privateEndpointName' for storage account '$($StorageAccount.StorageAccountName)'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create private endpoint '$privateEndpointName' for storage account '$($StorageAccount.StorageAccountName)'!"
        }
    }
    return $privateEndpoint
}
Export-ModuleMember -Function Deploy-StorageAccountEndpoint


# Create storage container if it does not exist
# ------------------------------------------
function Deploy-StorageContainer {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of storage container to deploy")]
        $Name,
        [Parameter(Mandatory = $true, HelpMessage = "Storage account to deploy into")]
        $StorageAccount
    )
    Add-LogMessage -Level Info "Ensuring that storage container '$Name' exists..."
    $storageContainer = Get-AzStorageContainer -Name $Name -Context $StorageAccount.Context -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating storage container '$Name' in storage account '$($StorageAccount.StorageAccountName)'"
        $storageContainer = New-AzStorageContainer -Name $Name -Context $StorageAccount.Context
        if ($?) {
            Add-LogMessage -Level Success "Created storage container '$Name' in storage account '$($StorageAccount.StorageAccountName)"
        } else {
            Add-LogMessage -Level Fatal "Failed to create storage container '$Name' in storage account '$($StorageAccount.StorageAccountName)'!"
        }
    } else {
        Add-LogMessage -Level InfoSuccess "Storage container '$Name' already exists in storage account '$($StorageAccount.StorageAccountName)'"
    }
    return $storageContainer
}
Export-ModuleMember -Function Deploy-StorageContainer


# Create storage share if it does not exist
# -----------------------------------------
function Deploy-StorageShare {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of storage share to deploy")]
        $Name,
        [Parameter(Mandatory = $true, HelpMessage = "Storage account to deploy into")]
        $StorageAccount
    )
    Add-LogMessage -Level Info "Ensuring that storage share '$Name' exists..."
    $storageShare = Get-AzStorageShare -Name $Name -Context $StorageAccount.Context -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating storage share '$Name' in storage account '$($StorageAccount.StorageAccountName)'"
        $storageShare = New-AzStorageShare -Name $Name -Context $StorageAccount.Context
        if ($?) {
            Add-LogMessage -Level Success "Created storage share '$Name' in storage account '$($StorageAccount.StorageAccountName)"
        } else {
            Add-LogMessage -Level Fatal "Failed to create storage share '$Name' in storage account '$($StorageAccount.StorageAccountName)'!"
        }
    } else {
        Add-LogMessage -Level InfoSuccess "Storage share '$Name' already exists in storage account '$($StorageAccount.StorageAccountName)'"
    }
    return $storageShare
}
Export-ModuleMember -Function Deploy-StorageShare


# Ensure that storage receptable (either container or share) exists
# -----------------------------------------------------------------
function Deploy-StorageReceptacle {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of storage receptacle to deploy")]
        $Name,
        [Parameter(Mandatory = $true, HelpMessage = "Storage account to deploy into")]
        $StorageAccount,
        [Parameter(Mandatory = $true, HelpMessage = "Type of storage receptacle to create (Share or Container)")]
        [ValidateSet("Share", "Container")]
        $StorageType
    )
    if ($StorageType -eq "Share") {
        return Deploy-StorageShare -Name $Name -StorageAccount $StorageAccount
    } elseif ($StorageType -eq "Container") {
        return Deploy-StorageContainer -Name $Name -StorageAccount $StorageAccount
    }
    Add-LogMessage -Level Fatal "Unable to create a storage receptacle of type '$MountStorageTypeType'!"
}
Export-ModuleMember -Function Deploy-StorageReceptacle


# Get all available endpoints for a given storage account
# -------------------------------------------------------
function Get-StorageAccountEndpoints {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Storage account to deploy into")]
        $StorageAccount
    )
    return @(
        @($StorageAccount.PrimaryEndpoints.Blob,
          $StorageAccount.PrimaryEndpoints.Queue,
          $StorageAccount.PrimaryEndpoints.Table,
          $StorageAccount.PrimaryEndpoints.File,
          $StorageAccount.PrimaryEndpoints.Web,
          $StorageAccount.PrimaryEndpoints.Dfs) | Where-Object { $_ }
    )
}
Export-ModuleMember -Function Get-StorageAccountEndpoints


# Generate a new SAS token
# ------------------------
function New-StorageAccountSasToken {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Enter subscription name")]
        [string]$SubscriptionName,
        [Parameter(Mandatory = $true, HelpMessage = "Enter storage account resource group")]
        [string]$ResourceGroup,
        [Parameter(Mandatory = $true, HelpMessage = "Enter storage account name")]
        [string]$AccountName,
        [Parameter(Mandatory = $true, HelpMessage = "Enter service(s): one or more of (Blob, File, Table, Queue)")]
        [string[]]$Service,
        [Parameter(Mandatory = $true, HelpMessage = "Enter resource type(s): one or more of (Service, Container, Object)")]
        [string[]]$ResourceType,
        [Parameter(Mandatory = $true, HelpMessage = "Enter permission string")]
        [string]$Permission,
        [Parameter(Mandatory = $false, HelpMessage = "Enter validity in hours")]
        [int]$ValidityHours = 2
    )

    # Temporarily switch to storage account subscription
    $originalContext = Get-AzContext
    $null = Set-AzContext -Subscription $SubscriptionName -ErrorAction Stop

    # Generate SAS token
    $accountKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroup -AccountName $AccountName).Value[0]
    $accountContext = (New-AzStorageContext -StorageAccountName $AccountName -StorageAccountKey $accountKey)
    $expiryTime = ((Get-Date) + (New-TimeSpan -Hours $ValidityHours))
    $sasToken = (New-AzStorageAccountSASToken -Service $Service -ResourceType $ResourceType -Permission $Permission -ExpiryTime $expiryTime -Context $accountContext)

    # Switch back to previous subscription
    $null = Set-AzContext -Context $originalContext -ErrorAction Stop
    return $sasToken
}
Export-ModuleMember -Function New-StorageAccountSasToken


# Generate a new read-only SAS token
# ----------------------------------
function New-ReadOnlyStorageAccountSasToken {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Enter subscription name")]
        [string]$SubscriptionName,
        [Parameter(Mandatory = $true, HelpMessage = "Enter storage account resource group")]
        [string]$ResourceGroup,
        [Parameter(Mandatory = $true, HelpMessage = "Enter storage account name")]
        [string]$AccountName
    )
    return New-StorageAccountSasToken -SubscriptionName "$SubscriptionName" `
                                      -ResourceGroup "$ResourceGroup" `
                                      -AccountName "$AccountName" `
                                      -Service Blob, File `
                                      -ResourceType Service, Container, Object `
                                      -Permission "rl"
}
Export-ModuleMember -Function New-ReadOnlyStorageAccountSasToken


# Generate a new SAS policy
# -------------------------
function New-StorageReceptacleSasToken {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Storage account")]
        [Microsoft.Azure.Commands.Management.Storage.Models.PSStorageAccount]$StorageAccount,
        [Parameter(Mandatory = $true, HelpMessage = "Policy permissions")]
        [string]$Policy,
        [Parameter(Mandatory = $false, ParameterSetName = "ByContainerName", HelpMessage = "Container name")]
        [string]$ContainerName,
        [Parameter(Mandatory = $false, ParameterSetName = "ByShareName", HelpMessage = "Container name")]
        [string]$ShareName
    )
    $identifier = $ContainerName ? "container '$ContainerName'" : $ShareName ? "share '$ShareName'" : ""
    Add-LogMessage -Level Info "Generating new SAS token for $identifier in '$($StorageAccount.StorageAccountName)..."
    if ($ContainerName) {
        $SasToken = New-AzStorageContainerSASToken -Name $ContainerName -Policy $Policy -Context $StorageAccount.Context
    } elseif ($ShareName) {
        $SasToken = New-AzStorageShareSASToken -ShareName $ShareName -Policy $Policy -Context $StorageAccount.Context
    }
    if ($?) {
        Add-LogMessage -Level Success "Created new SAS token for $identifier in '$($StorageAccount.StorageAccountName)"
    } else {
        Add-LogMessage -Level Fatal "Failed to create new SAS token for $identifier in '$($StorageAccount.StorageAccountName)!"
    }
    return $SasToken
}
Export-ModuleMember -Function New-StorageReceptacleSasToken


# Generate a new SAS policy
# Note that there is a limit of 5 policies for a given storage account/container
# ------------------------------------------------------------------------------
function Deploy-SasAccessPolicy {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Policy name")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Policy permissions")]
        [string]$Permission,
        [Parameter(Mandatory = $true, HelpMessage = "Storage account")]
        [Microsoft.Azure.Commands.Management.Storage.Models.PSStorageAccount]$StorageAccount,
        [Parameter(Mandatory = $false, ParameterSetName = "ByContainerName", HelpMessage = "Container name")]
        [string]$ContainerName,
        [Parameter(Mandatory = $false, ParameterSetName = "ByShareName", HelpMessage = "Container name")]
        [string]$ShareName,
        [Parameter(Mandatory = $false, HelpMessage = "Validity in years")]
        [int]$ValidityYears = 1
    )
    $Identifier = $ContainerName ? "container '$ContainerName'" : $ShareName ? "share '$ShareName'" : ""
    $PolicyName = "${identifier}${Name}".Replace(" ", "").Replace("'", "").ToLower()
    Add-LogMessage -Level Info "Ensuring that SAS policy '$PolicyName' exists for $Identifier in '$($StorageAccount.StorageAccountName)..."
    if ($ContainerName) {
        $policy = Get-AzStorageContainerStoredAccessPolicy -Container $ContainerName -Policy $PolicyName -Context $StorageAccount.Context -ErrorAction SilentlyContinue
    } elseif ($ShareName) {
        $policy = Get-AzStorageShareStoredAccessPolicy -Container $ContainerName -Policy $PolicyName -Context $StorageAccount.Context -ErrorAction SilentlyContinue
    }
    if ($policy) {
        Add-LogMessage -Level InfoSuccess "Found existing SAS policy '$PolicyName' for $Identifier in '$($StorageAccount.StorageAccountName)"
    } else {
        Add-LogMessage -Level Info "[ ] Creating new SAS policy '$PolicyName' for $Identifier in '$($StorageAccount.StorageAccountName)"
        $StartTime = (Get-Date).AddMinutes(-15)
        $ExpiryTime = $StartTime.AddYears($ValidityYears)
        $success = $false
        if ($ContainerName) {
            $null = New-AzStorageContainerStoredAccessPolicy -Container $ContainerName -Policy $PolicyName -Context $StorageAccount.Context -Permission $Permission -StartTime $StartTime -ExpiryTime $ExpiryTime
            $policy = Get-AzStorageContainerStoredAccessPolicy -Container $ContainerName -Policy $PolicyName -Context $StorageAccount.Context
            $success = $?
        } elseif ($ShareName) {
            $null = New-AzStorageShareStoredAccessPolicy -ShareName $ShareName -Policy $PolicyName -Context $StorageAccount.Context -Permission $Permission -StartTime $StartTime -ExpiryTime $ExpiryTime
            $policy = Get-AzStorageShareStoredAccessPolicy -ShareName $ShareName -Policy $PolicyName -Context $StorageAccount.Context
            $success = $?
        }
        if ($success) {
            Add-LogMessage -Level Success "Created new SAS policy '$PolicyName' for $Identifier in '$($StorageAccount.StorageAccountName)"
        } else {
            Add-LogMessage -Level Fatal "Failed to create new SAS policy '$PolicyName' for $Identifier in '$($StorageAccount.StorageAccountName)!"
        }
    }
    return $policy
}
Export-ModuleMember -Function Deploy-SasAccessPolicy
