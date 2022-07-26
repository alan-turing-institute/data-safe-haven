Import-Module Az.PrivateDns -ErrorAction Stop
Import-Module $PSScriptRoot/Logging -ErrorAction Stop


# Connect a private DNS zone to an automation account
# ---------------------------------------------------
function Connect-PrivateDnsToVirtualNetwork {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Private DNS zone to connect to")]
        [Microsoft.Azure.Commands.PrivateDns.Models.PSPrivateDnsZone]$DnsZone,
        [Parameter(Mandatory = $true, HelpMessage = "Automation account to connect")]
        [Microsoft.Azure.Commands.Network.Models.PSVirtualNetwork]$VirtualNetwork
    )
    Add-LogMessage -Level Info "Ensuring that private DNS zone '$($DnsZone.Name)' is connected to virtual network '$($VirtualNetwork.Name)'.."
    $link = Get-AzPrivateDnsVirtualNetworkLink -ZoneName $DnsZone.Name -ResourceGroupName $DnsZone.ResourceGroupName -ErrorAction SilentlyContinue
    if (-not $link) {
        Add-LogMessage -Level Info "[ ] Connecting private DNS zone '$($DnsZone.Name)' to virtual network '$($VirtualNetwork.Name)'"
        try {
            $linkName = "$($DnsZone.Name)-to-$($VirtualNetwork.Name)".Replace(".", "-").Replace("_", "-").ToLower()
            $link = New-AzPrivateDnsVirtualNetworkLink -ZoneName $DnsZone.Name -ResourceGroupName $DnsZone.ResourceGroupName -VirtualNetworkId $VirtualNetwork.Id -Name $linkName -ErrorAction Stop
            Add-LogMessage -Level Success "Connected private DNS zone '$($DnsZone.Name)' to virtual network '$($VirtualNetwork.Name)'"
        } catch {
            Add-LogMessage -Level Fatal "Failed to connect private DNS zone '$($DnsZone.Name)' to virtual network '$($VirtualNetwork.Name)'" -Exception $_.Exception
        }
    } else {
        Add-LogMessage -Level InfoSuccess "Private DNS zone '$($DnsZone.Name)' is already connected to '$($VirtualNetwork.Name)'"
    }
    return $link
}
Export-ModuleMember -Function Connect-PrivateDnsToVirtualNetwork


# Create an Azure Private DNS zone
# --------------------------------
function Deploy-PrivateDnsZone {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of private DNS zone to deploy")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        [string]$ResourceGroupName
    )
    Add-LogMessage -Level Info "Ensuring that private DNS zone '$Name' exists..."
    $zone = Get-AzPrivateDnsZone -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating private DNS zone '$Name'"
        $zone = New-AzPrivateDnsZone -Name $Name -ResourceGroupName $ResourceGroupName
        if ($?) {
            Add-LogMessage -Level Success "Created private DNS zone '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create private DNS zone '$Name'!"
        }
    } else {
        Add-LogMessage -Level InfoSuccess "Private DNS zone '$Name' already exists"
    }
    return $zone
}
Export-ModuleMember -Function Deploy-PrivateDnsZone


# Create an Azure Private DNS zone
# --------------------------------
function Deploy-PrivateDnsRecordSet {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of the record to add")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Private IP address to point to")]
        [string[]]$PrivateIpAddresses,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $false, HelpMessage = "Record type")]
        [string]$RecordType = "A",
        [Parameter(Mandatory = $false, HelpMessage = "TTL in seconds")]
        [UInt32]$Ttl = 60,
        [Parameter(Mandatory = $true, HelpMessage = "Name of private DNS zone to deploy")]
        [string]$ZoneName
    )
    Add-LogMessage -Level Info "Ensuring that private DNS record set '$Name' exists..."
    $record = Get-AzPrivateDnsRecordSet -Name $Name -ResourceGroupName $ResourceGroupName -RecordType $RecordType -ZoneName $ZoneName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating private DNS record set '$Name'"
        $privateDnsRecords = $PrivateIpAddresses | ForEach-Object { New-AzPrivateDnsRecordConfig -Ipv4Address $_ }
        $record = New-AzPrivateDnsRecordSet -Name $Name -ResourceGroupName $ResourceGroupName -RecordType $RecordType -Ttl $Ttl -ZoneName $ZoneName -PrivateDnsRecords $privateDnsRecords
        if ($?) {
            Add-LogMessage -Level Success "Created private DNS record set '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create private DNS record set '$Name'!"
        }
    } else {
        Add-LogMessage -Level InfoSuccess "Private DNS record set '$Name' already exists"
    }
    return $record
}
Export-ModuleMember -Function Deploy-PrivateDnsRecordSet
