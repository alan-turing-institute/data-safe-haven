# Generate a new SAS token
# ------------------------
function New-AccountSasToken {
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
    $null = Set-AzContext -Subscription $SubscriptionName

    # Generate SAS token
    $accountKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroup -AccountName $AccountName).Value[0]
    $accountContext = (New-AzStorageContext -StorageAccountName $AccountName -StorageAccountKey $accountKey)
    $expiryTime = ((Get-Date) + (New-TimeSpan -Hours $ValidityHours))
    $sasToken = (New-AzStorageAccountSASToken -Service $Service -ResourceType $ResourceType -Permission $Permission -ExpiryTime $expiryTime -Context $accountContext)

    # Switch back to previous subscription
    $null = Set-AzContext -Context $originalContext
    return $sasToken
}
Export-ModuleMember -Function New-AccountSasToken




# Generate a new read-only SAS token
# ----------------------------------
function New-ReadOnlyAccountSasToken {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Enter subscription name")]
        [string]$SubscriptionName,
        [Parameter(Mandatory = $true, HelpMessage = "Enter storage account resource group")]
        [string]$ResourceGroup,
        [Parameter(Mandatory = $true, HelpMessage = "Enter storage account name")]
        [string]$AccountName
    )
    return New-AccountSasToken -SubscriptionName "$SubscriptionName" `
                               -ResourceGroup "$ResourceGroup" `
                               -AccountName "$AccountName" `
                               -Service Blob, File `
                               -ResourceType Service, Container, Object `
                               -Permission "rl"
}
Export-ModuleMember -Function New-ReadOnlyAccountSasToken


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
# -------------------------
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
    $identifier = $ContainerName ? "container '$ContainerName'" : $ShareName ? "share '$ShareName'" : ""
    Add-LogMessage -Level Info "Ensuring that SAS policy '$Name' exists for $identifier in '$($StorageAccount.StorageAccountName)..."
    if ($ContainerName) {
        $policies = Get-AzStorageContainerStoredAccessPolicy -Container $ContainerName -Context $StorageAccount.Context | Where-Object { $_.policy -like "*$Name" } | Select-Object -First 1
    } elseif ($ShareName) {
        $policies = Get-AzStorageShareStoredAccessPolicy -ShareName $ShareName -Context $StorageAccount.Context
    }
    $existingPolicy = $policies | Where-Object { $_.policy -like "*$Name" } | Select-Object -First 1
    if ($existingPolicy) {
        Add-LogMessage -Level InfoSuccess "Found existing SAS policy '$Name' for $identifier in '$($StorageAccount.StorageAccountName)"
        $policy = $existingPolicy.Policy
    } else {
        Add-LogMessage -Level Info "[ ] Creating new SAS policy '$Name' for $identifier in '$($StorageAccount.StorageAccountName)"
        if ($ContainerName) {
            $policy = New-AzStorageContainerStoredAccessPolicy -Container $ContainerName `
                                                               -Policy "$(Get-Date -Format "yyyyMMddHHmmss")${AccessType}" `
                                                               -Context $StorageAccount.Context `
                                                               -Permission $Permission `
                                                               -StartTime (Get-Date).DateTime `
                                                               -ExpiryTime (Get-Date).AddYears($ValidityYears).DateTime
        } elseif ($ShareName) {
            $policy = New-AzStorageShareStoredAccessPolicy -ShareName $ShareName `
                                                           -Policy "$(Get-Date -Format "yyyyMMddHHmmss")${AccessType}" `
                                                           -Context $StorageAccount.Context `
                                                           -Permission $Permission `
                                                           -StartTime (Get-Date).DateTime `
                                                           -ExpiryTime (Get-Date).AddYears($ValidityYears).DateTime
        }
        if ($?) {
            Add-LogMessage -Level Success "Created new SAS policy '$Name' for $identifier in '$($StorageAccount.StorageAccountName)"
        } else {
            Add-LogMessage -Level Fatal "Failed to create new SAS policy '$Name' for $identifier in '$($StorageAccount.StorageAccountName)!"
        }
    }
    return $policy
}
Export-ModuleMember -Function Deploy-SasAccessPolicy
