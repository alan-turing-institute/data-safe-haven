Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Compute -ErrorAction Stop
Import-Module Az.Network -ErrorAction Stop
Import-Module $PSScriptRoot/DataStructures -ErrorAction Stop
Import-Module $PSScriptRoot/Logging -ErrorAction Stop


# Create network security group rule if it does not exist
# -------------------------------------------------------
function Add-NetworkSecurityGroupRule {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of network security group rule to deploy")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "A NetworkSecurityGroup object to apply this rule to")]
        [Microsoft.Azure.Commands.Network.Models.PSNetworkSecurityGroup]$NetworkSecurityGroup,
        [Parameter(Mandatory = $true, HelpMessage = "A description of the network security rule")]
        [string]$Description,
        [Parameter(Mandatory = $true, HelpMessage = "Specifies the priority of a rule configuration")]
        [Uint32]$Priority,
        [Parameter(Mandatory = $true, HelpMessage = "Specifies whether a rule is evaluated on incoming or outgoing traffic")]
        [string]$Direction,
        [Parameter(Mandatory = $true, HelpMessage = "Specifies whether network traffic is allowed or denied")]
        [string]$Access,
        [Parameter(Mandatory = $true, HelpMessage = "Specifies the network protocol that a rule configuration applies to")]
        [string]$Protocol,
        [Parameter(Mandatory = $true, HelpMessage = "Source addresses. One or more of: a CIDR, an IP address range, a wildcard or an Azure tag (eg. VirtualNetwork)")]
        [string[]]$SourceAddressPrefix,
        [Parameter(Mandatory = $true, HelpMessage = "Source port or range. One or more of: an integer, a range of integers or a wildcard")]
        [string[]]$SourcePortRange,
        [Parameter(Mandatory = $true, HelpMessage = "Destination addresses. One or more of: a CIDR, an IP address range, a wildcard or an Azure tag (eg. VirtualNetwork)")]
        [string[]]$DestinationAddressPrefix,
        [Parameter(Mandatory = $true, HelpMessage = "Destination port or range. One or more of: an integer, a range of integers or a wildcard")]
        [string[]]$DestinationPortRange,
        [Parameter(Mandatory = $false, HelpMessage = "Print verbose logging messages")]
        [switch]$VerboseLogging = $false
    )
    try {
        if ($VerboseLogging) { Add-LogMessage -Level Info "Ensuring that NSG rule '$Name' exists on '$($NetworkSecurityGroup.Name)'..." }
        $null = Get-AzNetworkSecurityRuleConfig -Name $Name -NetworkSecurityGroup $NetworkSecurityGroup -ErrorVariable notExists -ErrorAction SilentlyContinue
        if ($notExists) {
            if ($VerboseLogging) { Add-LogMessage -Level Info "[ ] Creating NSG rule '$Name'" }
            try {
                $null = Add-AzNetworkSecurityRuleConfig -Name "$Name" `
                                                        -Access "$Access" `
                                                        -Description "$Description" `
                                                        -DestinationAddressPrefix $DestinationAddressPrefix `
                                                        -DestinationPortRange $DestinationPortRange `
                                                        -Direction "$Direction" `
                                                        -NetworkSecurityGroup $NetworkSecurityGroup `
                                                        -Priority $Priority `
                                                        -Protocol "$Protocol" `
                                                        -SourceAddressPrefix $SourceAddressPrefix `
                                                        -SourcePortRange $SourcePortRange `
                                                        -ErrorAction Stop | Set-AzNetworkSecurityGroup -ErrorAction Stop
                if ($VerboseLogging) { Add-LogMessage -Level Success "Created NSG rule '$Name'" }
            } catch {
                Add-LogMessage -Level Fatal "Failed to create NSG rule '$Name'!" -Exception $_.Exception
            }
        } else {
            if ($VerboseLogging) { Add-LogMessage -Level InfoSuccess "Updating NSG rule '$Name'" }
            $null = Set-AzNetworkSecurityRuleConfig -Name "$Name" `
                                                    -Access "$Access" `
                                                    -Description "$Description" `
                                                    -DestinationAddressPrefix $DestinationAddressPrefix `
                                                    -DestinationPortRange $DestinationPortRange `
                                                    -Direction "$Direction" `
                                                    -NetworkSecurityGroup $NetworkSecurityGroup `
                                                    -Priority $Priority `
                                                    -Protocol "$Protocol" `
                                                    -SourceAddressPrefix $SourceAddressPrefix `
                                                    -SourcePortRange $SourcePortRange `
                                                    -ErrorAction Stop | Set-AzNetworkSecurityGroup -ErrorAction Stop
        }
    } catch [Microsoft.Azure.Commands.Network.Common.NetworkCloudException] {
        Add-LogMessage -Level Fatal "Azure network connection failed!" -Exception $_.Exception
    }
}
Export-ModuleMember -Function Add-NetworkSecurityGroupRule


# Associate a VM to an NSG
# ------------------------
function Add-VmToNSG {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of virtual machine")]
        [string]$VMName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of network security group")]
        [string]$NSGName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group that the VM belongs to")]
        [string]$VmResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group that the NSG belongs to")]
        [string]$NsgResourceGroupName,
        [Parameter(Mandatory = $false, HelpMessage = "Allow failures, printing a warning message instead of throwing an exception")]
        [switch]$WarnOnFailure
    )
    $LogLevel = $WarnOnFailure ? "Warning" : "Fatal"
    Add-LogMessage -Level Info "[ ] Associating $VMName with $NSGName..."
    $matchingVMs = Get-AzVM -Name $VMName -ResourceGroupName $VmResourceGroupName -ErrorAction SilentlyContinue
    if ($matchingVMs.Count -ne 1) { Add-LogMessage -Level $LogLevel "Found $($matchingVMs.Count) VM(s) called $VMName!"; return }
    $networkCard = Get-AzNetworkInterface | Where-Object { $_.VirtualMachine.Id -eq $matchingVMs[0].Id }
    $nsg = Get-AzNetworkSecurityGroup -Name $NSGName -ResourceGroupName $NsgResourceGroupName -ErrorAction SilentlyContinue
    if ($nsg.Count -ne 1) { Add-LogMessage -Level $LogLevel "Found $($nsg.Count) NSG(s) called $NSGName!"; return }
    $networkCard.NetworkSecurityGroup = $nsg
    $null = ($networkCard | Set-AzNetworkInterface)
    if ($?) {
        Start-Sleep -Seconds 10  # Allow NSG association to propagate
        Add-LogMessage -Level Success "NSG association succeeded"
    } else {
        Add-LogMessage -Level Fatal "NSG association failed!"
    }
}
Export-ModuleMember -Function Add-VmToNSG


# Create a private endpoint for an automation account
# ---------------------------------------------------
function Deploy-AutomationAccountEndpoint {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Automation account to create the private endpoint for")]
        [Microsoft.Azure.Commands.Automation.Model.AutomationAccount]$Account,
        [Parameter(Mandatory = $true, HelpMessage = "Subnet to deploy into")]
        [Microsoft.Azure.Commands.Network.Models.PSSubnet]$Subnet
    )
    $endpoint = Deploy-PrivateEndpoint -Name "$($Account.AutomationAccountName)-endpoint".ToLower() `
                                       -GroupId "DSCAndHybridWorker" `
                                       -Location $Account.Location `
                                       -PrivateLinkServiceId (Get-ResourceId $Account.AutomationAccountName) `
                                       -ResourceGroupName $Account.ResourceGroupName `
                                       -Subnet $Subnet
    return $endpoint
}
Export-ModuleMember -Function Deploy-AutomationAccountEndpoint


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
        [Parameter(Mandatory = $false, HelpMessage = "Whether these rules will allow or deny access to the specified resources")]
        [ValidateSet("Allow", "Deny")]
        [string]$ActionType,
        [Parameter(Mandatory = $true, HelpMessage = "Name of application rule collection to add this to")]
        [string]$CollectionName,
        [Parameter(Mandatory = $true, HelpMessage = "Firewall to add this collection to")]
        [Microsoft.Azure.Commands.Network.Models.PSAzureFirewall]$Firewall,
        [Parameter(HelpMessage = "Make change to the local firewall object only. Useful when making lots of updates in a row. You will need to make a separate call to 'Set-AzFirewall' to apply the changes to the actual Azure firewall.")]
        [switch]$LocalChangeOnly,
        [Parameter(Mandatory = $true, HelpMessage = "Name of application rule")]
        [string]$Name,
        [Parameter(Mandatory = $false, HelpMessage = "Priority of this application rule collection")]
        [UInt32]$Priority,
        [Parameter(Mandatory = $true, ParameterSetName = "ByFqdn", HelpMessage = "Protocol to use")]
        [string[]]$Protocol,
        [Parameter(Mandatory = $true, HelpMessage = "Address of source")]
        [string[]]$SourceAddress,
        [Parameter(Mandatory = $true, ParameterSetName = "ByFqdn", HelpMessage = "List of FQDNs to apply rule to. Supports '*' wildcard at start of each FQDN.")]
        [string[]]$TargetFqdn,
        [Parameter(Mandatory = $true, ParameterSetName = "ByTag", HelpMessage = "List of FQDN tags to apply rule to. An FQN tag represents a set of Azure-curated FQDNs.")]
        [string[]]$TargetTag
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
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        [ValidateSet("Allow", "Deny")]
        [string]$ActionType,
        [Parameter(Mandatory = $true, HelpMessage = "Name of network rule collection to add this to")]
        [string]$CollectionName,
        [Parameter(Mandatory = $true, ParameterSetName = "ByAddress", HelpMessage = "Address(es) of destination")]
        [string[]]$DestinationAddress,
        [Parameter(Mandatory = $true, ParameterSetName = "ByFQDN", HelpMessage = "FQDN(s) of destination")]
        [string[]]$DestinationFqdn,
        [Parameter(Mandatory = $true, HelpMessage = "Port(s) of destination")]
        [string[]]$DestinationPort,
        [Parameter(Mandatory = $true, HelpMessage = "Firewall to add this collection to")]
        [Microsoft.Azure.Commands.Network.Models.PSAzureFirewall]$Firewall,
        [Parameter(HelpMessage = "Make change to the local firewall object only. Useful when making lots of updates in a row. You will need to make a separate call to 'Set-AzFirewall' to apply the changes to the actual Azure firewall.")]
        [switch]$LocalChangeOnly,
        [Parameter(Mandatory = $true, HelpMessage = "Name of network rule")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        [UInt32]$Priority,
        [Parameter(Mandatory = $true, HelpMessage = "Protocol to use")]
        [string[]]$Protocol,
        [Parameter(Mandatory = $true, HelpMessage = "Address(es) of source")]
        [string[]]$SourceAddress
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


# Create a private endpoint for an automation account
# ---------------------------------------------------
function Deploy-MonitorPrivateLinkScopeEndpoint {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Location to deploy the endpoint")]
        [string]$Location,
        [Parameter(Mandatory = $true, HelpMessage = "Private link scope to connect")]
        [Microsoft.Azure.Commands.Insights.OutputClasses.PSMonitorPrivateLinkScope]$PrivateLinkScope,
        [Parameter(Mandatory = $true, HelpMessage = "Subnet to deploy into")]
        [Microsoft.Azure.Commands.Network.Models.PSSubnet]$Subnet
    )
    $endpoint = Deploy-PrivateEndpoint -Name "$($PrivateLinkScope.Name)-endpoint".ToLower() `
                                       -GroupId "azuremonitor" `
                                       -Location $Location `
                                       -PrivateLinkServiceId $PrivateLinkScope.Id `
                                       -ResourceGroupName (Get-ResourceGroupName $PrivateLinkScope.Name) `
                                       -Subnet $Subnet
    return $endpoint
}
Export-ModuleMember -Function Deploy-MonitorPrivateLinkScopeEndpoint


# Create network security group if it does not exist
# --------------------------------------------------
function Deploy-NetworkSecurityGroup {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of network security group to deploy")]
        $Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        $ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
        $Location
    )
    Add-LogMessage -Level Info "Ensuring that network security group '$Name' exists..."
    $nsg = Get-AzNetworkSecurityGroup -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating network security group '$Name'"
        $nsg = New-AzNetworkSecurityGroup -Name $Name -Location $Location -ResourceGroupName $ResourceGroupName -Force
        if ($?) {
            Add-LogMessage -Level Success "Created network security group '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create network security group '$Name'!"
        }
    } else {
        Add-LogMessage -Level InfoSuccess "Network security group '$Name' already exists"
    }
    return $nsg
}
Export-ModuleMember -Function Deploy-NetworkSecurityGroup


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


# Create a private endpoint
# -------------------------
function Deploy-PrivateEndpoint {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Group ID for this endpoint")]
        [string]$GroupId,
        [Parameter(Mandatory = $true, HelpMessage = "Location to deploy the endpoint")]
        [string]$Location,
        [Parameter(Mandatory = $true, HelpMessage = "Name of the endpoint")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "ID of the service to link against")]
        [string]$PrivateLinkServiceId,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Subnet to deploy into")]
        [Microsoft.Azure.Commands.Network.Models.PSSubnet]$Subnet
    )
    Add-LogMessage -Level Info "Ensuring that private endpoint '$Name' exists..."
    $endpoint = Get-AzPrivateEndpoint -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating private endpoint '$Name'"
        $privateLinkServiceConnection = New-AzPrivateLinkServiceConnection -Name "${Name}LinkServiceConnection" -PrivateLinkServiceId $PrivateLinkServiceId -GroupId $GroupId
        $endpoint = New-AzPrivateEndpoint -Name $Name -ResourceGroupName $ResourceGroupName -Location $Location -Subnet $Subnet -PrivateLinkServiceConnection $privateLinkServiceConnection
        if ($?) {
            Add-LogMessage -Level Success "Created private endpoint '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create private endpoint '$Name'!"
        }
    } else {
        Add-LogMessage -Level InfoSuccess "Private endpoint '$Name' already exists"
    }
    return $endpoint
}
Export-ModuleMember -Function Deploy-PrivateEndpoint


# Create a route if it does not exist
# -----------------------------------
function Deploy-Route {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of route to deploy")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of route table that this route should be deployed into")]
        [string]$RouteTableName,
        [Parameter(Mandatory = $true, HelpMessage = "CIDR that this route applies to")]
        [string]$AppliesTo,
        [Parameter(Mandatory = $true, HelpMessage = "The firewall IP address or one of 'Internet', 'None', 'VirtualNetworkGateway', 'VnetLocal'")]
        [string]$NextHop
    )
    $routeTable = Get-AzRouteTable -Name $RouteTableName
    if (-not $routeTable) {
        Add-LogMessage -Level Fatal "No route table named '$routeTableName' was found in this subscription!"
    }
    Add-LogMessage -Level Info "[ ] Ensuring that route '$Name' exists..."
    $routeConfig = Get-AzRouteConfig -Name $Name -RouteTable $routeTable -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating route '$Name'"
        if (@('Internet', 'None', 'VirtualNetworkGateway', 'VnetLocal').Contains($NextHop)) {
            $null = Add-AzRouteConfig -Name $Name -RouteTable $routeTable -AddressPrefix $AppliesTo -NextHopType $NextHop | Set-AzRouteTable
        } else {
            $null = Add-AzRouteConfig -Name $Name -RouteTable $routeTable -AddressPrefix $AppliesTo -NextHopType "VirtualAppliance" -NextHopIpAddress $NextHop | Set-AzRouteTable
        }
        $routeConfig = Get-AzRouteConfig -Name $Name -RouteTable $routeTable
        if ($?) {
            Add-LogMessage -Level Success "Created route '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create route '$Name'!"
        }
    } else {
        Add-LogMessage -Level InfoSuccess "Route '$Name' already exists"
    }
    return $routeConfig
}
Export-ModuleMember -Function Deploy-Route


# Create a route table if it does not exist
# -----------------------------------------
function Deploy-RouteTable {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of public IP address to deploy")]
        $Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        $ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
        $Location
    )
    Add-LogMessage -Level Info "[ ] Ensuring that route table '$Name' exists..."
    $routeTable = Get-AzRouteTable -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating route table '$Name'"
        $routeTable = New-AzRouteTable -Name $Name -ResourceGroupName $ResourceGroupName -Location $Location -DisableBgpRoutePropagation
        if ($?) {
            Add-LogMessage -Level Success "Created route table '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create route table '$Name'!"
        }
    } else {
        Add-LogMessage -Level InfoSuccess "Route table '$Name' already exists"
    }
    return $routeTable
}
Export-ModuleMember -Function Deploy-RouteTable


# Create subnet if it does not exist
# ----------------------------------
function Deploy-Subnet {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of subnet to deploy")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "A VirtualNetwork object to deploy into")]
        $VirtualNetwork,
        [Parameter(Mandatory = $true, HelpMessage = "Specifies a range of IP addresses for a virtual network")]
        [string]$AddressPrefix
    )
    Add-LogMessage -Level Info "Ensuring that subnet '$Name' exists..."
    $null = Get-AzVirtualNetworkSubnetConfig -Name $Name -VirtualNetwork $VirtualNetwork -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating subnet '$Name'"
        $null = Add-AzVirtualNetworkSubnetConfig -Name $Name -VirtualNetwork $VirtualNetwork -AddressPrefix $AddressPrefix
        $VirtualNetwork = Set-AzVirtualNetwork -VirtualNetwork $VirtualNetwork
        if ($?) {
            Add-LogMessage -Level Success "Created subnet '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create subnet '$Name'!"
        }
    } else {
        Add-LogMessage -Level InfoSuccess "Subnet '$Name' already exists"
    }
    return Get-Subnet -Name $Name -VirtualNetworkName $VirtualNetwork.Name -ResourceGroupName $VirtualNetwork.ResourceGroupName
}
Export-ModuleMember -Function Deploy-Subnet


# Create virtual network if it does not exist
# ------------------------------------------
function Deploy-VirtualNetwork {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of virtual network to deploy")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Specifies a range of IP addresses for a virtual network")]
        [string]$AddressPrefix,
        [Parameter(Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
        [string]$Location,
        [Parameter(Mandatory = $false, HelpMessage = "DNS servers to attach to this virtual network")]
        [string[]]$DnsServer
    )
    Add-LogMessage -Level Info "Ensuring that virtual network '$Name' exists..."
    $vnet = Get-AzVirtualNetwork -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating virtual network '$Name'"
        $params = @{}
        if ($DnsServer) { $params["DnsServer"] = $DnsServer }
        $vnet = New-AzVirtualNetwork -Name $Name -Location $Location -ResourceGroupName $ResourceGroupName -AddressPrefix "$AddressPrefix" @params -Force
        if ($?) {
            Add-LogMessage -Level Success "Created virtual network '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create virtual network '$Name'!"
        }
    } else {
        Add-LogMessage -Level InfoSuccess "Virtual network '$Name' already exists"
    }
    return $vnet
}
Export-ModuleMember -Function Deploy-VirtualNetwork


# Create virtual network gateway if it does not exist
# ---------------------------------------------------
function Deploy-VirtualNetworkGateway {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of virtual network gateway to deploy")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
        [string]$Location,
        [Parameter(Mandatory = $true, HelpMessage = "ID of the public IP address to use")]
        [string]$PublicIpAddressId,
        [Parameter(Mandatory = $true, HelpMessage = "ID of the subnet to deploy into")]
        [string]$SubnetId,
        [Parameter(Mandatory = $true, HelpMessage = "Point-to-site certificate used by the gateway")]
        [string]$P2SCertificate,
        [Parameter(Mandatory = $true, HelpMessage = "Range of IP addresses used by the point-to-site VpnClient")]
        [string]$VpnClientAddressPool
    )
    Add-LogMessage -Level Info "Ensuring that virtual network gateway '$Name' exists..."
    $gateway = Get-AzVirtualNetworkGateway -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating virtual network gateway '$Name'..."
        $ipconfig = New-AzVirtualNetworkGatewayIpConfig -Name "shmgwipconf" -SubnetId $SubnetId -PublicIpAddressId $PublicIpAddressId
        $rootCertificate = New-AzVpnClientRootCertificate -Name "SafeHavenManagementP2SRootCert" -PublicCertData $P2SCertificate
        $gateway = New-AzVirtualNetworkGateway -Name $Name `
                                               -GatewaySku VpnGw1 `
                                               -GatewayType Vpn `
                                               -IpConfigurations $ipconfig `
                                               -Location $Location `
                                               -ResourceGroupName $ResourceGroupName `
                                               -VpnClientAddressPool $VpnClientAddressPool `
                                               -VpnClientProtocol IkeV2, SSTP `
                                               -VpnClientRootCertificates $rootCertificate `
                                               -VpnType RouteBased
        if ($?) {
            Add-LogMessage -Level Success "Created virtual network gateway '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create virtual network gateway '$Name'!"
        }
    } else {
        Add-LogMessage -Level InfoSuccess "Virtual network gateway '$Name' already exists"
    }
    return $gateway
}
Export-ModuleMember -Function Deploy-VirtualNetworkGateway


# Get next available IP address in range
# --------------------------------------
function Get-NextAvailableIpInRange {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Input range in CIDR notation")]
        [string]$IpRangeCidr,
        [Parameter(Mandatory = $false, HelpMessage = "Offset to apply before returning an IP address")]
        [int]$Offset,
        [Parameter(Mandatory = $false, HelpMessage = "Virtual network to check availability against")]
        [Microsoft.Azure.Commands.Network.Models.PSVirtualNetwork]$VirtualNetwork
    )
    # Get the start and end IP decimals for this CIDR range
    $ipStart, $ipEnd = Convert-CidrToIpAddressRange -IpRangeCidr $IpRangeCidr -AsDecimal

    # Return the full range or filter as required
    $ipAddresses = $ipStart..$ipEnd | ForEach-Object { Convert-DecimalToIpAddress -IpDecimal $_ } | Select-Object -Skip $Offset
    if ($VirtualNetwork) {
        $ipAddress = $ipAddresses | Where-Object { (Test-AzPrivateIPAddressAvailability -VirtualNetwork $VirtualNetwork -IPAddress $_).Available } | Select-Object -First 1
    } else {
        $ipAddress = $ipAddresses | Select-Object -First 1
    }
    if (-not $ipAddress) {
        Add-LogMessage -Level Fatal "There are no free IP addresses in '$IpRangeCidr' after applying the offset '$Offset'!"
    }
    return $ipAddress
}
Export-ModuleMember -Function Get-NextAvailableIpInRange


# Get subnet
# ----------
function Get-Subnet {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of subnet to retrieve")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of virtual network that this subnet belongs to")]
        [string]$VirtualNetworkName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group that this subnet belongs to")]
        [string]$ResourceGroupName
    )
    $virtualNetwork = Get-AzVirtualNetwork -Name $VirtualNetworkName -ResourceGroupName $ResourceGroupName
    return ($virtualNetwork.Subnets | Where-Object { $_.Name -eq $Name })[0]
}
Export-ModuleMember -Function Get-Subnet


# Get the virtual network that a given subnet belongs to
# ------------------------------------------------------
function Get-VirtualNetwork {
    param(
        [Parameter(Mandatory = $false, HelpMessage = "Name of virtual network to retrieve")]
        [string]$Name,
        [Parameter(Mandatory = $false, HelpMessage = "Name of resource group that this virtual network belongs to")]
        [string]$ResourceGroupName
    )
    $params = @{}
    if ($Name) { $params["Name"] = $Name }
    if ($ResourceGroupName) { $params["ResourceGroupName"] = $ResourceGroupName }
    return Get-AzVirtualNetwork @params
}
Export-ModuleMember -Function Get-VirtualNetwork


# Get the virtual network that a given subnet belongs to
# ------------------------------------------------------
function Get-VirtualNetworkFromSubnet {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Subnet that we want the virtual network for")]
        [Microsoft.Azure.Commands.Network.Models.PSSubnet]$Subnet
    )
    $originalContext = Get-AzContext
    $null = Set-AzContext -SubscriptionId $Subnet.Id.Split("/")[2] -ErrorAction Stop
    $virtualNetwork = Get-AzVirtualNetwork | Where-Object { (($_.Subnets | Where-Object { $_.Id -eq $Subnet.Id }).Count -gt 0) }
    $null = Set-AzContext -Context $originalContext -ErrorAction Stop
    return $virtualNetwork
}
Export-ModuleMember -Function Get-VirtualNetworkFromSubnet


# Remove a virtual machine NIC
# ----------------------------
function Remove-NetworkInterface {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of VM NIC to remove")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to remove from")]
        [string]$ResourceGroupName
    )
    $null = Get-AzNetworkInterface -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level InfoSuccess "VM network card '$Name' does not exist"
    } else {
        Add-LogMessage -Level Info "[ ] Removing VM network card '$Name'"
        $null = Remove-AzNetworkInterface -Name $Name -ResourceGroupName $ResourceGroupName -Force
        if ($?) {
            Add-LogMessage -Level Success "Removed VM network card '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to remove VM network card '$Name'"
        }
    }
}
Export-ModuleMember -Function Remove-NetworkInterface


# Set Network Security Group Rules
# --------------------------------
function Set-NetworkSecurityGroupRules {
    param(
        [parameter(Mandatory = $true, HelpMessage = "Network Security Group to set rules for")]
        [Microsoft.Azure.Commands.Network.Models.PSNetworkSecurityGroup]$NetworkSecurityGroup,
        [parameter(Mandatory = $true, HelpMessage = "Rules to set for Network Security Group")]
        [Object[]]$Rules
    )
    Add-LogMessage -Level Info "[ ] Setting $($Rules.Count) rules for Network Security Group '$($NetworkSecurityGroup.Name)'"
    try {
        $existingRules = @(Get-AzNetworkSecurityRuleConfig -NetworkSecurityGroup $NetworkSecurityGroup)
        foreach ($existingRule in $existingRules) {
            $NetworkSecurityGroup = Remove-AzNetworkSecurityRuleConfig -Name $existingRule.Name -NetworkSecurityGroup $NetworkSecurityGroup
        }
    } catch {
        Add-LogMessage -Level Fatal "Error removing existing rules from Network Security Group '$($NetworkSecurityGroup.Name)'." -Exception $_.Exception
    }
    try {
        foreach ($rule in $Rules) {
            $null = Add-NetworkSecurityGroupRule -NetworkSecurityGroup $NetworkSecurityGroup @rule
        }
    } catch {
        Add-LogMessage -Level Fatal "Error adding provided rules to Network Security Group '$($NetworkSecurityGroup.Name)'." -Exception $_.Exception
    }
    try {
        $NetworkSecurityGroup = Get-AzNetworkSecurityGroup -Name $NetworkSecurityGroup.Name -ResourceGroupName $NetworkSecurityGroup.ResourceGroupName -ErrorAction Stop
        $updatedRules = @(Get-AzNetworkSecurityRuleConfig -NetworkSecurityGroup $NetworkSecurityGroup)
        foreach ($updatedRule in $updatedRules) {
            $sourceAddressText = ($updatedRule.SourceAddressPrefix -eq "*") ? "any source" : $updatedRule.SourceAddressPrefix
            $destinationAddressText = ($updatedRule.DestinationAddressPrefix -eq "*") ? "any destination" : $updatedRule.DestinationAddressPrefix
            $destinationPortText = ($updatedRule.DestinationPortRange -eq "*") ? "any port" : "ports $($updatedRule.DestinationPortRange)"
            Add-LogMessage -Level Success "Set $($updatedRule.Name) rule to $($updatedRule.Access) connections from $sourceAddressText to $destinationPortText on $destinationAddressText."
        }
    } catch {
        Add-LogMessage -Level Fatal "Failed to add one or more NSG rules!" -Exception $_.Exception
    }
    return $NetworkSecurityGroup
}
Export-ModuleMember -Function Set-NetworkSecurityGroupRules


# Attach a network security group to a subnet
# -------------------------------------------
function Set-SubnetNetworkSecurityGroup {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Subnet whose NSG will be set")]
        [Microsoft.Azure.Commands.Network.Models.PSSubnet]$Subnet,
        [Parameter(Mandatory = $true, HelpMessage = "Network security group to attach")]
        $NetworkSecurityGroup,
        [Parameter(Mandatory = $false, HelpMessage = "Virtual network that the subnet belongs to")]
        $VirtualNetwork
    )
    if (-not $VirtualNetwork) {
        $VirtualNetwork = Get-VirtualNetworkFromSubnet -Subnet $Subnet
    }
    Add-LogMessage -Level Info "Ensuring that NSG '$($NetworkSecurityGroup.Name)' is attached to subnet '$($Subnet.Name)'..."
    $null = Set-AzVirtualNetworkSubnetConfig -Name $Subnet.Name -VirtualNetwork $VirtualNetwork -AddressPrefix $Subnet.AddressPrefix -NetworkSecurityGroup $NetworkSecurityGroup
    $success = $?
    $VirtualNetwork = Set-AzVirtualNetwork -VirtualNetwork $VirtualNetwork
    $success = $success -and $?
    $updatedSubnet = Get-Subnet -Name $Subnet.Name -VirtualNetworkName $VirtualNetwork.Name -ResourceGroupName $VirtualNetwork.ResourceGroupName
    $success = $success -and $?
    if ($success) {
        Add-LogMessage -Level Success "Set network security group on '$($Subnet.Name)'"
    } else {
        Add-LogMessage -Level Fatal "Failed to set network security group on '$($Subnet.Name)'!"
    }
    return $updatedSubnet
}
Export-ModuleMember -Function Set-SubnetNetworkSecurityGroup


# Peer two vnets
# --------------
function Set-VnetPeering {
    param(
        [Parameter(Mandatory = $false, HelpMessage = "Enable use of remote gateway from the first VNet")]
        [switch]$VNet1AllowRemoteGateway,
        [Parameter(Mandatory = $true, HelpMessage = "Name of the first of two VNets to peer")]
        [string]$Vnet1Name,
        [Parameter(Mandatory = $true, HelpMessage = "Resource group name of the first VNet")]
        [string]$Vnet1ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Subscription name of the first VNet")]
        [string]$Vnet1SubscriptionName,
        [Parameter(Mandatory = $false, HelpMessage = "Enable use of remote gateway from the second VNet")]
        [switch]$VNet2AllowRemoteGateway,
        [Parameter(Mandatory = $true, HelpMessage = "Name of the second of two VNets to peer")]
        [string]$Vnet2Name,
        [Parameter(Mandatory = $true, HelpMessage = "Resource group name of the second VNet")]
        [string]$Vnet2ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Subscription name of the second VNet")]
        [string]$Vnet2SubscriptionName
    )
    # Exit early if trying to enable remote gateways on both virtual networks
    if ($VNet1AllowRemoteGateway -and $VNet2AllowRemoteGateway) {
        Add-LogMessage -Level Fatal "Remote gateways cannot be used from both VNets in a peering!"
    }
    try {
        # Get original subscription
        $originalContext = Get-AzContext
        Add-LogMessage -Level Info "Peering virtual networks ${Vnet1Name} and ${Vnet2Name}."

        # Get virtual networks
        $null = Set-AzContext -SubscriptionId $Vnet1SubscriptionName -ErrorAction Stop
        $Vnet1 = Get-AzVirtualNetwork -Name $Vnet1Name -ResourceGroupName $Vnet1ResourceGroupName -ErrorAction Stop
        $null = Set-AzContext -SubscriptionId $Vnet2SubscriptionName -ErrorAction Stop
        $Vnet2 = Get-AzVirtualNetwork -Name $Vnet2Name -ResourceGroupName $Vnet2ResourceGroupName -ErrorAction Stop

        # Remove any existing peerings
        $null = Set-AzContext -SubscriptionId $Vnet1SubscriptionName -ErrorAction Stop
        $null = Get-AzVirtualNetworkPeering -VirtualNetworkName $Vnet1.Name -ResourceGroupName $Vnet1.ResourceGroupName | Where-Object { $_.RemoteVirtualNetwork.Id -eq $Vnet2.Id } | Remove-AzVirtualNetworkPeering -Force -ErrorAction Stop
        $null = Set-AzContext -SubscriptionId $Vnet2SubscriptionName -ErrorAction Stop
        $null = Get-AzVirtualNetworkPeering -VirtualNetworkName $Vnet2.Name -ResourceGroupName $Vnet2.ResourceGroupName | Where-Object { $_.RemoteVirtualNetwork.Id -eq $Vnet1.Id } | Remove-AzVirtualNetworkPeering -Force -ErrorAction Stop

        # Set remote gateway parameters if requested
        $paramsVnet1 = @{}
        $paramsVnet2 = @{}
        if ($AllowVNet1Gateway.IsPresent) {
            $paramsVnet1["AllowGatewayTransit"] = $true
            $paramsVnet2["UseRemoteGateways"] = $true
        }
        if ($AllowVNet2Gateway.IsPresent) {
            $paramsVnet1["UseRemoteGateways"] = $true
            $paramsVnet2["AllowGatewayTransit"] = $true
        }

        # Create peering in the direction VNet1 -> VNet2
        $null = Set-AzContext -SubscriptionId $Vnet1SubscriptionName -ErrorAction Stop
        $PeeringName = "PEER_${Vnet2Name}"
        Add-LogMessage -Level Info "[ ] Adding peering '$PeeringName' to virtual network ${Vnet1Name}."
        $null = Add-AzVirtualNetworkPeering -Name "$PeeringName" -VirtualNetwork $vnet1 -RemoteVirtualNetworkId $Vnet2.Id @paramsVnet1 -ErrorAction Stop
        if ($?) {
            Add-LogMessage -Level Success "Adding peering '$PeeringName' succeeded"
        } else {
            Add-LogMessage -Level Fatal "Adding peering '$PeeringName' failed!"
        }
        # Create peering in the direction VNet2 -> VNet1
        $null = Set-AzContext -SubscriptionId $Vnet2SubscriptionName -ErrorAction Stop
        $PeeringName = "PEER_${Vnet1Name}"
        Add-LogMessage -Level Info "[ ] Adding peering '$PeeringName' to virtual network ${Vnet2Name}."
        $null = Add-AzVirtualNetworkPeering -Name "$PeeringName" -VirtualNetwork $Vnet2 -RemoteVirtualNetworkId $Vnet1.Id @paramsVnet2 -ErrorAction Stop
        if ($?) {
            Add-LogMessage -Level Success "Adding peering '$PeeringName' succeeded"
        } else {
            Add-LogMessage -Level Fatal "Adding peering '$PeeringName' failed!"
        }
    } finally {
        # Switch back to original subscription
        $null = Set-AzContext -Context $originalContext -ErrorAction Stop
    }
}
Export-ModuleMember -Function Set-VnetPeering


# Ensure Firewall is running, with option to force a restart
# ----------------------------------------------------------
function Start-Firewall {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of Firewall")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of Firewall resource group")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of virtual network containing the 'AzureFirewall' subnet")]
        [string]$VirtualNetworkName,
        [Parameter(Mandatory = $false, HelpMessage = "Force restart of Firewall")]
        [switch]$ForceRestart
    )
    Add-LogMessage -Level Info "Ensuring that firewall '$Name' is running..."
    $firewall = Get-AzFirewall -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if (-not $firewall) {
        Add-LogMessage -Level Error "Firewall '$Name' does not exist in $ResourceGroupName"
    } else {
        $virtualNetwork = Get-AzVirtualNetwork -Name $VirtualNetworkName
        $publicIP = Get-AzPublicIpAddress -Name "${Name}-PIP" -ResourceGroupName $ResourceGroupName
        if ($ForceRestart) {
            Add-LogMessage -Level Info "Restart requested. Deallocating firewall '$Name'..."
            $firewall = Stop-Firewall -Name $Name -ResourceGroupName $ResourceGroupName
        }
        # At this point we either have a running firewall or a stopped firewall.
        # A firewall is allocated if it has one or more IP configurations.
        if ($firewall.IpConfigurations) {
            Add-LogMessage -Level InfoSuccess "Firewall '$Name' is already running."
        } else {
            try {
                Add-LogMessage -Level Info "[ ] Starting firewall '$Name'..."
                $firewall.Allocate($virtualNetwork, $publicIp)
                $firewall = Set-AzFirewall -AzureFirewall $firewall -ErrorAction Stop
                Add-LogMessage -Level Success "Firewall '$Name' successfully started."
            } catch {
                Add-LogMessage -Level Fatal "Failed to (re)start firewall '$Name'" -Exception $_.Exception
            }
        }
    }
    return $firewall
}
Export-ModuleMember -Function Start-Firewall


# Ensure Firewall is deallocated
# ------------------------------
function Stop-Firewall {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of Firewall")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of Firewall resource group")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $false, HelpMessage = "Submit request to stop but don't wait for completion.")]
        [switch]$NoWait
    )
    Add-LogMessage -Level Info "Ensuring that firewall '$Name' is deallocated..."
    $firewall = Get-AzFirewall -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if (-not $firewall) {
        Add-LogMessage -Level Fatal "Firewall '$Name' does not exist."
        Exit 1
    }
    # At this point we either have a running firewall or a stopped firewall.
    # A firewall is allocated if it has one or more IP configurations.
    $firewallAllocacted = ($firewall.IpConfigurations.Length -ge 1)
    if (-not $firewallAllocacted) {
        Add-LogMessage -Level InfoSuccess "Firewall '$Name' is already deallocated."
    } else {
        Add-LogMessage -Level Info "[ ] Deallocating firewall '$Name'..."
        $firewall.Deallocate()
        $firewall = Set-AzFirewall -AzureFirewall $firewall -AsJob:$NoWait -ErrorAction Stop
        if ($NoWait) {
            Add-LogMessage -Level Success "Request to deallocate firewall '$Name' accepted."
        } else {
            Add-LogMessage -Level Success "Firewall '$Name' successfully deallocated."
        }
        $firewall = Get-AzFirewall -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    }
    return $firewall
}
Export-ModuleMember -Function Stop-Firewall


# Update NSG rule to match a given configuration
# ----------------------------------------------
function Update-NetworkSecurityGroupRule {
    param(
        [Parameter(Mandatory = $false, HelpMessage = "Rule access type")]
        [ValidateSet("Allow", "Deny")]
        [string]$Access = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Rule destination address prefix")]
        [string[]]$DestinationAddressPrefix = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Rule destination port range")]
        [string[]]$DestinationPortRange = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Rule direction")]
        [ValidateSet("Inbound", "Outbound")]
        [string]$Direction = $null,
        [Parameter(Mandatory = $true, HelpMessage = "Name of NSG rule to update")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "NSG that this rule belongs to")]
        [Microsoft.Azure.Commands.Network.Models.PSNetworkSecurityGroup]$NetworkSecurityGroup,
        [Parameter(Mandatory = $false, HelpMessage = "Rule Priority")]
        [int]$Priority = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Rule protocol")]
        [string]$Protocol = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Rule source address prefix")]
        [string[]]$SourceAddressPrefix = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Rule source port range")]
        [string[]]$SourcePortRange = $null
    )
    # Load any unspecified parameters from the existing rule
    try {
        $ruleBefore = Get-AzNetworkSecurityRuleConfig -Name $Name -NetworkSecurityGroup $NetworkSecurityGroup
        $Description = $ruleBefore.Description
        if (-not $Access) { $Access = $ruleBefore.Access }
        if (-not $DestinationAddressPrefix) { $DestinationAddressPrefix = $ruleBefore.DestinationAddressPrefix }
        if (-not $DestinationPortRange) { $DestinationPortRange = $ruleBefore.DestinationPortRange }
        if (-not $Direction) { $Direction = $ruleBefore.Direction }
        if (-not $Priority) { $Priority = $ruleBefore.Priority }
        if (-not $Protocol) { $Protocol = $ruleBefore.Protocol }
        if (-not $SourceAddressPrefix) { $SourceAddressPrefix = $ruleBefore.SourceAddressPrefix }
        if (-not $SourcePortRange) { $SourcePortRange = $ruleBefore.SourcePortRange }
        # Print the update we're about to make
        if ($Direction -eq "Inbound") {
            Add-LogMessage -Level Info "[ ] Updating '$Name' rule on '$($NetworkSecurityGroup.Name)' to '$Access' access from '$SourceAddressPrefix'"
        } else {
            Add-LogMessage -Level Info "[ ] Updating '$Name' rule on '$($NetworkSecurityGroup.Name)' to '$Access' access to '$DestinationAddressPrefix'"
        }
        # Update rule and NSG (both are required)
        $null = Set-AzNetworkSecurityRuleConfig -Access $Access `
                                                -Description $Description `
                                                -DestinationAddressPrefix $DestinationAddressPrefix `
                                                -DestinationPortRange $DestinationPortRange `
                                                -Direction $Direction `
                                                -Name $Name `
                                                -NetworkSecurityGroup $NetworkSecurityGroup `
                                                -Priority $Priority `
                                                -Protocol $Protocol `
                                                -SourceAddressPrefix $SourceAddressPrefix `
                                                -SourcePortRange $SourcePortRange `
                                                -ErrorAction Stop | Set-AzNetworkSecurityGroup -ErrorAction Stop
        # Apply the rule and validate whether it succeeded
        $ruleAfter = Get-AzNetworkSecurityRuleConfig -Name $Name -NetworkSecurityGroup $NetworkSecurityGroup
        if (($ruleAfter.Access -eq $Access) -and
            ($ruleAfter.Description -eq $Description) -and
            ("$($ruleAfter.DestinationAddressPrefix)" -eq "$DestinationAddressPrefix") -and
            ("$($ruleAfter.DestinationPortRange)" -eq "$DestinationPortRange") -and
            ($ruleAfter.Direction -eq $Direction) -and
            ($ruleAfter.Name -eq $Name) -and
            ($ruleAfter.Priority -eq $Priority) -and
            ($ruleAfter.Protocol -eq $Protocol) -and
            ("$($ruleAfter.SourceAddressPrefix)" -eq "$SourceAddressPrefix") -and
            ("$($ruleAfter.SourcePortRange)" -eq "$SourcePortRange")) {
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
        Add-LogMessage -Level Fatal "Could not find rule '$Name' on NSG '$($NetworkSecurityGroup.Name)'" -Exception $_.Exception
    }
}
Export-ModuleMember -Function Update-NetworkSecurityGroupRule


# Update subnet and IP address for a VM
# -------------------------------------
function Update-VMIpAddress {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Azure VM object", ParameterSetName = "ByObject")]
        [Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine]$VM,
        [Parameter(Mandatory = $true, HelpMessage = "VM name", ParameterSetName = "ByName")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "VM resource group", ParameterSetName = "ByName")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Subnet to join")]
        [Microsoft.Azure.Commands.Network.Models.PSChildResource]$Subnet,
        [Parameter(Mandatory = $true, HelpMessage = "IP address to switch to")]
        [string]$IpAddress
    )
    # Get VM if not provided
    if (-not $VM) {
        $VM = Get-AzVM -Name $Name -ResourceGroup $ResourceGroupName
    }
    $networkCard = Get-AzNetworkInterface | Where-Object { $_.VirtualMachine.Id -eq $VM.Id }
    if ($networkCard.Count -ne 1) { Add-LogMessage -Level Fatal "Found $($networkCard.Count) network cards for $VMName!" }
    if ($networkCard.IpConfigurations[0].PrivateIpAddress -eq $IpAddress) {
        Add-LogMessage -Level InfoSuccess "IP address for '$($VM.Name)' is already set to '$IpAddress'"
    } else {
        Add-LogMessage -Level Info "Updating subnet and IP address for '$($VM.Name)'..."
        Stop-VM -VM $VM
        $networkCard.IpConfigurations[0].Subnet.Id = $Subnet.Id
        $networkCard.IpConfigurations[0].PrivateIpAddress = $IpAddress
        $null = $networkCard | Set-AzNetworkInterface
        # Validate changes
        $networkCard = Get-AzNetworkInterface | Where-Object { $_.VirtualMachine.Id -eq $VM.Id }
        if ($networkCard.IpConfigurations[0].Subnet.Id -eq $Subnet.Id) {
            Add-LogMessage -Level Info "Set '$($VM.Name)' subnet to '$($Subnet.Name)'"
        } else {
            Add-LogMessage -Level Fatal "Failed to change subnet to '$($Subnet.Name)'!"
        }
        if ($networkCard.IpConfigurations[0].PrivateIpAddress -eq $IpAddress) {
            Add-LogMessage -Level Info "Set '$($VM.Name)' IP address to '$IpAddress'"
        } else {
            Add-LogMessage -Level Fatal "Failed to change IP address to '$IpAddress'!"
        }
        Start-VM -VM $VM
    }
}
Export-ModuleMember -Function Update-VMIpAddress
