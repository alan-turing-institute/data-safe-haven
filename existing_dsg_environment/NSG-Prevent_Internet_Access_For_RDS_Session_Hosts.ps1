#Resources
$resourceGroupName = "RESOURCEGROUP" # Resource group of RDS session hosts
$location = "uk south"
$region = "uksouth"
$nsgName = "NSGNAME" # NSG Name

# Sign-in with Azure account credentials
#Login-AzureRmAccount

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

# Download current list of Azure Public IP ranges
write-Host -ForegroundColor Cyan "Getting latest Azure services IP addresses fron the internet..."
$downloadUri = "https://www.microsoft.com/en-in/download/confirmation.aspx?id=41653"
$downloadPage = Invoke-WebRequest -Uri $downloadUri
$xmlFileUri = ($downloadPage.RawContent.Split('"') -like "https://*PublicIps*")[0]
$response = Invoke-WebRequest -Uri $xmlFileUri

# Get list of regions & public IP ranges
[xml]$xmlResponse = [System.Text.Encoding]::UTF8.GetString($response.Content)
$regions = $xmlResponse.AzurePublicIpAddresses.Region

# Select Azure regions for which to define NSG rules
#$selectedRegions = $regions.Name | Out-GridView -Title "Select Azure Datacenter...." -PassThru
$ipRange = ( $regions | where-object Name -In $region ).IpRange

# Build NSG rules
write-Host -ForegroundColor Cyan "Creating the NSG and applying the rules..."
$rules = @()
$rulePriority = 100

ForEach ($subnet in $ipRange.Subnet) {

    $ruleName = "Allow_Azure_Out_" + $subnet.Replace("/","-")
    
    $rules += 
        New-AzureRmNetworkSecurityRuleConfig `
            -Name $ruleName `
            -Description "Allow outbound to Azure $subnet" `
            -Access Allow `
            -Protocol * `
            -Direction Outbound `
            -Priority $rulePriority `
            -SourceAddressPrefix VirtualNetwork `
            -SourcePortRange * `
            -DestinationAddressPrefix "$subnet" `
            -DestinationPortRange *

    $rulePriority++

}

# Define deny rule for all other traffic to Internet

$rules += 
    New-AzureRmNetworkSecurityRuleConfig `
        -Name "Deny_Internet_Out" `
        -Description "Deny outbound to Internet" `
        -Access Deny `
        -Protocol * `
        -Direction Outbound `
        -Priority 4001 `
        -SourceAddressPrefix VirtualNetwork `
        -SourcePortRange * `
        -DestinationAddressPrefix Internet `
        -DestinationPortRange *

# Create Network Security Group

$nsg = New-AzureRmNetworkSecurityGroup -Name "$nsgName" -ResourceGroupName $resourceGroupName -Location $location -SecurityRules $rules

write-Host -ForegroundColor Cyan "Updating VM..."
$vm1nic = Get-AzureRmNetworkInterface -ResourceGroupName $resourceGroupName -Name "VM1_NIC1"
$vm1nic.NetworkSecurityGroup = $nsg
Set-AzureRmNetworkInterface -NetworkInterface $vm1nic

write-Host -ForegroundColor Cyan "Updating VM..."
$vm2nic = Get-AzureRmNetworkInterface -ResourceGroupName $resourceGroupName -Name "VM2_NIC1"
$vm2nic.NetworkSecurityGroup = $nsg
Set-AzureRmNetworkInterface -NetworkInterface $vm2nic