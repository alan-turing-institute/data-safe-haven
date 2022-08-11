Import-Module Az.Network -ErrorAction Stop
Import-Module $PSScriptRoot/Logging -ErrorAction Stop


# Create a firewall if it does not exist
# --------------------------------------
function Deploy-Firewall {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of public IP address to deploy")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of virtual network containing the 'AzureFirewall' subnet")]
        [string]$VirtualNetworkName,
        [Parameter(Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
        [string]$Location,
        [Parameter(Mandatory = $false, HelpMessage = "Force deallocation and reallocation of Firewall")]
        [switch]$ForceReallocation
    )
    # Ensure Firewall public IP address exists
    $publicIp = Deploy-PublicIpAddress -Name "${Name}-PIP" -ResourceGroupName $ResourceGroupName -Location $Location -AllocationMethod Static -Sku "Standard"  # NB. Azure Firewall requires a 'Standard' public IP
    Add-LogMessage -Level Info "Ensuring that firewall '$Name' exists..."
    $firewall = Get-AzFirewall -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating firewall '$Name'"
        $firewall = New-AzFirewall -Name $Name -ResourceGroupName $ResourceGroupName -Location $Location -VirtualNetworkName $VirtualNetworkName -PublicIpName $publicIp.Name -EnableDnsProxy
        if ($?) {
            Add-LogMessage -Level Success "Created firewall '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create firewall '$Name'!"
        }
    }
    # Ensure Firewall is running
    $firewall = Start-Firewall -Name $Name -ResourceGroupName $ResourceGroupName -VirtualNetworkName $VirtualNetworkName
    return $firewall
}
Export-ModuleMember -Function Deploy-Firewall


# Deploy an application rule to a firewall
# ----------------------------------------
function Deploy-FirewallApplicationRule {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of application rule")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of application rule collection to add this to")]
        [string]$CollectionName,
        [Parameter(Mandatory = $true, HelpMessage = "Firewall to add this collection to")]
        $Firewall,
        [Parameter(Mandatory = $true, HelpMessage = "Address of source")]
        [string]$SourceAddress,
        [Parameter(Mandatory = $true, ParameterSetName = "ByFqdn", HelpMessage = "Protocol to use")]
        [string]$Protocol,
        [Parameter(Mandatory = $false, HelpMessage = "Priority of this application rule collection")]
        [string]$Priority,
        [Parameter(Mandatory = $false, HelpMessage = "Whether these rules will allow or deny access to the specified resources")]
        [ValidateSet("Allow", "Deny")]
        [string]$ActionType,
        [Parameter(Mandatory = $true, ParameterSetName = "ByFqdn", HelpMessage = "List of FQDNs to apply rule to. Supports '*' wildcard at start of each FQDN.")]
        [string]$TargetFqdn,
        [Parameter(Mandatory = $true, ParameterSetName = "ByTag", HelpMessage = "List of FQDN tags to apply rule to. An FQN tag represents a set of Azure-curated FQDNs.")]
        [string]$TargetTag,
        [Parameter(HelpMessage = "Make change to the local firewall object only. Useful when making lots of updates in a row. You will need to make a separate call to 'Set-AzFirewall' to apply the changes to the actual Azure firewall.")]
        [switch]$LocalChangeOnly
    )
    Add-LogMessage -Level Info "[ ] Ensuring that application rule '$Name' exists..."
    $params = @{}
    if ($TargetTag) { $params["FqdnTag"] = $TargetTag }
    if ($TargetFqdn) { $params["TargetFqdn"] = $TargetFqdn }
    $rule = New-AzFirewallApplicationRule -Name $Name -SourceAddress $SourceAddress -Protocol $Protocol @params
    try {
        $ruleCollection = $Firewall.GetApplicationRuleCollectionByName($CollectionName)
        # Overwrite any existing rule with the same name to ensure that we can update if settings have changed
        $existingRule = $ruleCollection.Rules | Where-Object { $_.Name -eq $Name }
        if ($existingRule) { $ruleCollection.RemoveRuleByName($Name) }
        $ruleCollection.AddRule($rule)
        # Remove the existing rule collection to ensure that we can update with the new rule
        $Firewall.RemoveApplicationRuleCollectionByName($ruleCollection.Name)
    } catch [System.Management.Automation.MethodInvocationException] {
        $ruleCollection = New-AzFirewallApplicationRuleCollection -Name $CollectionName -Priority $Priority -ActionType $ActionType -Rule $rule
        if (-not $?) {
            Add-LogMessage -Level Fatal "Failed to create application rule collection '$CollectionName'!"
        }
    }
    try {
        $null = $Firewall.ApplicationRuleCollections.Add($ruleCollection)
        if ($LocalChangeOnly) {
            Add-LogMessage -Level InfoSuccess "Added application rule '$Name' to set of rules to update on remote firewall."
        } else {
            $Firewall = Set-AzFirewall -AzureFirewall $Firewall -ErrorAction Stop
            Add-LogMessage -Level Success "Ensured that application rule '$Name' exists and updated remote firewall."
        }
    } catch [System.Management.Automation.MethodInvocationException], [Microsoft.Rest.Azure.CloudException] {
        Add-LogMessage -Level Fatal "Failed to ensure that application rule '$Name' exists!"
    }
    return $Firewall
}
Export-ModuleMember -Function Deploy-FirewallApplicationRule


# Deploy a network rule collection to a firewall
# ----------------------------------------------
function Deploy-FirewallNetworkRule {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of network rule")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of network rule collection to add this to")]
        [string]$CollectionName,
        [Parameter(Mandatory = $true, HelpMessage = "Firewall to add this collection to")]
        $Firewall,
        [Parameter(Mandatory = $true, HelpMessage = "Address(es) of source")]
        [string]$SourceAddress,
        [Parameter(Mandatory = $true, ParameterSetName = "ByAddress", HelpMessage = "Address(es) of destination")]
        [string]$DestinationAddress,
        [Parameter(Mandatory = $true, ParameterSetName = "ByFQDN", HelpMessage = "FQDN(s) of destination")]
        [string]$DestinationFqdn,
        [Parameter(Mandatory = $true, HelpMessage = "Port(s) of destination")]
        [string]$DestinationPort,
        [Parameter(Mandatory = $true, HelpMessage = "Protocol to use")]
        [string]$Protocol,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        [string]$Priority,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        [ValidateSet("Allow", "Deny")]
        [string]$ActionType,
        [Parameter(HelpMessage = "Make change to the local firewall object only. Useful when making lots of updates in a row. You will need to make a separate call to 'Set-AzFirewall' to apply the changes to the actual Azure firewall.")]
        [switch]$LocalChangeOnly
    )
    Add-LogMessage -Level Info "[ ] Ensuring that traffic from '$SourceAddress' to '$($DestinationAddress ? $DestinationAddress : $DestinationFqdn)' on ports '$DestinationPort' over $Protocol is set on $($Firewall.Name)..."
    $params = @{}
    if ($DestinationAddress) { $params["DestinationAddress"] = $DestinationAddress }
    if ($DestinationFqdn) { $params["DestinationFqdn"] = $DestinationFqdn }
    $rule = New-AzFirewallNetworkRule -Name $Name -SourceAddress $SourceAddress -DestinationPort $DestinationPort -Protocol $Protocol @params
    try {
        $ruleCollection = $Firewall.GetNetworkRuleCollectionByName($CollectionName)
        Add-LogMessage -Level InfoSuccess "Network rule collection '$CollectionName' already exists"
        # Overwrite any existing rule with the same name to ensure that we can update if settings have changed
        $existingRule = $ruleCollection.Rules | Where-Object { $_.Name -eq $Name }
        if ($existingRule) { $ruleCollection.RemoveRuleByName($Name) }
        $ruleCollection.AddRule($rule)
        # Remove the existing rule collection to ensure that we can update with the new rule
        $Firewall.RemoveNetworkRuleCollectionByName($ruleCollection.Name)
    } catch [System.Management.Automation.MethodInvocationException] {
        $ruleCollection = New-AzFirewallNetworkRuleCollection -Name $CollectionName -Priority $Priority -ActionType $ActionType -Rule $rule
        if (-not $?) {
            Add-LogMessage -Level Fatal "Failed to create network rule collection '$CollectionName'!"
        }
    }
    try {
        $null = $Firewall.NetworkRuleCollections.Add($ruleCollection)
        if ($LocalChangeOnly) {
            Add-LogMessage -Level InfoSuccess "Added network rule '$Name' to set of rules to update on remote firewall."
        } else {
            $Firewall = Set-AzFirewall -AzureFirewall $Firewall -ErrorAction Stop
            Add-LogMessage -Level Success "Ensured that network rule '$Name' exists and updated remote firewall."
        }
    } catch [System.Management.Automation.MethodInvocationException], [Microsoft.Rest.Azure.CloudException] {
        Add-LogMessage -Level Fatal "Failed to ensure that network rule '$Name' exists!"
    }
    return $Firewall
}
Export-ModuleMember -Function Deploy-FirewallNetworkRule


# Create a virtual machine NIC
# ----------------------------
function Deploy-NetworkInterface {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of VM NIC to deploy")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Subnet to attach this NIC to")]
        [Microsoft.Azure.Commands.Network.Models.PSSubnet]$Subnet,
        [Parameter(Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
        [string]$Location,
        [Parameter(Mandatory = $false, HelpMessage = "Public IP address for this NIC")]
        [ValidateSet("Dynamic", "Static")]
        [string]$PublicIpAddressAllocation = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Private IP address for this NIC")]
        [string]$PrivateIpAddress = $null
    )
    Add-LogMessage -Level Info "Ensuring that VM network card '$Name' exists..."
    $vmNic = Get-AzNetworkInterface -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating VM network card '$Name'"
        $ipAddressParams = @{}
        if ($PublicIpAddressAllocation) {
            $PublicIpAddress = Deploy-PublicIpAddress -Name "$Name-PIP" -ResourceGroupName $ResourceGroupName -AllocationMethod $PublicIpAddressAllocation -Location $Location
            $ipAddressParams["PublicIpAddress"] = $PublicIpAddress
        }
        if ($PrivateIpAddress) { $ipAddressParams["PrivateIpAddress"] = $PrivateIpAddress }
        $vmNic = New-AzNetworkInterface -Name $Name -ResourceGroupName $ResourceGroupName -Subnet $Subnet -IpConfigurationName "ipconfig-$Name" -Location $Location @ipAddressParams -Force
        if ($?) {
            Add-LogMessage -Level Success "Created VM network card '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create VM network card '$Name'!"
        }
    } else {
        Add-LogMessage -Level InfoSuccess "VM network card '$Name' already exists"
    }
    return $vmNic
}
Export-ModuleMember -Function Deploy-NetworkInterface


# Create a public IP address if it does not exist
# -----------------------------------------------
function Deploy-PublicIpAddress {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of public IP address to deploy")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Allocation method (static or dynamic)")]
        [ValidateSet("Dynamic", "Static")]
        [string]$AllocationMethod,
        [Parameter(Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
        [string]$Location,
        [Parameter(Mandatory = $false, HelpMessage = "SKU ('Basic' or 'Standard')")]
        [ValidateSet("Basic", "Standard")]
        [string]$Sku = "Basic"
    )
    Add-LogMessage -Level Info "Ensuring that public IP address '$Name' exists..."
    $publicIpAddress = Get-AzPublicIpAddress -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating public IP address '$Name'"
        $ipAddressParams = @{}
        if ($Sku -eq "Standard") {
            $ipAddressParams["Zone"] = @(1, 2, 3)
        }
        $publicIpAddress = New-AzPublicIpAddress -Name $Name -ResourceGroupName $ResourceGroupName -AllocationMethod $AllocationMethod -Location $Location -Sku $Sku @ipAddressParams
        if ($?) {
            Add-LogMessage -Level Success "Created public IP address '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create public IP address '$Name'!"
        }
    } else {
        Add-LogMessage -Level InfoSuccess "Public IP address '$Name' already exists"
    }
    return $publicIpAddress
}
Export-ModuleMember -Function Deploy-PublicIpAddress
