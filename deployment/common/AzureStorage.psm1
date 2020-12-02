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
            Add-LogMessage -Level Warning "Storage account '$Name' will be deployed with EnableHttpsTrafficOnly disabled. Note that this can take up to 15 minutes to complete."
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
        [Microsoft.Azure.Commands.Management.Storage.Models.PSStorageAccount]$StorageAccount,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy the endpoint into")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Subnet to deploy the endpoint into")]
        [Microsoft.Azure.Commands.Network.Models.PSSubnet]$Subnet,
        [Parameter(Mandatory = $true, HelpMessage = "Type of storage to connect to (Blob, File or Default)")]
        [ValidateSet("Blob", "File", "Default")]
        [string]$StorageType,
        [Parameter(Mandatory = $true, HelpMessage = "Location to deploy the endpoint into")]
        [string]$Location
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
# ---------------------------------------------
function Deploy-StorageContainer {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of storage container to deploy")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Storage account to deploy into")]
        [Microsoft.Azure.Commands.Management.Storage.Models.PSStorageAccount]$StorageAccount
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
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Storage account to deploy into")]
        [Microsoft.Azure.Commands.Management.Storage.Models.PSStorageAccount]$StorageAccount
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


# Create storage share if it does not exist
# -----------------------------------------
function Deploy-StorageNfsShare {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of storage share to deploy")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Storage account to deploy into")]
        [Microsoft.Azure.Commands.Management.Storage.Models.PSStorageAccount]$StorageAccount
    )
    Add-LogMessage -Level Info "Ensuring that NFS storage share '$Name' exists..."
    $storageShare = Get-AzStorageShare -Name $Name -Context $StorageAccount.Context -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating NFS storage share '$Name' in storage account '$($StorageAccount.StorageAccountName)'"
        # As this step needs Az.Storage == 2.5.2-preview we run it in a subjob
        $success = Start-Job -ArgumentList @($StorageAccount.ResourceGroupName, $StorageAccount.StorageAccountName, $Name) -ScriptBlock {
            param(
                [string]$ResourceGroupName,
                [string]$StorageAccountName,
                [string]$ShareName
            )
            if (-not (Get-Module -ListAvailable -Name Az.Storage | Where-Object { $_.Version -eq "2.5.2" })) {
                Install-Module -Name Az.Storage -RequiredVersion 2.5.2-preview -AllowPrerelease -Repository PSGallery
            }
            Import-Module Az.Storage -RequiredVersion 2.5.2 -Force -ErrorAction Stop
            New-AzRmStorageShare -ResourceGroupName $ResourceGroupName `
                                 -StorageAccountName $StorageAccountName `
                                 -Name $ShareName `
                                 -EnabledProtocol NFS `
                                 -RootSquash "NoRootSquash"
            return $?
        } | Receive-Job -Wait -AutoRemoveJob
        if ($success) {
            $storageShare = Get-AzStorageShare -Name $Name -Context $StorageAccount.Context -ErrorVariable notExists -ErrorAction SilentlyContinue
            Add-LogMessage -Level Success "Created NFS storage share '$Name' in storage account '$($StorageAccount.StorageAccountName)"
        } else {
            Add-LogMessage -Level Fatal "Failed to create NFS storage share '$Name' in storage account '$($StorageAccount.StorageAccountName)'!"
        }
    } else {
        Add-LogMessage -Level InfoSuccess "NFS storage share '$Name' already exists in storage account '$($StorageAccount.StorageAccountName)'"
    }
    return $storageShare
}
Export-ModuleMember -Function Deploy-StorageNfsShare




# Ensure that storage receptable (either container or share) exists
# -----------------------------------------------------------------
function Deploy-StorageReceptacle {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of storage receptacle to deploy")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Storage account to deploy into")]
        [Microsoft.Azure.Commands.Management.Storage.Models.PSStorageAccount]$StorageAccount,
        [Parameter(Mandatory = $true, HelpMessage = "Type of storage receptacle to create (Share, Container or NfsShare)")]
        [ValidateSet("Share", "Container", "NfsShare")]
        [string]$StorageType
    )
    if ($StorageType -eq "Share") {
        return Deploy-StorageShare -Name $Name -StorageAccount $StorageAccount
    } elseif ($StorageType -eq "Container") {
        return Deploy-StorageContainer -Name $Name -StorageAccount $StorageAccount
    } elseif ($StorageType -eq "NfsShare") {
        return Deploy-StorageNfsShare -Name $Name -StorageAccount $StorageAccount
    }
    Add-LogMessage -Level Fatal "Unable to create a storage receptacle of type '$MountStorageTypeType'!"
}
Export-ModuleMember -Function Deploy-StorageReceptacle


# Get storage account possibly in another subscription
# ----------------------------------------------------
function Get-StorageAccount {
    # Note that in order to use @Args we must not include any [Parameter(...)] information
    param(
        [string]$SubscriptionName
    )
    $originalContext = Get-AzContext
    $null = Set-AzContext -SubscriptionId $SubscriptionName -ErrorAction Stop
    $StorageAccount = Get-AzStorageAccount @Args
    $null = Set-AzContext -Context $originalContext -ErrorAction Stop
    return $StorageAccount
}
Export-ModuleMember -Function Get-StorageAccount


# Get all available endpoints for a given storage account
# -------------------------------------------------------
function Get-StorageAccountEndpoints {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Storage account to deploy into")]
        [Microsoft.Azure.Commands.Management.Storage.Models.PSStorageAccount]$StorageAccount
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
        [Parameter(Mandatory = $true, HelpMessage = "Name of an access policy that is valid for this storage account")]
        [string]$PolicyName,
        [Parameter(Mandatory = $false, ParameterSetName = "ByContainerName", HelpMessage = "Container name")]
        [string]$ContainerName,
        [Parameter(Mandatory = $false, ParameterSetName = "ByShareName", HelpMessage = "Container name")]
        [string]$ShareName
    )
    $identifier = $ContainerName ? "container '$ContainerName'" : $ShareName ? "share '$ShareName'" : ""
    Add-LogMessage -Level Info "Generating new SAS token for $identifier in '$($StorageAccount.StorageAccountName)..."
    if ($ContainerName) {
        $SasToken = New-AzStorageContainerSASToken -Name $ContainerName -Policy $PolicyName -Context $StorageAccount.Context
        $expiryTime = (Get-AzStorageContainerStoredAccessPolicy -Container $ContainerName -Policy $PolicyName -Context $StorageAccount.Context).ExpiryTime
    } elseif ($ShareName) {
        $SasToken = New-AzStorageShareSASToken -ShareName $ShareName -Policy $PolicyName -Context $StorageAccount.Context
        $expiryTime = (Get-AzStorageShareStoredAccessPolicy -ShareName $ContainerName -Policy $PolicyName -Context $StorageAccount.Context).ExpiryTime
    }
    if ($?) {
        Add-LogMessage -Level Success "Created new SAS token for $identifier in '$($StorageAccount.StorageAccountName)' valid until $($expiryTime.UtcDateTime.ToString('yyyy-MM-dd'))"
    } else {
        Add-LogMessage -Level Fatal "Failed to create new SAS token for $identifier in '$($StorageAccount.StorageAccountName)!"
    }
    return $SasToken
}
Export-ModuleMember -Function New-StorageReceptacleSasToken


# Send local files to a Linux VM
# ------------------------------
function Send-FilesToLinuxVM {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of DNS zone to create")]
        [string]$LocalDirectory,
        [Parameter(Mandatory = $true, HelpMessage = "Name of DNS zone to create")]
        [string]$RemoteDirectory,
        [Parameter(Mandatory = $true, HelpMessage = "Storage account to generate a private endpoint for")]
        [Microsoft.Azure.Commands.Management.Storage.Models.PSStorageAccount]$BlobStorageAccount,
        [Parameter(Mandatory = $true, HelpMessage = "Storage account to generate a private endpoint for")]
        [string]$VMName,
        [Parameter(Mandatory = $true, HelpMessage = "Storage account to generate a private endpoint for")]
        [string]$VMResourceGroupName
    )
    $originalContext = Get-AzContext
    $ResolvedPath = Get-Item -Path $LocalDirectory

    # Zip files from the local directory
    try {
        $zipFileDir = New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString()))
        $zipFileContainerName = [Guid]::NewGuid().ToString()
        $zipFileName = "${zipFileContainerName}.zip"
        $zipFilePath = Join-Path $zipFileDir $zipFileName
        if (Test-Path $zipFilePath) { Remove-Item $zipFilePath }
        Add-LogMessage -Level Info "[ ] Creating zip file at $zipFilePath..."
        Compress-Archive -CompressionLevel NoCompression -Path $ResolvedPath -DestinationPath $zipFilePath -ErrorAction Stop
        Add-LogMessage -Level Success "Zip file creation succeeded"
    } catch {
        $null = Remove-Item -Path $zipFileDir -Recurse -Force -ErrorAction SilentlyContinue
        Add-LogMessage -Level Fatal "Zip file creation failed!"
    }

    # Upload the zipfile to blob storage
    Add-LogMessage -Level Info "[ ] Uploading zip file to container '$zipFileContainerName'..."
    try {
        $null = Set-AzContext -SubscriptionId $BlobStorageAccount.Id.Split("/")[2] -ErrorAction Stop
        $DefaultAction = (Get-AzStorageAccountNetworkRuleSet -ResourceGroupName $BlobStorageAccount.ResourceGroupName -Name $BlobStorageAccount.StorageAccountName).DefaultAction
        $null = Update-AzStorageAccountNetworkRuleSet -Name $BlobStorageAccount.StorageAccountName -ResourceGroupName $BlobStorageAccount.ResourceGroupName -DefaultAction Allow -ErrorAction Stop
        $null = Deploy-StorageContainer -Name $zipFileContainerName -StorageAccount $BlobStorageAccount
        $null = Set-AzStorageBlobContent -Container $zipFileContainerName -Context $BlobStorageAccount.Context -File $zipFilePath -Blob $zipFileName -Force -ErrorAction Stop
        $null = Update-AzStorageAccountNetworkRuleSet -Name $BlobStorageAccount.StorageAccountName -ResourceGroupName $BlobStorageAccount.ResourceGroupName -DefaultAction $DefaultAction -ErrorAction Stop
        $null = Set-AzContext -Context $originalContext -ErrorAction Stop
        Add-LogMessage -Level Success "Successfully uploaded zip file to '$zipFileContainerName'"
    } catch {
        $null = Remove-Item -Path $zipFileDir -Recurse -Force -ErrorAction SilentlyContinue
        $null = Remove-AzStorageContainer -Name $zipFileContainerName -Context $BlobStorageAccount.Context -Force -ErrorAction SilentlyContinue
        Add-LogMessage -Level Fatal "Failed to upload zip file to '$zipFileContainerName'!" -Exception $_.Exception
    }

    # Remove zip file directory
    Add-LogMessage -Level Info "[ ] Cleaning up directory $zipFileDir..."
    try {
        $null = Remove-Item -Path $zipFileDir -Recurse -Force -ErrorAction SilentlyContinue
        Add-LogMessage -Level Success "Successfully cleaned up '$zipFileDir'"
    } catch {
        Add-LogMessage -Level Fatal "Failed to clean up '$zipFileDir'!"
    }

    # Generate a SAS token and construct URL
    Add-LogMessage -Level Info "[ ] Generating download URL..."
    $sasToken = New-ReadOnlyStorageAccountSasToken -ResourceGroup $BlobStorageAccount.ResourceGroupName -AccountName $BlobStorageAccount.StorageAccountName -SubscriptionName $BlobStorageAccount.Id.Split("/")[2]
    $remoteUrl = "$($BlobStorageAccount.PrimaryEndpoints.Blob)${zipFileContainerName}/${zipFileName}${sasToken}"
    Add-LogMessage -Level Success "Constructed download URL $remoteUrl"

    # Download the zip file onto the remote machine using curl
    $script = @("#!/bin/bash",
                "tmpdir=`$(mktemp -d)",
                "curl -X GET -o `$tmpdir/${zipFileName} '${remoteUrl}' 2>&1",
                "mkdir -p ${RemoteDirectory}",
                "unzip `$tmpdir/${zipFileName} -d ${RemoteDirectory}",
                "rm -rf `$tmpdir") -join "`n"
    Add-LogMessage -Level Info "[ ] Downloading zip file onto $VMName"
    $null = Invoke-RemoteScript -Shell "UnixShell" -Script $script -VMName $VMName -ResourceGroupName $VMResourceGroupName

    # Remove blob storage container
    Add-LogMessage -Level Info "[ ] Cleaning up storage container '$zipFileContainerName'..."
    try {
        $null = Remove-AzStorageContainer -Name $zipFileContainerName -Context $BlobStorageAccount.Context -Force -ErrorAction Stop
        Add-LogMessage -Level Success "Successfully cleaned up '$zipFileContainerName'"
    } catch {
        Add-LogMessage -Level Fatal "Failed to clean up '$zipFileContainerName'!"
    }
}
Export-ModuleMember -Function Send-FilesToLinuxVM

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
        $policy = Get-AzStorageShareStoredAccessPolicy -ShareName $ContainerName -Policy $PolicyName -Context $StorageAccount.Context -ErrorAction SilentlyContinue
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
