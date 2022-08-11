Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Dns -ErrorAction Stop
Import-Module $PSScriptRoot/Logging -ErrorAction Stop

# Add A (and optionally CNAME) DNS records
# ----------------------------------------
function Deploy-DNSRecords {
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
        [int]$TtlSeconds = 30
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
        # Set the CAA record
        if ($RecordNameCAA) {
            Add-LogMessage -Level Info "[ ] Setting CAA record for $ZoneName to state that certificates will be provided by $RecordNameCAA"
            Remove-AzDnsRecordSet -Name "@" -RecordType CAA -ZoneName $ZoneName -ResourceGroupName $ResourceGroupName
            $null = New-AzDnsRecordSet -Name "@" -RecordType CAA -ZoneName $ZoneName -ResourceGroupName $ResourceGroupName -Ttl $TtlSeconds -DnsRecords (New-AzDnsRecordConfig -CaaFlags 0 -CaaTag "issue" -CaaValue $RecordNameCAA)
            if ($?) {
                Add-LogMessage -Level Success "Successfully set 'CAA' record for $ZoneName"
            } else {
                Add-LogMessage -Level Fatal "Failed to set 'CAA' record for $ZoneName!"
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
