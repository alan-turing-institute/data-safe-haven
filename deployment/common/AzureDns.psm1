Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Dns -ErrorAction Stop
Import-Module $PSScriptRoot/Logging -ErrorAction Stop


function Deploy-DnsRecord {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "DNS records")]
        [Microsoft.Azure.Commands.Dns.DnsRecordBase[]]$DnsRecords,
        [Parameter(Mandatory = $true, HelpMessage = "Name of record")]
        [string]$RecordName,
        [Parameter(Mandatory = $true, HelpMessage = "Type of record")]
        [string]$RecordType,
        [Parameter(Mandatory = $true, HelpMessage = "Name of DNS resource group")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of DNS subscription")]
        [string]$SubscriptionName,
        [Parameter(Mandatory = $true, HelpMessage = "TTL seconds for the DNS records")]
        [uint]$TtlSeconds,
        [Parameter(Mandatory = $true, HelpMessage = "Name of DNS zone to add the records to")]
        [string]$ZoneName
    )
    $originalContext = Get-AzContext
    try {
        $null = Set-AzContext -Subscription $SubscriptionName -ErrorAction Stop
        Remove-AzDnsRecordSet -Name $RecordName -RecordType $RecordType -ZoneName $ZoneName -ResourceGroupName $ResourceGroupName
        $null = New-AzDnsRecordSet -DnsRecords $DnsRecords -Name $RecordName -RecordType $RecordType -ResourceGroupName $ResourceGroupName -Ttl $TtlSeconds -ZoneName $ZoneName -ErrorAction Stop
    } catch {
        $null = Set-AzContext -Context $originalContext -ErrorAction Stop
        throw
    } finally {
        $null = Set-AzContext -Context $originalContext -ErrorAction Stop
    }
    return
}
Export-ModuleMember -Function Deploy-DnsRecord


# Add A (and optionally CNAME) DNS records
# ----------------------------------------
function Deploy-DnsRecordCollection {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of DNS subscription")]
        [string]$SubscriptionName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of DNS resource group")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of DNS zone to add the records to")]
        [string]$ZoneName,
        [Parameter(Mandatory = $true, HelpMessage = "Public IP address for this record to point to")]
        [string]$PublicIpAddress,
        [Parameter(Mandatory = $false, HelpMessage = "Name of 'A' record")]
        [string]$RecordNameA = "@",
        [Parameter(Mandatory = $false, HelpMessage = "Name of certificate provider for CAA record")]
        [string]$RecordNameCAA = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Name of 'CNAME' record (if none is provided then no CNAME redirect will be set up)")]
        [string]$RecordNameCName = $null,
        [Parameter(Mandatory = $false, HelpMessage = "TTL seconds for the DNS records")]
        [uint]$TtlSeconds = 30
    )
    Add-LogMessage -Level Info "Adding DNS records for DNS zone '$ZoneName'..."
    try {
        # Set the A record
        Add-LogMessage -Level Info "[ ] Setting 'A' record to '$PublicIpAddress' for DNS zone '$ZoneName'"
        Deploy-DnsRecord -DnsRecords (New-AzDnsRecordConfig -Ipv4Address $PublicIpAddress) -RecordName $RecordNameA -RecordType "A" -ResourceGroupName $ResourceGroupName -Subscription $SubscriptionName -TtlSeconds $TtlSeconds -ZoneName $ZoneName
        Add-LogMessage -Level Success "Set 'A' record to '$PublicIpAddress' for DNS zone '$ZoneName'"
        # Set the CNAME record
        if ($RecordNameCName) {
            Add-LogMessage -Level Info "[ ] Setting CNAME record '$RecordNameCName' to point to the 'A' record for DNS zone '$ZoneName'"
            Deploy-DnsRecord -DnsRecords (New-AzDnsRecordConfig -Cname $ZoneName) -RecordName $RecordNameCName -RecordType "CNAME" -ResourceGroupName $ResourceGroupName -Subscription $SubscriptionName -TtlSeconds $TtlSeconds -ZoneName $ZoneName
            Add-LogMessage -Level Success "Set 'CNAME' record to '$RecordNameCName' to point to the 'A' record for DNS zone '$ZoneName'"
        }
        # Set the CAA record
        if ($RecordNameCAA) {
            Add-LogMessage -Level Info "[ ] Setting CAA record for $ZoneName to state that certificates will be provided by $RecordNameCAA"
            Deploy-DnsRecord -DnsRecords (New-AzDnsRecordConfig -CaaFlags 0 -CaaTag "issue" -CaaValue $RecordNameCAA) -RecordName "@" -RecordType "CAA" -ResourceGroupName $ResourceGroupName -Subscription $SubscriptionName -TtlSeconds $TtlSeconds  -ZoneName $ZoneName
            Add-LogMessage -Level Success "Set 'CAA' record for '$ZoneName' to state that certificates will be provided by $RecordNameCAA"
        }
    } catch {
        Add-LogMessage -Level Fatal "Failed to add DNS records for DNS zone '$ZoneName'!" -Exception $_.Exception
    }
}
Export-ModuleMember -Function Deploy-DnsRecordCollection


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


# Remove a DNS record if it exists
# --------------------------------
function Remove-DnsRecord {
    param(
        [Parameter(Mandatory = $false, HelpMessage = "Name of 'A' record")]
        [string]$RecordName,
        [Parameter(Mandatory = $false, HelpMessage = "Name of 'A' record")]
        [string]$RecordType,
        [Parameter(Mandatory = $true, HelpMessage = "Name of DNS resource group")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of DNS subscription")]
        [string]$SubscriptionName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of DNS zone to add the records to")]
        [string]$ZoneName
    )
    $originalContext = Get-AzContext
    try {
        Add-LogMessage -Level Info "[ ] Removing '$RecordName' $RecordType record from DNS zone $ZoneName"
        $null = Set-AzContext -SubscriptionId $SubscriptionName -ErrorAction Stop
        Remove-AzDnsRecordSet -Name $RecordName -RecordType $RecordType -ZoneName $ZoneName -ResourceGroupName $ResourceGroupName -ErrorAction Stop
        Add-LogMessage -Level Fatal "DNS record removal succeeded"
    } catch {
        $null = Set-AzContext -Context $originalContext -ErrorAction Stop
        Add-LogMessage -Level Fatal "DNS record removal failed!" -Excepation $_.Exception
    } finally {
        $null = Set-AzContext -Context $originalContext -ErrorAction Stop
    }
}
Export-ModuleMember -Function Remove-ResourceGroup


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
        $null = New-AzDnsRecordSet -Name $RecordSetName -ZoneName $DnsZoneName -ResourceGroupName $ResourceGroupName -Ttl 3600 -RecordType NS -DnsRecords $NsRecords
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
