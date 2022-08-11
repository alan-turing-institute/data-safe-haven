Import-Module Az.Accounts -ErrorAction Stop
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


# Peer two vnets
# --------------
function Set-VnetPeering {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of the first of two VNets to peer")]
        [string]$Vnet1Name,
        [Parameter(Mandatory = $true, HelpMessage = "Resource group name of the first VNet")]
        [string]$Vnet1ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Subscription name of the first VNet")]
        [string]$Vnet1SubscriptionName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of the second of two VNets to peer")]
        [string]$Vnet2Name,
        [Parameter(Mandatory = $true, HelpMessage = "Resource group name of the second VNet")]
        [string]$Vnet2ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Subscription name of the second VNet")]
        [string]$Vnet2SubscriptionName,
        [Parameter(Mandatory = $false, HelpMessage = "Enable use of remote gateway from one of the two VNets")]
        [ValidateSet(1, 2)]
        [int]$AllowRemoteGatewayFromVNet
    )
    try {
        # Get original subscription
        $originalContext = Get-AzContext
        Add-LogMessage -Level Info "Peering virtual networks ${Vnet1Name} and ${Vnet2Name}."

        # Get virtual networks
        $null = Set-AzContext -SubscriptionId $Vnet1SubscriptionName -ErrorAction Stop
        $vnet1 = Get-AzVirtualNetwork -Name $Vnet1Name -ResourceGroupName $Vnet1ResourceGroup -ErrorAction Stop
        $null = Set-AzContext -SubscriptionId $Vnet2SubscriptionName -ErrorAction Stop
        $vnet2 = Get-AzVirtualNetwork -Name $Vnet2Name -ResourceGroupName $Vnet2ResourceGroup -ErrorAction Stop

        # Remove any existing peerings
        $null = Set-AzContext -SubscriptionId $Vnet1SubscriptionName -ErrorAction Stop
        $existingPeering = Get-AzVirtualNetworkPeering -VirtualNetworkName $Vnet1Name -ResourceGroupName $Vnet1ResourceGroup | Where-Object { $_.RemoteVirtualNetwork.Id -eq $vnet2.Id }
        if ($existingPeering) {
            $existingPeering | Remove-AzVirtualNetworkPeering -Force -ErrorAction Stop
        }
        $null = Set-AzContext -SubscriptionId $Vnet2SubscriptionName -ErrorAction Stop
        $existingPeering = Get-AzVirtualNetworkPeering -VirtualNetworkName $Vnet2Name -ResourceGroupName $Vnet2ResourceGroup | Where-Object { $_.RemoteVirtualNetwork.Id -eq $vnet1.Id }
        if ($existingPeering) {
            $existingPeering | Remove-AzVirtualNetworkPeering -Force -ErrorAction Stop
        }

        # Set remote gateway parameters if requested
        $paramsVnet1 = @{}
        $paramsVnet2 = @{}
        if ($AllowRemoteGatewayFromVNet) {
            if ($AllowRemoteGatewayFromVNet -eq 1) {
                $paramsVnet1["AllowGatewayTransit"] = $true
                $paramsVnet2["UseRemoteGateways"] = $true
            } elseif ($AllowRemoteGatewayFromVNet -eq 2) {
                $paramsVnet1["UseRemoteGateways"] = $true
                $paramsVnet2["AllowGatewayTransit"] = $true
            }
        }

        # Create peering in the direction VNet1 -> VNet2
        $null = Set-AzContext -SubscriptionId $Vnet1SubscriptionName -ErrorAction Stop
        $peeringName = "PEER_${Vnet2Name}"
        Add-LogMessage -Level Info "[ ] Adding peering '$peeringName' to virtual network ${Vnet1Name}."
        $null = Add-AzVirtualNetworkPeering -Name "$peeringName" -VirtualNetwork $vnet1 -RemoteVirtualNetworkId $vnet2.Id @paramsVnet1 -ErrorAction Stop
        if ($?) {
            Add-LogMessage -Level Success "Adding peering '$peeringName' succeeded"
        } else {
            Add-LogMessage -Level Fatal "Adding peering '$peeringName' failed!"
        }
        # Create peering in the direction VNet2 -> VNet1
        $null = Set-AzContext -SubscriptionId $Vnet2SubscriptionName -ErrorAction Stop
        $peeringName = "PEER_${Vnet1Name}"
        Add-LogMessage -Level Info "[ ] Adding peering '$peeringName' to virtual network ${Vnet2Name}."
        $null = Add-AzVirtualNetworkPeering -Name "$peeringName" -VirtualNetwork $vnet2 -RemoteVirtualNetworkId $vnet1.Id @paramsVnet2 -ErrorAction Stop
        if ($?) {
            Add-LogMessage -Level Success "Adding peering '$peeringName' succeeded"
        } else {
            Add-LogMessage -Level Fatal "Adding peering '$peeringName' failed!"
        }
    } finally {
        # Switch back to original subscription
        $null = Set-AzContext -Context $originalContext -ErrorAction Stop
    }
}
Export-ModuleMember -Function Set-VnetPeering


# Update NSG rule to match a given configuration
# ----------------------------------------------
function Update-NetworkSecurityGroupRule {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of NSG rule to update")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of NSG that this rule belongs to")]
        [string]$NetworkSecurityGroup,
        [Parameter(Mandatory = $false, HelpMessage = "Rule Priority")]
        $Priority = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Rule direction")]
        [ValidateSet("Inbound", "Outbound")]
        [string]$Direction = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Rule access type")]
        [string]$Access = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Rule protocol")]
        [string]$Protocol = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Rule source address prefix")]
        [string]$SourceAddressPrefix = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Rule source port range")]
        [string]$SourcePortRange = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Rule destination address prefix")]
        [string]$DestinationAddressPrefix = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Rule destination port range")]
        [string]$DestinationPortRange = $null
    )
    # Load any unspecified parameters from the existing rule
    try {
        $ruleBefore = Get-AzNetworkSecurityRuleConfig -Name $Name -NetworkSecurityGroup $NetworkSecurityGroup
        $Description = $ruleBefore.Description
        if ($null -eq $Priority) { $Priority = $ruleBefore.Priority }
        if ($null -eq $Direction) { $Direction = $ruleBefore.Direction }
        if ($null -eq $Access) { $Access = $ruleBefore.Access }
        if ($null -eq $Protocol) { $Protocol = $ruleBefore.Protocol }
        if ($null -eq $SourceAddressPrefix) { $SourceAddressPrefix = $ruleBefore.SourceAddressPrefix }
        if ($null -eq $SourcePortRange) { $SourcePortRange = $ruleBefore.SourcePortRange }
        if ($null -eq $DestinationAddressPrefix) { $DestinationAddressPrefix = $ruleBefore.DestinationAddressPrefix }
        if ($null -eq $DestinationPortRange) { $DestinationPortRange = $ruleBefore.DestinationPortRange }
        # Print the update we're about to make
        if ($Direction -eq "Inbound") {
            Add-LogMessage -Level Info "[ ] Updating '$Name' rule on '$($NetworkSecurityGroup.Name)' to '$Access' access from '$SourceAddressPrefix'"
        } else {
            Add-LogMessage -Level Info "[ ] Updating '$Name' rule on '$($NetworkSecurityGroup.Name)' to '$Access' access to '$DestinationAddressPrefix'"
        }
        # Update rule and NSG (both are required)
        $null = Set-AzNetworkSecurityRuleConfig -NetworkSecurityGroup $NetworkSecurityGroup `
                                                -Name "$Name" `
                                                -Description "$Description" `
                                                -Priority "$Priority" `
                                                -Direction "$Direction" `
                                                -Access "$Access" `
                                                -Protocol "$Protocol" `
                                                -SourceAddressPrefix $SourceAddressPrefix `
                                                -SourcePortRange $SourcePortRange `
                                                -DestinationAddressPrefix $DestinationAddressPrefix `
                                                -DestinationPortRange $DestinationPortRange | Set-AzNetworkSecurityGroup
        # Apply the rule and validate whether it succeeded
        $ruleAfter = Get-AzNetworkSecurityRuleConfig -Name $Name -NetworkSecurityGroup $NetworkSecurityGroup
        if (($ruleAfter.Name -eq $Name) -and
            ($ruleAfter.Description -eq $Description) -and
            ($ruleAfter.Priority -eq $Priority) -and
            ($ruleAfter.Direction -eq $Direction) -and
            ($ruleAfter.Access -eq $Access) -and
            ($ruleAfter.Protocol -eq $Protocol) -and
            ("$($ruleAfter.SourceAddressPrefix)" -eq "$SourceAddressPrefix") -and
            ("$($ruleAfter.SourcePortRange)" -eq "$SourcePortRange") -and
            ("$($ruleAfter.DestinationAddressPrefix)" -eq "$DestinationAddressPrefix") -and
            ("$($ruleAfter.DestinationPortRange)" -eq "$DestinationPortRange")) {
            if ($Direction -eq "Inbound") {
                Add-LogMessage -Level Success "'$Name' on '$($NetworkSecurityGroup.Name)' will now '$($ruleAfter.Access)' access from '$($ruleAfter.SourceAddressPrefix)'"
            } else {
                Add-LogMessage -Level Success "'$Name' on '$($NetworkSecurityGroup.Name)' will now '$($ruleAfter.Access)' access to '$($ruleAfter.DestinationAddressPrefix)'"
            }
        } else {
            if ($Direction -eq "Inbound") {
                Add-LogMessage -Level Failure "'$Name' on '$($NetworkSecurityGroup.Name)' will now '$($ruleAfter.Access)' access from '$($ruleAfter.SourceAddressPrefix)'"
            } else {
                Add-LogMessage -Level Failure "'$Name' on '$($NetworkSecurityGroup.Name)' will now '$($ruleAfter.Access)' access to '$($ruleAfter.DestinationAddressPrefix)'"
            }
        }
        # Return the rule
        return $ruleAfter
    } catch [System.Management.Automation.ValidationMetadataException] {
        Add-LogMessage -Level Fatal "Could not find rule '$Name' on NSG '$($NetworkSecurityGroup.Name)'"
    }
}
Export-ModuleMember -Function Update-NetworkSecurityGroupRule