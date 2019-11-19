function New-AccountSasToken {
    param(
        [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter subscription name")]
        [string]$subscriptionName,
        [Parameter(Position=1, Mandatory = $true, HelpMessage = "Enter storage account resource group")]
        [string]$resourceGroup,
        [Parameter(Position=2, Mandatory = $true, HelpMessage = "Enter storage account name")]
        [string]$accountName,
        [Parameter(Position=3, Mandatory = $true, HelpMessage = "Enter service(s) - one or more of Blob,File,Table,Queue")]
        $service,
        [Parameter(Position=4, Mandatory = $true, HelpMessage = "Enter resource type(s) - one or more of Service,Container,Object")]
        $resourceType,
        [Parameter(Position=5, Mandatory = $true, HelpMessage = "Enter permission string")]
        [string]$permission,
        [Parameter(Position=6, Mandatory = $false, HelpMessage = "Enter validity in hours")]
        [int]$validityHours
    )

    if(-not $validityHours){
        $validityHours = 2
    }
    # Temporarily switch to storage account subscription
    $prevContext = Get-AzContext
    $_ = Set-AzContext -Subscription $subscriptionName; # Assign to dummy variable to avoid conmtext being returned
    # Generate SAS token
    $accountKey = (Get-AzStorageAccountKey -ResourceGroupName $resourceGroup -AccountName $accountName).Value[0];
    $accountContext = (New-AzStorageContext -StorageAccountName $accountName -StorageAccountKey $accountKey);
    $expiryTime = ((Get-Date) + (New-TimeSpan -Hours $validityHours))
    $sasToken = (New-AzStorageAccountSASToken -Service $service -ResourceType $resourceType -Permission $permission -ExpiryTime $expiryTime -Context $accountContext);

    # Switch back to previous subscription
    $_ = Set-AzContext -Context $prevContext;
    return $sasToken
}
Export-ModuleMember -Function New-AccountSasToken

function New-ReadOnlyAccountSasToken {
    param(
        [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter subscription name")]
        [string]$subscriptionName,
        [Parameter(Position=1, Mandatory = $true, HelpMessage = "Enter storage account resource group")]
        [string]$resourceGroup,
        [Parameter(Position=2, Mandatory = $true, HelpMessage = "Enter storage account name")]
        [string]$accountName
    )
    return New-AccountSasToken -subscriptionName "$subscriptionName" `
                                -resourceGroup "$resourceGroup" `
                                -accountName "$accountName" `
                                -service Blob,File `
                                -resourceType Service,Container,Object `
                                -permission "rl"
}
Export-ModuleMember -Function New-ReadOnlyAccountSasToken