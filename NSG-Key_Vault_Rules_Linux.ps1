#Resources
$resourceGroupName = "RESOURCEGROUP" # Resource group of the Linux servers
$location = "uk south"
$region = "uksouth"
$nsgName = "NSGNAME" # NSG Name

#Select subscription
write-Host -ForegroundColor Cyan "Select the correct subscription..."

$subscription = (
    Get-AzureRmSubscription |
    Sort-Object -Property Name |
    Select-Object -Property Name,Id |
    Out-GridView -OutputMode Single -Title 'Select an subscription'
).name

Select-AzureRmSubscription -SubscriptionName $subscription
write-Host -ForegroundColor Green "Ok, lets go!"

Read-Host -Prompt "Check that the subscription has been selected above, press any key to continue or Ctrl+C to abort"

$nsg = Get-AzureRmNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Name $nsgName

Write-Host "Creating rule for Microsoft Online Access....." -ForegroundColor Cyan
Add-AzureRmNetworkSecurityRuleConfig   -NetworkSecurityGroup $nsg `
                                       -Name KeyVault_Microsoft_Online_Login `
                                       -Description "Required for Key Vault access" `
                                       -Access Allow `
                                       -Protocol Tcp `
                                       -Direction Outbound `
                                       -Priority 200 `
                                       -SourceAddressPrefix VirtualNetwork `
                                       -SourcePortRange * `
                                       -DestinationAddressPrefix "104.41.216.16","104.41.216.18","40.112.64.18","40.112.64.25" `
                                       -DestinationPortRange 443
Set-AzureRmNetworkSecurityGroup -NetworkSecurityGroup $nsg
Write-Host "Ok, Done!" -ForegroundColor Green

Write-Host "Creating rule Microsoft Azure management....." -ForegroundColor Cyan
Add-AzureRmNetworkSecurityRuleConfig   -NetworkSecurityGroup $nsg `
                                       -Name KeyVault_Management_Azure_Com `
                                       -Description "Required for Key Vault access" `
                                       -Access Allow `
                                       -Protocol Tcp `
                                       -Direction Outbound `
                                       -Priority 201 `
                                       -SourceAddressPrefix VirtualNetwork `
                                       -SourcePortRange * `
                                       -DestinationAddressPrefix 51.141.8.44 `
                                       -DestinationPortRange 443 
Set-AzureRmNetworkSecurityGroup -NetworkSecurityGroup $nsg
Write-Host "Ok, Done!" -ForegroundColor Green

# Change name to suit DSG and DestinationAddressPrefix to match IP address of Key Vault URI
Write-Host "Creating rule for Key Vault Web Application....." -ForegroundColor Cyan
Add-AzureRmNetworkSecurityRuleConfig   -NetworkSecurityGroup $nsg `
                                       -Name KeyVault_Azure_Key_Vault_DSG_Linux `
                                       -Description "Required for Key Vault access" `
                                       -Access Allow `
                                       -Protocol Tcp `
                                       -Direction Outbound `
                                       -Priority 202 `
                                       -SourceAddressPrefix VirtualNetwork `
                                       -SourcePortRange * `
                                       -DestinationAddressPrefix 0.0.0.0 `
                                       -DestinationPortRange 443 
Set-AzureRmNetworkSecurityGroup -NetworkSecurityGroup $nsg
Write-Host "Ok, Done!" -ForegroundColor Green
