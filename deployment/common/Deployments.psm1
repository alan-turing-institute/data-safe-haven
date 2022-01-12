Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Compute -ErrorAction Stop
Import-Module Az.Dns -ErrorAction Stop
Import-Module Az.KeyVault -ErrorAction Stop
Import-Module Az.Network -ErrorAction Stop
Import-Module Az.OperationalInsights -ErrorAction Stop
Import-Module Az.Resources -ErrorAction Stop
Import-Module Az.Storage -ErrorAction Stop
Import-Module $PSScriptRoot/DataStructures -ErrorAction Stop
Import-Module $PSScriptRoot/Logging -ErrorAction Stop


# Create network security group rule if it does not exist
# -------------------------------------------------------
function Add-NetworkSecurityGroupRule {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of network security group rule to deploy")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "A NetworkSecurityGroup object to apply this rule to")]
        $NetworkSecurityGroup,
        [Parameter(Mandatory = $true, HelpMessage = "A description of the network security rule")]
        [string]$Description,
        [Parameter(Mandatory = $true, HelpMessage = "Specifies the priority of a rule configuration")]
        $Priority,
        [Parameter(Mandatory = $true, HelpMessage = "Specifies whether a rule is evaluated on incoming or outgoing traffic")]
        $Direction,
        [Parameter(Mandatory = $true, HelpMessage = "Specifies whether network traffic is allowed or denied")]
        [string]$Access,
        [Parameter(Mandatory = $true, HelpMessage = "Specifies the network protocol that a rule configuration applies to")]
        [string]$Protocol,
        [Parameter(Mandatory = $true, HelpMessage = "Source addresses. One or more of: a CIDR, an IP address range, a wildcard or an Azure tag (eg. VirtualNetwork)")]
        $SourceAddressPrefix,
        [Parameter(Mandatory = $true, HelpMessage = "Source port or range. One or more of: an integer, a range of integers or a wildcard")]
        $SourcePortRange,
        [Parameter(Mandatory = $true, HelpMessage = "Destination addresses. One or more of: a CIDR, an IP address range, a wildcard or an Azure tag (eg. VirtualNetwork)")]
        $DestinationAddressPrefix,
        [Parameter(Mandatory = $true, HelpMessage = "Destination port or range. One or more of: an integer, a range of integers or a wildcard")]
        $DestinationPortRange,
        [Parameter(Mandatory = $false, HelpMessage = "Print verbose logging messages")]
        [switch]$VerboseLogging = $false
    )
    try {
        if ($VerboseLogging) { Add-LogMessage -Level Info "Ensuring that NSG rule '$Name' exists on '$($NetworkSecurityGroup.Name)'..." }
        $null = Get-AzNetworkSecurityRuleConfig -Name $Name -NetworkSecurityGroup $NetworkSecurityGroup -ErrorVariable notExists -ErrorAction SilentlyContinue
        if ($notExists) {
            if ($VerboseLogging) { Add-LogMessage -Level Info "[ ] Creating NSG rule '$Name'" }
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
                                                    -SourcePortRange $SourcePortRange | Set-AzNetworkSecurityGroup -ErrorAction Stop
            if ($?) {
                if ($VerboseLogging) { Add-LogMessage -Level Success "Created NSG rule '$Name'" }
            } else {
                if ($VerboseLogging) { Add-LogMessage -Level Fatal "Failed to create NSG rule '$Name'!" }
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
                                                    -SourcePortRange $SourcePortRange | Set-AzNetworkSecurityGroup -ErrorAction Stop
        }
    } catch [Microsoft.Azure.Commands.Network.Common.NetworkCloudException] {
        Add-LogMessage -Level Fatal $_.Exception.Message.Split("`n")[0]
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


# Confirm VM is deallocated
# -------------------------
function Confirm-VmDeallocated {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of VM")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group that the VM belongs to")]
        [string]$ResourceGroupName
    )
    $vmStatuses = (Get-AzVM -Name $Name -ResourceGroupName $ResourceGroupName -Status).Statuses.Code
    return (($vmStatuses -contains "PowerState/deallocated") -and ($vmStatuses -contains "ProvisioningState/succeeded") )
}
Export-ModuleMember -Function Confirm-VmDeallocated


# Confirm VM is running
# ---------------------
function Confirm-VmRunning {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of VM")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group that the VM belongs to")]
        [string]$ResourceGroupName
    )
    $vmStatuses = (Get-AzVM -Name $Name -ResourceGroupName $ResourceGroupName -Status).Statuses.Code
    return (($vmStatuses -contains "PowerState/running") -and ($vmStatuses -contains "ProvisioningState/succeeded") )
}
Export-ModuleMember -Function Confirm-VmRunning


# Confirm VM is stopped
# ---------------------
function Confirm-VmStopped {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of VM")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group that the VM belongs to")]
        [string]$ResourceGroupName
    )
    if ($vmStatuses -contains "ProvisioningState/failed/VMStoppedToWarnSubscription") {
        Add-LogMessage -Level Warning "VM '$Name' has status: VMStoppedToWarnSubscription meaning that it was automatically stopped when the subscription ran out of credit."
    }
    $vmStatuses = (Get-AzVM -Name $Name -ResourceGroupName $ResourceGroupName -Status).Statuses.Code
    return (($vmStatuses -contains "PowerState/stopped") -and (($vmStatuses -contains "ProvisioningState/succeeded") -or ($vmStatuses -contains "ProvisioningState/failed/VMStoppedToWarnSubscription")))
}
Export-ModuleMember -Function Confirm-VmStopped


# Deploy an ARM template and log the output
# -----------------------------------------
function Deploy-ArmTemplate {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Path to template file")]
        $TemplatePath,
        [Parameter(Mandatory = $true, HelpMessage = "Template parameters")]
        $Params,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        $ResourceGroupName
    )
    $templateName = Split-Path -Path "$TemplatePath" -LeafBase
    New-AzResourceGroupDeployment -Name $templateName -ResourceGroupName $ResourceGroupName -TemplateFile $TemplatePath @Params -Verbose -DeploymentDebugLogLevel ResponseContent -ErrorVariable templateErrors
    $result = $?
    Add-DeploymentLogMessages -ResourceGroupName $ResourceGroupName -DeploymentName $templateName -ErrorDetails $templateErrors
    if ($result) {
        Add-LogMessage -Level Success "Template deployment '$templateName' succeeded"
    } else {
        Add-LogMessage -Level Fatal "Template deployment '$templateName' failed!"
    }
}
Export-ModuleMember -Function Deploy-ArmTemplate


# Add A (and optionally CNAME) DNS records
# ----------------------------------------
function Deploy-DNSRecords {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of DNS subscription")]
        $SubscriptionName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of DNS resource group")]
        $ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of DNS zone to add the records to")]
        $ZoneName,
        [Parameter(Mandatory = $true, HelpMessage = "Public IP address for this record to point to")]
        $PublicIpAddress,
        [Parameter(Mandatory = $false, HelpMessage = "Name of 'A' record")]
        $RecordNameA = "@",
        [Parameter(Mandatory = $false, HelpMessage = "Name of 'CNAME' record (if none is provided then no CNAME redirect will be set up)")]
        $RecordNameCName,
        [Parameter(Mandatory = $false, HelpMessage = "TTL seconds for the DNS records")]
        $TtlSeconds = 30
    )
    $originalContext = Get-AzContext
    try {
        Add-LogMessage -Level Info "Adding DNS records..."
        $null = Set-AzContext -Subscription $SubscriptionName -ErrorAction Stop

        # Set the A record
        Add-LogMessage -Level Info "[ ] Setting 'A' record to '$PublicIpAddress' for DNS zone ($ZoneName)"
        Remove-AzDnsRecordSet -Name $RecordNameA -RecordType A -ZoneName $ZoneName -ResourceGroupName $ResourceGroupName
        $null = New-AzDnsRecordSet -Name $RecordNameA -RecordType A -ZoneName $ZoneName -ResourceGroupName $ResourceGroupName -Ttl $TtlSeconds -DnsRecords (New-AzDnsRecordConfig -Ipv4Address $PublicIpAddress)
        if ($?) {
            Add-LogMessage -Level Success "Successfully set 'A' record"
        } else {
            Add-LogMessage -Level Fatal "Failed to set 'A' record!"
        }
        # Set the CNAME record
        if ($RecordNameCName) {
            Add-LogMessage -Level Info "[ ] Setting CNAME record '$RecordNameCName' to point to the 'A' record for DNS zone ($ZoneName)"
            Remove-AzDnsRecordSet -Name $RecordNameCName -RecordType CNAME -ZoneName $ZoneName -ResourceGroupName $ResourceGroupName
            $null = New-AzDnsRecordSet -Name $RecordNameCName -RecordType CNAME -ZoneName $ZoneName -ResourceGroupName $ResourceGroupName -Ttl $TtlSeconds -DnsRecords (New-AzDnsRecordConfig -Cname $ZoneName)
            if ($?) {
                Add-LogMessage -Level Success "Successfully set 'CNAME' record"
            } else {
                Add-LogMessage -Level Fatal "Failed to set 'CNAME' record!"
            }
        }
    } catch {
        $null = Set-AzContext -Context $originalContext -ErrorAction Stop
        throw
    } finally {
        $null = Set-AzContext -Context $originalContext -ErrorAction Stop
    }
    return
}
Export-ModuleMember -Function Deploy-DNSRecords


# Create a firewall if it does not exist
# --------------------------------------
function Deploy-Firewall {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of public IP address to deploy")]
        $Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        $ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of virtual network containing the 'AzureFirewall' subnet")]
        $VirtualNetworkName,
        [Parameter(Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
        $Location,
        [Parameter(Mandatory = $false, HelpMessage = "Force deallocation and reallocation of Firewall")]
        [switch]$ForceReallocation
    )
    # Ensure Firewall public IP address exists
    $publicIp = Deploy-PublicIpAddress -Name "${Name}-PIP" -ResourceGroupName $ResourceGroupName -Location $Location -AllocationMethod Static -Sku "Standard"  # NB. Azure Firewall requires a 'Standard' public IP
    Add-LogMessage -Level Info "Ensuring that firewall '$Name' exists..."
    $firewall = Get-AzFirewall -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating firewall '$Name'"
        $firewall = New-AzFirewall -Name $Name -ResourceGroupName $ResourceGroupName -Location $Location -VirtualNetworkName $VirtualNetworkName -PublicIpName $publicIp.Name #"${Name}-PIP"
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
        $Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of application rule collection to add this to")]
        $CollectionName,
        [Parameter(Mandatory = $true, HelpMessage = "Firewall to add this collection to")]
        $Firewall,
        [Parameter(Mandatory = $true, HelpMessage = "Address of source")]
        $SourceAddress,
        [Parameter(Mandatory = $true, ParameterSetName = "ByFqdn", HelpMessage = "Protocol to use")]
        $Protocol,
        [Parameter(Mandatory = $false, HelpMessage = "Priority of this application rule collection")]
        $Priority,
        [Parameter(Mandatory = $false, HelpMessage = "Whether these rules will allow or deny access to the specified resources")]
        [ValidateSet("Allow", "Deny")]
        $ActionType,
        [Parameter(Mandatory = $true, ParameterSetName = "ByFqdn", HelpMessage = "List of FQDNs to apply rule to. Supports '*' wildcard at start of each FQDN.")]
        $TargetFqdn,
        [Parameter(Mandatory = $true, ParameterSetName = "ByTag", HelpMessage = "List of FQDN tags to apply rule to. An FQN tag represents a set of Azure-curated FQDNs.")]
        $TargetTag,
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
        $Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of network rule collection to add this to")]
        $CollectionName,
        [Parameter(Mandatory = $true, HelpMessage = "Firewall to add this collection to")]
        $Firewall,
        [Parameter(Mandatory = $true, HelpMessage = "Address(es) of source")]
        $SourceAddress,
        [Parameter(Mandatory = $true, HelpMessage = "Address(es) of destination")]
        $DestinationAddress,
        [Parameter(Mandatory = $true, HelpMessage = "Port(s) of destination")]
        $DestinationPort,
        [Parameter(Mandatory = $true, HelpMessage = "Protocol to use")]
        $Protocol,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        $Priority,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        [ValidateSet("Allow", "Deny")]
        $ActionType,
        [Parameter(HelpMessage = "Make change to the local firewall object only. Useful when making lots of updates in a row. You will need to make a separate call to 'Set-AzFirewall' to apply the changes to the actual Azure firewall.")]
        [switch]$LocalChangeOnly
    )
    $rule = New-AzFirewallNetworkRule -Name $Name -SourceAddress $SourceAddress -DestinationAddress $DestinationAddress -DestinationPort $DestinationPort -Protocol $Protocol
    Add-LogMessage -Level Info "[ ] Ensuring that traffic from '$SourceAddress' to '$DestinationAddress' on port '$DestinationPort' over $Protocol is set on $($Firewall.Name)..."
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


# Create a key vault if it does not exist
# ---------------------------------------
function Deploy-KeyVault {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of disk to deploy")]
        $Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        $ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
        $Location
    )
    Add-LogMessage -Level Info "Ensuring that key vault '$Name' exists..."
    $keyVault = Get-AzKeyVault -VaultName $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($null -eq $keyVault) {
        # Purge any existing soft-deleted key vault
        foreach ($existingLocation in (Get-AzLocation | ForEach-Object { $_.Location })) {
            try {
                if (Get-AzKeyVault -VaultName $Name -Location $existingLocation -InRemovedState -ErrorAction Stop) {
                    Add-LogMessage -Level Info "Purging a soft-deleted key vault '$Name' in $existingLocation"
                    Remove-AzKeyVault -VaultName $Name -Location $existingLocation -InRemovedState -Force | Out-Null
                    if ($?) {
                        Add-LogMessage -Level Success "Purged key vault '$Name'"
                    } else {
                        Add-LogMessage -Level Fatal "Failed to purge key vault '$Name'!"
                    }
                }
            } catch [Microsoft.Rest.Azure.CloudException] {
                continue  # Running Get-AzKeyVault on a location which does not support soft-deleted key vaults causes an error which we catch here
            }
        }
        # Create a new key vault
        Add-LogMessage -Level Info "[ ] Creating key vault '$Name'"
        $keyVault = New-AzKeyVault -Name $Name -ResourceGroupName $ResourceGroupName -Location $Location
        if ($?) {
            Add-LogMessage -Level Success "Created key vault '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create key vault '$Name'!"
        }
    } else {
        Add-LogMessage -Level InfoSuccess "Key vault '$Name' already exists"
    }
    return $keyVault
}
Export-ModuleMember -Function Deploy-KeyVault


# Create log analytics workspace if it does not exist
# ---------------------------------------------------
function Deploy-LogAnalyticsWorkspace {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of log analytics workspace to deploy")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Location to deploy into")]
        [string]$Location
    )
    $null = Deploy-ResourceGroup -Name $ResourceGroupName -Location $Location
    Add-LogMessage -Level Info "Ensuring that log analytics workspace '$Name' exists..."
    $workspace = Get-AzOperationalInsightsWorkspace -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating log analytics workspace '$Name'"
        $workspace = New-AzOperationalInsightsWorkspace -Name $Name -ResourceGroupName $ResourceGroupName -Location $Location -Sku Standard
        if ($?) {
            Add-LogMessage -Level Success "Created log analytics workspace '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create log analytics workspace '$Name'!"
        }
    } else {
        Add-LogMessage -Level InfoSuccess "Log analytics workspace '$Name' already exists"
    }
    if (-not $(Get-AzResourceProvider | Where-Object { $_.ProviderNamespace -eq "Microsoft.Insights" })) {
        Add-LogMessage -Level Info "[ ] Registering Microsoft.Insights provider in this subscription..."
        $null = Register-AzResourceProvider -ProviderNamespace Microsoft.Insights
        Wait-For -Target "Microsoft.Insights provider to register" -Seconds 300
        if ($(Get-AzResourceProvider | Where-Object { $_.ProviderNamespace -eq "Microsoft.Insights" })) {
            Add-LogMessage -Level Success "Successfully registered Microsoft.Insights provider"
        } else {
            Add-LogMessage -Level Fatal "Failed to register Microsoft.Insights provider!"
        }
    }
    return $workspace
}
Export-ModuleMember -Function Deploy-LogAnalyticsWorkspace


# Create a managed disk if it does not exist
# ------------------------------------------
function Deploy-ManagedDisk {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of disk to deploy")]
        $Name,
        [Parameter(Mandatory = $true, HelpMessage = "Disk size in GB")]
        $SizeGB,
        [Parameter(Mandatory = $true, HelpMessage = "Disk type (eg. Standard_LRS)")]
        $Type,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        $ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
        $Location
    )
    Add-LogMessage -Level Info "Ensuring that managed disk '$Name' exists..."
    $disk = Get-AzDisk -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating $SizeGB GB managed disk '$Name'"
        $diskConfig = New-AzDiskConfig -Location $Location -DiskSizeGB $SizeGB -AccountType $Type -OsType Linux -CreateOption Empty
        $disk = New-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $Name -Disk $diskConfig
        if ($?) {
            Add-LogMessage -Level Success "Created managed disk '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create managed disk '$Name'!"
        }
    } else {
        Add-LogMessage -Level InfoSuccess "Managed disk '$Name' already exists"
    }
    return $disk
}
Export-ModuleMember -Function Deploy-ManagedDisk


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
        $Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        $ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Allocation method (static or dynamic)")]
        [ValidateSet("Dynamic", "Static")]
        $AllocationMethod,
        [Parameter(Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
        $Location,
        [Parameter(Mandatory = $false, HelpMessage = "SKU ('Basic' or 'Standard')")]
        [ValidateSet("Basic", "Standard")]
        $Sku = "Basic"
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


# Create resource group if it does not exist
# ------------------------------------------
function Deploy-ResourceGroup {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy")]
        $Name,
        [Parameter(Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
        $Location
    )
    Add-LogMessage -Level Info "Ensuring that resource group '$Name' exists..."
    $resourceGroup = Get-AzResourceGroup -Name $Name -Location $Location -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating resource group '$Name'"
        $resourceGroup = New-AzResourceGroup -Name $Name -Location $Location -Force
        if ($?) {
            Add-LogMessage -Level Success "Created resource group '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create resource group '$Name'!"
        }
    } else {
        Add-LogMessage -Level InfoSuccess "Resource group '$Name' already exists"
    }
    return $resourceGroup
}
Export-ModuleMember -Function Deploy-ResourceGroup


# Create a route if it does not exist
# -----------------------------------
function Deploy-Route {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of route to deploy")]
        $Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of route table that this route should be deployed into")]
        $RouteTableName,
        [Parameter(Mandatory = $true, HelpMessage = "CIDR that this route applies to")]
        $AppliesTo,
        [Parameter(Mandatory = $true, HelpMessage = "The firewall IP address or one of 'Internet', 'None', 'VirtualNetworkGateway', 'VnetLocal'")]
        $NextHop
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
        $Name,
        [Parameter(Mandatory = $true, HelpMessage = "A VirtualNetwork object to deploy into")]
        $VirtualNetwork,
        [Parameter(Mandatory = $true, HelpMessage = "Specifies a range of IP addresses for a virtual network")]
        $AddressPrefix
    )
    Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"
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


# Create Linux virtual machine if it does not exist
# -------------------------------------------------
function Deploy-UbuntuVirtualMachine {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Administrator password")]
        [System.Security.SecureString]$AdminPassword,
        [Parameter(Mandatory = $true, HelpMessage = "Administrator username")]
        [string]$AdminUsername,
        [Parameter(Mandatory = $true, HelpMessage = "Name of storage account for boot diagnostics")]
        [Microsoft.Azure.Commands.Management.Storage.Models.PSStorageAccount]$BootDiagnosticsAccount,
        [Parameter(Mandatory = $true, HelpMessage = "Cloud-init YAML file")]
        [string]$CloudInitYaml,
        [Parameter(Mandatory = $true, ParameterSetName = "ByNicId_ByImageId", HelpMessage = "ID of VM image to deploy")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIpAddress_ByImageId", HelpMessage = "ID of VM image to deploy")]
        [string]$ImageId,
        [Parameter(Mandatory = $true, ParameterSetName = "ByNicId_ByImageSku", HelpMessage = "SKU of VM image to deploy")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIpAddress_ByImageSku", HelpMessage = "SKU of VM image to deploy")]
        [string]$ImageSku,
        [Parameter(Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
        [string]$Location,
        [Parameter(Mandatory = $true, HelpMessage = "Name of virtual machine to deploy")]
        [string]$Name,
        [Parameter(Mandatory = $true, ParameterSetName = "ByNicId_ByImageId", HelpMessage = "ID of network card to attach to this VM")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNicId_ByImageSku", HelpMessage = "ID of network card to attach to this VM")]
        [string]$NicId,
        [Parameter(Mandatory = $true, HelpMessage = "OS disk type (eg. Standard_LRS)")]
        [string]$OsDiskType,
        [Parameter(Mandatory = $true, ParameterSetName = "ByIpAddress_ByImageId", HelpMessage = "Private IP address to assign to this VM")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIpAddress_ByImageSku", HelpMessage = "Private IP address to assign to this VM")]
        [string]$PrivateIpAddress,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Size of virtual machine to deploy")]
        [string]$Size,
        [Parameter(Mandatory = $true, ParameterSetName = "ByIpAddress_ByImageId", HelpMessage = "Subnet to deploy this VM into")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIpAddress_ByImageSku", HelpMessage = "Subnet to deploy this VM into")]
        [Microsoft.Azure.Commands.Network.Models.PSSubnet]$Subnet,
        [Parameter(Mandatory = $false, HelpMessage = "Administrator public SSH key")]
        [string]$AdminPublicSshKey = $null,
        [Parameter(Mandatory = $false, HelpMessage = "IDs of data disks")]
        [string[]]$DataDiskIds = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Do not wait for deployment to finish")]
        [switch]$NoWait = $false,
        [Parameter(Mandatory = $false, HelpMessage = "Size of OS disk (GB)")]
        [int]$OsDiskSizeGb = $null
    )
    Add-LogMessage -Level Info "Ensuring that virtual machine '$Name' exists..."
    $null = Get-AzVM -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        $adminCredentials = New-Object System.Management.Automation.PSCredential("$AdminUsername", $AdminPassword)
        # Build VM configuration
        $vmConfig = New-AzVMConfig -VMName $Name -VMSize $Size
        # Set source image to a custom image or to latest Ubuntu (default)
        if ($ImageId) {
            $vmConfig = Set-AzVMSourceImage -VM $vmConfig -Id $ImageId
        } elseif ($ImageSku) {
            if ($ImageSku -eq "20.04-LTS") {
                $vmConfig = Set-AzVMSourceImage -VM $vmConfig -PublisherName Canonical -Offer 0001-com-ubuntu-server-focal -Skus "20_04-LTS" -Version "latest"
            } else {
                $vmConfig = Set-AzVMSourceImage -VM $vmConfig -PublisherName Canonical -Offer UbuntuServer -Skus $ImageSku -Version "latest"
            }
        } else {
            Add-LogMessage -Level Fatal "Could not determine which source image to use!"
        }
        $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Linux -ComputerName $Name -Credential $adminCredentials -CustomData $CloudInitYaml
        if (-not $NicId) {
            $NicId = (Deploy-VirtualMachineNIC -Name "${Name}-NIC" -ResourceGroupName $ResourceGroupName -Subnet $Subnet -PrivateIpAddress $PrivateIpAddress -Location $Location).Id
        }
        $vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $NicId -Primary
        if ($OsDiskSizeGb) {
            $vmConfig = Set-AzVMOSDisk -VM $vmConfig -StorageAccountType $OsDiskType -Name "$Name-OS-DISK" -CreateOption FromImage -DiskSizeInGB $OsDiskSizeGb
        } else {
            $vmConfig = Set-AzVMOSDisk -VM $vmConfig -StorageAccountType $OsDiskType -Name "$Name-OS-DISK" -CreateOption FromImage
        }
        $vmConfig = Set-AzVMBootDiagnostic -VM $vmConfig -Enable -ResourceGroupName $BootDiagnosticsAccount.ResourceGroupName -StorageAccountName $BootDiagnosticsAccount.StorageAccountName
        # Add optional data disks
        $lun = 0
        foreach ($diskId in $DataDiskIds) {
            $lun += 1 # NB. this line means that our first disk gets deployed at lun1 and we do not use lun0. Consider changing this.
            $vmConfig = Add-AzVMDataDisk -VM $vmConfig -ManagedDiskId $diskId -CreateOption Attach -Lun $lun
        }
        # Copy public key to VM
        if ($AdminPublicSshKey) {
            $vmConfig = Add-AzVMSshPublicKey -VM $vmConfig -KeyData $AdminPublicSshKey -Path "/home/$($AdminUsername)/.ssh/authorized_keys"
        }
        # Create VM
        Add-LogMessage -Level Info "[ ] Creating virtual machine '$Name'"
        try {
            $null = New-AzVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $vmConfig -ErrorAction Stop
            Add-LogMessage -Level Success "Created virtual machine '$Name'"
        } catch {
            Add-LogMessage -Level Fatal "Failed to create virtual machine '$Name'! Check that your desired image is available in this region." -Exception $_.Exception
        }
        if (-not $NoWait) {
            Start-Sleep 30  # wait for VM deployment to register
            Wait-ForAzVMCloudInit -Name $Name -ResourceGroupName $ResourceGroupName
        }
    } else {
        Add-LogMessage -Level InfoSuccess "Virtual machine '$Name' already exists"
    }
    return (Get-AzVM -Name $Name -ResourceGroupName $ResourceGroupName)
}
Export-ModuleMember -Function Deploy-UbuntuVirtualMachine


# Create a virtual machine NIC
# ----------------------------
function Deploy-VirtualMachineNIC {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of VM NIC to deploy")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Subnet to attach this NIC to")]
        $Subnet,
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
Export-ModuleMember -Function Deploy-VirtualMachineNIC


# Deploy Azure Monitoring Extension on a VM
# -----------------------------------------
function Deploy-VirtualMachineMonitoringExtension {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "VM object")]
        $VM,
        [Parameter(Mandatory = $true, HelpMessage = "Log Analytics Workspace ID")]
        [string]$WorkspaceId,
        [Parameter(Mandatory = $true, HelpMessage = "Log Analytics Workspace key")]
        [string]$WorkspaceKey
    )

    $PublicSettings = @{ "workspaceId" = $WorkspaceId }
    $ProtectedSettings = @{ "workspaceKey" = $WorkspaceKey }

    function Set-ExtensionIfNotInstalled {
        param(
            [Parameter(Mandatory = $true, HelpMessage = "VM object")]
            $VM,
            [Parameter(Mandatory = $true, HelpMessage = "Extension publisher")]
            [string]$Publisher,
            [Parameter(Mandatory = $true, HelpMessage = "Extension type")]
            [string]$Type,
            [Parameter(Mandatory = $true, HelpMessage = "Extension version")]
            [string]$Version
        )
        Add-LogMessage -Level Info "[ ] Ensuring extension '$type' is installed on VM '$($VM.Name)'."
        $installed = Get-AzVMExtension -ResourceGroupName $VM.ResourceGroupName -VMName $VM.Name | Where-Object { $_.Publisher -eq $publisher -and $_.ExtensionType -eq $type }
        if ($installed) {
            Add-LogMessage -Level InfoSuccess "Extension '$type' is already installed on VM '$($VM.Name)'."
        } else {
            try {
                Set-AzVMExtension -ExtensionName $type `
                                  -ExtensionType $type `
                                  -Location $VM.location `
                                  -ProtectedSettings $ProtectedSettings `
                                  -Publisher $publisher `
                                  -ResourceGroupName $VM.ResourceGroupName `
                                  -Settings $PublicSettings `
                                  -TypeHandlerVersion $version `
                                  -VMName $VM.Name `
                                  -ErrorAction Stop
                Add-LogMessage -Level Success "Installed extension '$type' on VM '$($VM.Name)'."
            } catch {
                Add-LogMessage -Level Failure "Failed to install extension '$type' on VM '$($VM.Name)'!"
            }
        }
    }
    if ($VM.OSProfile.WindowsConfiguration) {
        # Install Monitoring Agent
        Set-ExtensionIfNotInstalled -VM $VM -Publisher "Microsoft.EnterpriseCloud.Monitoring" -Type "MicrosoftMonitoringAgent" -Version 1.0
        # Install Dependency Agent
        Set-ExtensionIfNotInstalled -VM $VM -Publisher "Microsoft.Azure.Monitoring.DependencyAgent" -Type "DependencyAgentWindows" -Version 9.10
    } elseif ($VM.OSProfile.LinuxConfiguration) {
        # Install Monitoring Agent
        Set-ExtensionIfNotInstalled -VM $VM -Publisher "Microsoft.EnterpriseCloud.Monitoring" -Type "OmsAgentForLinux" -Version 1.13
        # Install Dependency Agent
        Set-ExtensionIfNotInstalled -VM $VM -Publisher "Microsoft.Azure.Monitoring.DependencyAgent" -Type "DependencyAgentLinux" -Version 9.10
    } else {
        Add-LogMessage -Level Failure "VM OSProfile not recognised. Cannot activate logging for VM '$($vm.Name)'!"
    }
}
Export-ModuleMember -Function Deploy-VirtualMachineMonitoringExtension


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


# Ensure that an Azure VM is turned on
# ------------------------------------
function Enable-AzVM {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of VM to enable")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group that the VM belongs to")]
        [string]$ResourceGroupName
    )
    Add-LogMessage -Level Info "Enable-AzVM is deprecated - consider switching to Start-VM"
    $powerState = (Get-AzVM -Name $Name -ResourceGroupName $ResourceGroupName -Status).Statuses.Code[1]
    if ($powerState -eq "PowerState/running") {
        return Start-VM -Name $Name -ResourceGroupName $ResourceGroupName -ForceRestart
    } else {
        return Start-VM -Name $Name -ResourceGroupName $ResourceGroupName
    }
}
Export-ModuleMember -Function Enable-AzVM


# Get subnet
# ----------
function Get-AzSubnet {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of subnet to retrieve")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Virtual network that this subnet belongs to")]
        $VirtualNetwork
    )
    Add-LogMessage -Level Info "Get-AzSubnet is deprecated - consider switching to Get-Subnet"
    return Get-Subnet -Name $Name -VirtualNetworkName $VirtualNetwork.Name -ResourceGroupName $VirtualNetwork.ResourceGroupName
}
Export-ModuleMember -Function Get-AzSubnet


# Get image ID
# ------------
function Get-ImageFromGallery {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Image version to retrieve")]
        [string]$ImageVersion,
        [Parameter(Mandatory = $true, HelpMessage = "Image definition that image belongs to")]
        [string]$ImageDefinition,
        [Parameter(Mandatory = $true, HelpMessage = "Image gallery name")]
        [string]$GalleryName,
        [Parameter(Mandatory = $true, HelpMessage = "Resource group containing image gallery")]
        [string]$ResourceGroup,
        [Parameter(Mandatory = $true, HelpMessage = "Subscription containing image gallery")]
        [string]$Subscription
    )
    $originalContext = Get-AzContext
    try {
        $null = Set-AzContext -Subscription $Subscription -ErrorAction Stop
        Add-LogMessage -Level Info "Looking for image $imageDefinition version $imageVersion..."
        try {
            $image = Get-AzGalleryImageVersion -ResourceGroup $ResourceGroup -GalleryName $GalleryName -GalleryImageDefinitionName $ImageDefinition -GalleryImageVersionName $ImageVersion -ErrorAction Stop
        } catch [Microsoft.Azure.Commands.Compute.Common.ComputeCloudException] {
            $versions = Get-AzGalleryImageVersion -ResourceGroup $ResourceGroup -GalleryName $GalleryName -GalleryImageDefinitionName $ImageDefinition | Sort-Object Name | ForEach-Object { $_.Name }
            Add-LogMessage -Level Error "Image version '$ImageVersion' is invalid. Available versions are: $versions"
            $ImageVersion = $versions | Select-Object -Last 1
            $userVersion = Read-Host -Prompt "Enter the version you would like to use (or leave empty to accept the default: '$ImageVersion')"
            if ($versions.Contains($userVersion)) {
                $ImageVersion = $userVersion
            }
            $image = Get-AzGalleryImageVersion -ResourceGroup $ResourceGroup -GalleryName $GalleryName -GalleryImageDefinitionName $ImageDefinition -GalleryImageVersionName $ImageVersion -ErrorAction Stop
        }
        if ($image) {
            $commitHash = $image.Tags["Build commit hash"]
            if ($commitHash) {
                Add-LogMessage -Level Success "Found image $imageDefinition version $($image.Name) in gallery created from commit $commitHash"
            } else {
                Add-LogMessage -Level Success "Found image $imageDefinition version $($image.Name) in gallery"
            }
        } else {
            Add-LogMessage -Level Fatal "Could not find image $imageDefinition version $ImageVersion in gallery!"
        }
    } catch {
        $null = Set-AzContext -Context $originalContext -ErrorAction Stop
        throw
    } finally {
        $null = Set-AzContext -Context $originalContext -ErrorAction Stop
    }
    return $image
}
Export-ModuleMember -Function Get-ImageFromGallery


# Get image definition from the type specified in the config file
# ---------------------------------------------------------------
function Get-ImageDefinition {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Type of image to retrieve the definition for")]
        [string]$Type
    )
    Add-LogMessage -Level Info "[ ] Getting image type from gallery..."
    if ($Type -eq "Ubuntu") {
        $imageDefinition = "ComputeVM-Ubuntu"
    } elseif ($Type -eq "Ubuntu18") {
        $imageDefinition = "ComputeVM-Ubuntu1804Base"
    } else {
        Add-LogMessage -Level Fatal "Failed to interpret $Type as an image type!"
    }
    Add-LogMessage -Level Success "Interpreted $Type as image type $imageDefinition"
    return $imageDefinition
}
Export-ModuleMember -Function Get-ImageDefinition


# Get NS Records
# --------------
function Get-NSRecords {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of record set")]
        [string]$RecordSetName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of DNS zone")]
        [string]$DnsZoneName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        [string]$ResourceGroupName
    )
    Add-LogMessage -Level Info "Reading NS records '$($RecordSetName)' for DNS Zone '$($DnsZoneName)'..."
    $recordSet = Get-AzDnsRecordSet -ZoneName $DnsZoneName -ResourceGroupName $ResourceGroupName -Name $RecordSetName -RecordType "NS"
    return $recordSet.Records
}
Export-ModuleMember -Function Get-NSRecords


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
function Get-VirtualNetworkFromSubnet {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Subnet that we want the virtual network for")]
        $Subnet
    )
    $originalContext = Get-AzContext
    $null = Set-AzContext -SubscriptionId $Subnet.Id.Split("/")[2] -ErrorAction Stop
    $virtualNetwork = Get-AzVirtualNetwork | Where-Object { (($_.Subnets | Where-Object { $_.Id -eq $Subnet.Id }).Count -gt 0) }
    $null = Set-AzContext -Context $originalContext -ErrorAction Stop
    return $virtualNetwork
}
Export-ModuleMember -Function Get-VirtualNetworkFromSubnet


# Get all VMs for an SHM or SRE
# -----------------------------
function Get-VMsByResourceGroupPrefix {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Prefix to match resource groups on")]
        [string]$ResourceGroupPrefix
    )
    $matchingResourceGroups = Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -like "${ResourceGroupPrefix}_*" }
    $matchingVMs = [ordered]@{}
    foreach ($rg in $matchingResourceGroups) {
        $rgVms = Get-AzVM -ResourceGroup $rg.ResourceGroupName
        if ($rgVms) {
            $matchingVMs[$rg.ResourceGroupName] = $rgVms
        }
    }
    return $matchingVMs
}
Export-ModuleMember -Function Get-VMsByResourceGroupPrefix


# Run remote shell script
# -----------------------
function Invoke-RemoteScript {
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "ByPath", HelpMessage = "Path to local script that will be run remotely")]
        [string]$ScriptPath,
        [Parameter(Mandatory = $true, ParameterSetName = "ByString", HelpMessage = "Contents of script that will be run remotely")]
        [string]$Script,
        [Parameter(Mandatory = $true, HelpMessage = "Name of VM to run on")]
        [string]$VMName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group VM belongs to")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $false, HelpMessage = "Type of script to run")]
        [ValidateSet("PowerShell", "UnixShell")]
        [string]$Shell = "PowerShell",
        [Parameter(Mandatory = $false, HelpMessage = "Suppress script output on success")]
        [switch]$SuppressOutput,
        [Parameter(Mandatory = $false, HelpMessage = "(Optional) hashtable of script parameters")]
        [System.Collections.IDictionary]$Parameter = $null
    )
    # If we're given a script then create a file from it
    $tmpScriptFile = $null
    if ($Script) {
        $tmpScriptFile = New-TemporaryFile
        $Script | Out-File -FilePath $tmpScriptFile.FullName
        $ScriptPath = $tmpScriptFile.FullName
    }
    # Validate any external parameters as non-string arguments or arguments containing special characters will cause Invoke-AzVMRunCommand to fail
    $params = @{}
    if ($Parameter) { $params["Parameter"] = $Parameter }
    $params["CommandId"] = ($Shell -eq "PowerShell") ? "RunPowerShellScript" : "RunShellScript"
    if ($params.Contains("Parameter")) {
        foreach ($kv in $params["Parameter"].GetEnumerator()) {
            if ($kv.Value -isnot [string]) {
                Add-LogMessage -Level Fatal "$($kv.Key) argument ($($kv.Value)) must be a string!"
            }
            foreach ($unsafeCharacter in @("|", "&")) {
                if ($kv.Value.Contains($unsafeCharacter)) {
                    Add-LogMessage -Level Fatal "$($kv.Key) argument ($($kv.Value)) contains '$unsafeCharacter' which will cause Invoke-AzVMRunCommand to fail. Consider encoding this variable in Base-64."
                }
            }
            foreach ($whitespaceCharacter in @(" ", "`t")) {
                if (($Shell -eq "UnixShell") -and ($kv.Value.Contains($whitespaceCharacter))) {
                    if (-not (($kv.Value[0] -eq "'") -or ($kv.Value[0] -eq '"'))) {
                        Write-Information -InformationAction "Continue" $kv.Value[0]
                        Add-LogMessage -Level Fatal "$($kv.Key) argument ($($kv.Value)) contains '$whitespaceCharacter' which will cause the shell script to fail. Consider wrapping this variable in single quotes."
                    }
                }
            }
        }
    }
    try {
        # Catch failures from running two commands in close proximity and rerun
        while ($true) {
            try {
                $result = Invoke-AzVMRunCommand -Name $VMName -ResourceGroupName $ResourceGroupName -ScriptPath $ScriptPath @params -ErrorAction Stop
                $success = $?
                break
            } catch [Microsoft.Azure.Commands.Compute.Common.ComputeCloudException] {
               if (-not ($_.Exception.Message -match "Run command extension execution is in progress")) { throw }
            }
        }
    } catch {
        Add-LogMessage -Level Fatal "Running '$ScriptPath' on remote VM '$VMName' failed." -Exception $_.Exception
    }
    $success = $success -and ($result.Status -eq "Succeeded")
    foreach ($outputStream in $result.Value) {
        # Check for 'ComponentStatus/<stream name>/succeeded' as a signal of success
        $success = $success -and (($outputStream.Code -split "/")[-1] -eq "succeeded")
        # Check for ' [x] ' in the output stream as a signal of failure
        if ($outputStream.Message -ne "") {
            $success = $success -and ([string]($outputStream.Message) -NotLike '* `[x`] *')
        }
    }
    # Clean up any temporary scripts
    if ($tmpScriptFile) { Remove-Item $tmpScriptFile.FullName }
    # Check for success or failure
    if ($success) {
        Add-LogMessage -Level Success "Remote script execution succeeded"
        if (-not $SuppressOutput) { Write-Information -InformationAction "Continue" ($result.Value | Out-String) }
    } else {
        Add-LogMessage -Level Info "Script output:"
        Write-Information -InformationAction "Continue" ($result | Out-String)
        Add-LogMessage -Level Fatal "Remote script execution has failed. Please check the output above before re-running this script."
    }
    return $result
}
Export-ModuleMember -Function Invoke-RemoteScript


# Update and reboot a machine
# ---------------------------
function Invoke-WindowsConfigureAndUpdate {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of VM to run on")]
        [string]$VMName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Time zone to use")]
        [string]$TimeZone,
        [Parameter(Mandatory = $true, HelpMessage = "NTP server to use")]
        [string]$NtpServer,
        [Parameter(Mandatory = $false, HelpMessage = "Additional Powershell modules")]
        [string[]]$AdditionalPowershellModules = @()
    )
    # Install core Powershell modules
    Add-LogMessage -Level Info "[ ] Installing core Powershell modules on '$VMName'"
    $corePowershellScriptPath = Join-Path $PSScriptRoot "remote" "Install_Core_Powershell_Modules.ps1"
    $null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $corePowershellScriptPath -VMName $VMName -ResourceGroupName $ResourceGroupName
    # Install additional Powershell modules
    if ($AdditionalPowershellModules) {
        Add-LogMessage -Level Info "[ ] Installing additional Powershell modules on '$VMName'"
        $additionalPowershellScriptPath = Join-Path $PSScriptRoot "remote" "Install_Additional_Powershell_Modules.ps1"
        $null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $additionalPowershellScriptPath -VMName $VMName -ResourceGroupName $ResourceGroupName -Parameter @{"ModuleNamesB64" = ($AdditionalPowershellModules | ConvertTo-Json -Depth 10 | ConvertTo-Base64) }
    }
    # Set locale and run update script
    Add-LogMessage -Level Info "[ ] Setting time/locale and installing updates on '$VMName'"
    $InstallationScriptPath = Join-Path $PSScriptRoot "remote" "Configure_Windows.ps1"
    $null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $InstallationScriptPath -VMName $VMName -ResourceGroupName $ResourceGroupName -Parameter @{"TimeZone" = "$TimeZone"; "NTPServer" = "$NtpServer"; "Locale" = "en-GB" }
    # Reboot the VM
    Start-VM -Name $VMName -ResourceGroupName $ResourceGroupName -ForceRestart
}
Export-ModuleMember -Function Invoke-WindowsConfigureAndUpdate


# Create DNS Zone if it does not exist
# ------------------------------------
function New-DNSZone {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of DNS zone to deploy")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        [string]$ResourceGroupName
    )
    Add-LogMessage -Level Info "Ensuring that DNS zone '$($Name)' exists..."
    $null = Get-AzDnsZone -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating DNS Zone '$Name'"
        $null = New-AzDnsZone -Name $Name -ResourceGroupName $ResourceGroupName
        if ($?) {
            Add-LogMessage -Level Success "Created DNS Zone '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create DNS Zone '$Name'!"
        }
    } else {
        Add-LogMessage -Level InfoSuccess "DNS Zone '$Name' already exists"
    }
}
Export-ModuleMember -Function New-DNSZone


# Remove Virtual Machine
# ----------------------
function Remove-VirtualMachine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of the VM to remove")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group containing the VM")]
        [string]$ResourceGroupName,
        [Parameter(HelpMessage = "Forces the command to run without asking for user confirmation.")]
        [switch]$Force
    )
    $vm = Get-AzVM -Name $Name -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    if ($vm) {
        # Get boot diagnostics details
        $storageAccountName = [regex]::match($vm.DiagnosticsProfile.bootDiagnostics.storageUri, '^http[s]?://(.+?)\.').Groups[1].Value
        $bootDiagnosticsContainerName = "bootdiagnostics-*-$($vm.VmId)"
        # Remove VM
        Add-LogMessage -Level Info "[ ] Removing VM '$($vm.Name)'"
        $params = @{}
        if ($Force) { $params["Force"] = $Force }
        if ($ErrorAction) { $params["ErrorAction"] = $ErrorAction }
        $null = $vm | Remove-AzVM @params
        $success = $?
        # Remove boot diagnostics container
        Add-LogMessage -Level Info "[ ] Removing boot diagnostics account for '$($vm.Name)'"
        $storageAccount = Get-AzStorageAccount | Where-Object { $_.StorageAccountName -eq $storageAccountName }
        $null = $storageAccount | Get-AzStorageContainer | Where-Object { $_.Name -like $bootDiagnosticsContainerName } | Remove-AzStorageContainer -Force
        $success = $success -and $?
        if ($success) {
            Add-LogMessage -Level Success "Removed VM '$Name'"
        } else {
            Add-LogMessage -Level Failure "Failed to remove VM '$Name'"
        }
    } else {
        Add-LogMessage -Level InfoSuccess "VM '$Name' does not exist"
    }
}
Export-ModuleMember -Function Remove-VirtualMachine


# Remove Virtual Machine disk
# ---------------------------
function Remove-VirtualMachineDisk {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of the disk to remove")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group containing the disk")]
        [string]$ResourceGroupName
    )

    $null = Get-AzDisk -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level InfoSuccess "Disk '$Name' does not exist"
    } else {
        Add-LogMessage -Level Info "[ ] Removing disk '$Name'"
        $null = Remove-AzDisk -Name $Name -ResourceGroupName $ResourceGroupName -Force
        if ($?) {
            Add-LogMessage -Level Success "Removed disk '$Name'"
        } else {
            Add-LogMessage -Level Failure "Failed to remove disk '$Name'"
        }
    }
}
Export-ModuleMember -Function Remove-VirtualMachineDisk


# Remove a virtual machine NIC
# ----------------------------
function Remove-VirtualMachineNIC {
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
Export-ModuleMember -Function Remove-VirtualMachineNIC


# Add NS Record Set to DNS Zone if it does not already exist
# ---------------------------------------------------------
function Set-DnsZoneAndParentNSRecords {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of DNS zone to create")]
        [string]$DnsZoneName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group holding DNS zones")]
        [string]$ResourceGroupName
    )
    # Get subdomain and parent domain
    $subdomain = $DnsZoneName.Split('.')[0]
    $parentDnsZoneName = $DnsZoneName -replace "$subdomain.", ""

    # Create DNS Zone
    New-DNSZone -Name $DnsZoneName -ResourceGroupName $ResourceGroupName

    # Get NS records from the new DNS Zone
    Add-LogMessage -Level Info "Get NS records from the new DNS Zone..."
    $nsRecords = Get-NSRecords -RecordSetName "@" -DnsZoneName $DnsZoneName -ResourceGroupName $ResourceGroupName

    # Check if parent DNS Zone exists in same subscription and resource group
    $null = Get-AzDnsZone -Name $parentDnsZoneName -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "No existing DNS Zone was found for '$parentDnsZoneName' in resource group '$ResourceGroupName'."
        Add-LogMessage -Level Info "You need to add the following NS records to the parent DNS system for '$parentDnsZoneName': '$nsRecords'"
    } else {
        # Add NS records to the parent DNS Zone
        Add-LogMessage -Level Info "Add NS records to the parent DNS Zone..."
        Set-NSRecords -RecordSetName $subdomain -DnsZoneName $parentDnsZoneName -ResourceGroupName $ResourceGroupName -NsRecords $nsRecords
    }
}
Export-ModuleMember -Function Set-DnsZoneAndParentNSRecords


# Set key vault permissions to the group and remove the user who deployed it
# --------------------------------------------------------------------------
function Set-KeyVaultPermissions {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of key vault to set the permissions on")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of group to give permissions to")]
        [string]$GroupName
    )
    Add-LogMessage -Level Info "Giving group '$GroupName' access to key vault '$Name'..."
    try {
        $securityGroupId = (Get-AzADGroup -DisplayName $GroupName).Id | Select-Object -First 1
    } catch [Microsoft.Azure.Commands.ActiveDirectory.GetAzureADGroupCommand] {
        Add-LogMessage -Level Fatal "Could not identify an Azure security group called $GroupName!"
    }
    Set-AzKeyVaultAccessPolicy -VaultName $Name `
                               -ObjectId $securityGroupId `
                               -PermissionsToKeys Get, List, Update, Create, Import, Delete, Backup, Restore, Recover, Purge `
                               -PermissionsToSecrets Get, List, Set, Delete, Recover, Backup, Restore, Purge `
                               -PermissionsToCertificates Get, List, Delete, Create, Import, Update, Managecontacts, Getissuers, Listissuers, Setissuers, Deleteissuers, Manageissuers, Recover, Backup, Restore, Purge
    $success = $?
    foreach ($accessPolicy in (Get-AzKeyVault $Name).AccessPolicies | Where-Object { $_.ObjectId -ne $securityGroupId }) {
        Remove-AzKeyVaultAccessPolicy -VaultName $Name -ObjectId $accessPolicy.ObjectId
        $success = $success -and $?
    }
    if ($success) {
        Add-LogMessage -Level Success "Set correct access policies for key vault '$Name'"
    } else {
        Add-LogMessage -Level Fatal "Failed to set correct access policies for key vault '$Name'!"
    }
}
Export-ModuleMember -Function Set-KeyVaultPermissions


# Add NS Record Set to DNS Zone if it doesn't already exist
# ---------------------------------------------------------
function Set-NSRecords {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of record set")]
        [string]$RecordSetName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of DNS zone")]
        [string]$DnsZoneName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "NS records to add")]
        $NsRecords
    )
    $null = Get-AzDnsRecordSet -ResourceGroupName $ResourceGroupName -ZoneName $DnsZoneName -Name $RecordSetName -RecordType NS -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "Creating new Record Set '$($RecordSetName)' in DNS Zone '$($DnsZoneName)' with NS records '$($nsRecords)' to ..."
        $null = New-AzDnsRecordSet -Name $RecordSetName –ZoneName $DnsZoneName -ResourceGroupName $ResourceGroupName -Ttl 3600 -RecordType NS -DnsRecords $NsRecords
        if ($?) {
            Add-LogMessage -Level Success "Created DNS Record Set '$RecordSetName'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create DNS Record Set '$RecordSetName'!"
        }
    } else {
        # It's not straightforward to modify existing record sets idempotently so if the set already exists we do nothing
        Add-LogMessage -Level InfoSuccess "DNS record set '$RecordSetName' already exists. Will not update!"
    }
}
Export-ModuleMember -Function Set-NSRecords


# Attach a network security group to a subnet
# -------------------------------------------
function Set-SubnetNetworkSecurityGroup {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Subnet whose NSG will be set")]
        $Subnet,
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


# Ensure VM is started, with option to force a restart
# ----------------------------------------------------
function Start-VM {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Azure VM object", ParameterSetName = "ByObject")]
        [Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine]$VM,
        [Parameter(Mandatory = $true, HelpMessage = "Azure VM name", ParameterSetName = "ByName")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Azure VM resource group", ParameterSetName = "ByName")]
        [string]$ResourceGroupName,
        [Parameter(HelpMessage = "Skip this VM if it does not exist")]
        [switch]$SkipIfNotExist,
        [Parameter(HelpMessage = "Force restart of VM if already running")]
        [switch]$ForceRestart,
        [Parameter(HelpMessage = "Don't wait for VM (re)start operation to complete before returning")]
        [switch]$NoWait
    )
    # Get VM if not provided
    if (-not $VM) {
        try {
            $VM = Get-AzVM -Name $Name -ResourceGroup $ResourceGroupName -ErrorAction Stop
        } catch [Microsoft.Azure.Commands.Compute.Common.ComputeCloudException] {
            if ($SkipIfNotExist) { return }
            Add-LogMessage -Level Fatal "VM '$Name' could not be found in resource group '$ResourceGroupName'" -Exception $_.Exception
        }
    }
    # Ensure VM is started but don't restart if already running
    $operation = "start"
    if (Confirm-VmRunning -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName) {
        if ($ForceRestart) {
            $operation = "restart"
            Add-LogMessage -Level Info "[ ] Restarting VM '$($VM.Name)'"
            $result = Restart-AzVM -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName -NoWait:$NoWait
        } else {
            Add-LogMessage -Level InfoSuccess "VM '$($VM.Name)' already running."
            return
        }
    } elseif ((Confirm-VmDeallocated -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName) -or (Confirm-VmStopped -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName)) {
        Add-LogMessage -Level Info "[ ] Starting VM '$($VM.Name)'"
        $result = Start-AzVM -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName -NoWait:$NoWait
    } else {
        $vmStatus = (Get-AzVM -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName -Status).Statuses.Code
        Add-LogMessage -Level Warning "VM '$($VM.Name)' not in supported status: $vmStatus. No action taken."
        return
    }
    if ($result -is [Microsoft.Azure.Commands.Compute.Models.PSComputeLongRunningOperation]) {
        # Synchronous operation requested
        if ($result.Status -eq "Succeeded") {
            Add-LogMessage -Level Success "VM '$($VM.Name)' successfully ${operation}ed."
        } else {
            # If (re)start failed, log error with failure reason
            Add-LogMessage -Level Fatal "Failed to ${operation} VM '$($VM.Name)' [$($result.StatusCode): $($result.ReasonPhrase)]"
        }
    } elseif ($result -is [Microsoft.Azure.Commands.Compute.Models.PSAzureOperationResponse]) {
        # Asynchronous operation requested
        if (-not $result.IsSuccessStatusCode) {
            Add-LogMessage -Level Fatal "Request to ${operation} VM '$($VM.Name)' failed [$($result.StatusCode): $($result.ReasonPhrase)]"
        } else {
            Add-LogMessage -Level Success "Request to ${operation} VM '$($VM.Name)' accepted."
        }
    } else {
        Add-LogMessage -Level Fatal "Unrecognised return type from operation: '$($result.GetType().Name)'."
    }
}
Export-ModuleMember -Function Start-VM


# Ensure VM is stopped (de-allocated)
# -----------------------------------
function Stop-VM {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Azure VM object", ParameterSetName = "ByObject")]
        [Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine]$VM,
        [Parameter(Mandatory = $true, HelpMessage = "Azure VM name", ParameterSetName = "ByName")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Azure VM resource group", ParameterSetName = "ByName")]
        [string]$ResourceGroupName,
        [Parameter(HelpMessage = "Skip this VM if it does not exist")]
        [switch]$SkipIfNotExist,
        [Parameter(HelpMessage = "Don't wait for VM deallocation operation to complete before returning")]
        [switch]$NoWait
    )
    # Get VM if not provided
    if (-not $VM) {
        try {
            $VM = Get-AzVM -Name $Name -ResourceGroup $ResourceGroupName -ErrorAction Stop
        } catch [Microsoft.Azure.Commands.Compute.Common.ComputeCloudException] {
            if ($SkipIfNotExist) { return }
            Add-LogMessage -Level Fatal "VM '$Name' could not be found in resource group '$ResourceGroupName'" -Exception $_.Exception
        }
    }
    # Ensure VM is deallocated
    if (Confirm-VmDeallocated -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName) {
        Add-LogMessage -Level InfoSuccess "VM '$($VM.Name)' already stopped."
        return
    } else {
        Add-LogMessage -Level Info "[ ] Stopping VM '$($VM.Name)'"
        $result = Stop-AzVM -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName -Force -NoWait:$NoWait
    }
    if ($result -is [Microsoft.Azure.Commands.Compute.Models.PSComputeLongRunningOperation]) {
        # Synchronous operation requested
        if ($result.Status -eq "Succeeded") {
            Add-LogMessage -Level Success "VM '$($VM.Name)' stopped."
        } else {
            Add-LogMessage -Level Fatal "Failed to stop VM '$($VM.Name)' [$($result.Status): $($result.Error)]"
        }
    } elseif ($result -is [Microsoft.Azure.Commands.Compute.Models.PSAzureOperationResponse]) {
        # Asynchronous operation requested
        if (-not $result.IsSuccessStatusCode) {
            Add-LogMessage -Level Fatal "Request to stop VM '$($VM.Name)' failed [$($result.StatusCode): $($result.ReasonPhrase)]"
        } else {
            Add-LogMessage -Level Success "Request to stop VM '$($VM.Name)' accepted."
        }
    } else {
        Add-LogMessage -Level Fatal "Unrecognised return type from operation: '$($result.GetType().Name)'."
    }
}
Export-ModuleMember -Function Stop-VM


# Update NSG rule to match a given configuration
# ----------------------------------------------
function Update-NetworkSecurityGroupRule {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of NSG rule to update")]
        $Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of NSG that this rule belongs to")]
        $NetworkSecurityGroup,
        [Parameter(Mandatory = $false, HelpMessage = "Rule Priority")]
        $Priority = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Rule direction")]
        [ValidateSet("Inbound", "Outbound")]
        $Direction = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Rule access type")]
        $Access = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Rule protocol")]
        $Protocol = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Rule source address prefix")]
        $SourceAddressPrefix = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Rule source port range")]
        $SourcePortRange = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Rule destination address prefix")]
        $DestinationAddressPrefix = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Rule destination port range")]
        $DestinationPortRange = $null
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


# Peer two vnets
# --------------
function Set-VnetPeering {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of the first of two VNets to peer")]
        $Vnet1Name,
        [Parameter(Mandatory = $true, HelpMessage = "Resource group of the first VNet")]
        $Vnet1ResourceGroup,
        [Parameter(Mandatory = $true, HelpMessage = "Subscription name of the first VNet")]
        $Vnet1SubscriptionName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of the second of two VNets to peer")]
        $Vnet2Name,
        [Parameter(Mandatory = $true, HelpMessage = "Resource group of the second VNet")]
        $Vnet2ResourceGroup,
        [Parameter(Mandatory = $true, HelpMessage = "Subscription name of the second VNet")]
        $Vnet2SubscriptionName,
        [Parameter(Mandatory = $false, HelpMessage = "Enable use of remote gateway from one of the two VNets")]
        [ValidateSet(1, 2)]
        $AllowRemoteGatewayFromVNet
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


# Update LDAP secret in the local Active Directory
# ------------------------------------------------
function Update-AdLdapSecret {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of DC that holds the local Active Directory")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Resource group for DC that holds the local Active Directory")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Subscription name for DC that holds the local Active Directory")]
        [string]$SubscriptionName,
        [Parameter(Mandatory = $true, HelpMessage = "Password for LDAP search account")]
        [string]$LdapSearchPassword,
        [Parameter(Mandatory = $true, HelpMessage = "SAM account name for LDAP search account")]
        [string]$LdapSearchSamAccountName
    )
    # Get original subscription
    $originalContext = Get-AzContext
    try {
        $null = Set-AzContext -SubscriptionId $SubscriptionName -ErrorAction Stop
        Add-LogMessage -Level Info "[ ] Setting LDAP secret in local AD (${Name})"
        $params = @{
            ldapSearchSamAccountName = $LdapSearchSamAccountName
            ldapSearchPasswordB64    = $LdapSearchPassword | ConvertTo-Base64
        }
        $scriptPath = Join-Path $PSScriptRoot "remote" "ResetLdapPasswordOnAD.ps1"
        $null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $Name -ResourceGroupName $ResourceGroupName -Parameter $params
    } finally {
        # Switch back to original subscription
        $null = Set-AzContext -Context $originalContext -ErrorAction Stop
    }
}
Export-ModuleMember -Function Update-AdLdapSecret


# Update LDAP secret for a VM
# ---------------------------
function Update-VMLdapSecret {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "VM name")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "VM resource group")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Password for LDAP search account")]
        [string]$LdapSearchPassword
    )
    Add-LogMessage -Level Info "[ ] Setting LDAP secret on SRD '${Name}'"
    $params = @{
        ldapSearchPasswordB64 = $LdapSearchPassword | ConvertTo-Base64
    }
    $scriptPath = Join-Path $PSScriptRoot "remote" "ResetLdapPasswordOnVm.sh"
    $null = Invoke-RemoteScript -Shell "UnixShell" -ScriptPath $scriptPath -VMName $Name -ResourceGroupName $ResourceGroupName -Parameter $params
}
Export-ModuleMember -Function Update-VMLdapSecret


# Wait for cloud-init provisioning to finish
# ------------------------------------------
function Wait-ForAzVMCloudInit {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of virtual machine to wait for")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group VM belongs to")]
        [string]$ResourceGroupName
    )
    # Poll VM to see whether it has finished running
    Add-LogMessage -Level Info "Waiting for cloud-init provisioning to finish for $Name..."
    $progress = 0
    $statuses = @()
    while (-not ($statuses.Contains("ProvisioningState/succeeded") -and ($statuses.Contains("PowerState/stopped") -or $statuses.Contains("PowerState/deallocated")))) {
        try {
            $statuses = (Get-AzVM -Name $Name -ResourceGroupName $ResourceGroupName -Status -ErrorAction Stop).Statuses.Code
        } catch [Microsoft.Azure.Commands.Compute.Common.ComputeCloudException] {
            Add-LogMessage -Level Fatal "Could not retrieve VM status while waiting for cloud-init to finish!" -Exception $_.Exception
        } catch {
            Add-LogMessage -Level Fatal "Unknown error of type $($_.Exception.GetType()) occurred!" -Exception $_.Exception
        }
        $progress = [math]::min(100, $progress + 1)
        Write-Progress -Activity "Deployment status" -Status "$($statuses[0]) $($statuses[1])" -PercentComplete $progress
        Start-Sleep 10
    }
    Add-LogMessage -Level Success "Cloud-init provisioning is finished for $Name"
}
Export-ModuleMember -Function Wait-ForAzVMCloudInit
