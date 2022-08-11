param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Azure Active Directory tenant ID")]
    [string]$tenantId
)

Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Dns -ErrorAction Stop
Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmConfig -shmId $shmId
$originalContext = Get-AzContext
$null = Set-AzContext -Subscription $config.dns.subscriptionName -ErrorAction Stop


# Connect to Microsoft Graph
# --------------------------
if (Get-MgContext) { Disconnect-MgGraph } # force a refresh of the Microsoft Graph token before starting
Add-LogMessage -Level Info "Authenticating against Azure Active Directory: use an AAD global administrator for tenant ($tenantId)..."
Connect-MgGraph -TenantId $tenantId -Scopes "Domain.ReadWrite.All" -ErrorAction Stop
if (Get-MgContext) {
    Add-LogMessage -Level Success "Authenticated with Microsoft Graph"
} else {
    Add-LogMessage -Level Fatal "Failed to authenticate with Microsoft Graph"
}


# Ensure that the SHM domain is registered with the Azure AD
# ----------------------------------------------------------
Add-LogMessage -Level Info "Adding SHM domain to AAD..."
$aadDomain = Get-MgDomain | Where-Object { $_.Id -eq $config.domain.fqdn }
if ($aadDomain) {
    Add-LogMessage -Level InfoSuccess "'$($config.domain.fqdn)' already present as custom domain on SHM AAD."
} else {
    $aadDomain = New-MgDomain -Id $config.domain.fqdn
    Add-LogMessage -Level Success "'$($config.domain.fqdn)' added as custom domain on SHM AAD."
}


# Verify the SHM domain record for the Azure AD
# ---------------------------------------------
Add-LogMessage -Level Info "Verifying domain on SHM AAD..."
if ($aadDomain.IsVerified) {
    Add-LogMessage -Level InfoSuccess "'$($config.domain.fqdn)' already verified on SHM AAD."
} else {
    # Fetch TXT version of AAD domain verification record set
    $validationRecord = Get-MgDomainVerificationDnsRecord -DomainId $config.domain.fqdn | Where-Object { $_.RecordType -eq "Txt" }
    # Make a DNS TXT Record object containing the validation code
    $validationCode = New-AzDnsRecordConfig -Value $validationRecord.AdditionalProperties.text

    # Check if this validation record already exists for the domain
    $recordSet = Get-AzDnsRecordSet -RecordType TXT -Name "@" -ZoneName $config.domain.fqdn -ResourceGroupName $config.dns.rg -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        # If no TXT record set exists at all, create a new TXT record set with the domain validation code
        $null = Deploy-DnsRecord -DnsRecords $validationCode -RecordName "@" -RecordType "TXT" -ResourceGroupName $config.dns.rg -Subscription $config.dns.subscriptionName -ZoneName $config.domain.fqdn
        Add-LogMessage -Level Success "Verification TXT record added to '$($config.domain.fqdn)' DNS zone."
    } else {
        # Check if the verification TXT record already exists in domain DNS zone
        $existingRecord = $recordSet.Records | Where-Object { $_.Value -eq $validationCode }
        if ($existingRecord) {
            Add-LogMessage -Level InfoSuccess "Verification TXT record already exists in '$($config.domain.fqdn)' DNS zone."
        } else {
            # Add the verification TXT record if it did not already exist
            $null = Add-AzDnsRecordConfig -RecordSet $recordSet -Value $validationCode
            $null = Set-AzDnsRecordSet -RecordSet $recordSet
            Add-LogMessage -Level Success "Verification TXT record added to '$($config.domain.fqdn)' DNS zone."
        }
    }
    # Verify domain on AAD
    $maxTries = 10
    $retryDelaySeconds = 60

    for ($tries = 1; $tries -le $maxTries; $tries++) {
        Confirm-MgDomain -DomainId $config.domain.fqdn | Out-Null
        Add-LogMessage -Level Info "Checking domain verification status on SHM AAD (attempt $tries of $maxTries)..."
        $aadDomain = Get-MgDomain -DomainId $config.domain.fqdn
        if ($aadDomain.IsVerified) {
            Add-LogMessage -Level Success "Domain '$($config.domain.fqdn)' is verified on SHM AAD."
            break
        } elseif ($tries -eq $maxTries) {
            Add-LogMessage -Level Fatal "Failed to verify domain '$($config.domain.fqdn)' after $tries attempts. Please try again later."
        } else {
            Add-LogMessage -Level Warning "Verification check failed. Retrying in $retryDelaySeconds seconds..."
            Start-Sleep -Seconds $retryDelaySeconds
            Confirm-MgDomain -DomainId $config.domain.fqdn | Out-Null
        }
    }
}


# Make domain primary on SHM AAD
# ------------------------------
Add-LogMessage -Level Info "Ensuring '$($config.domain.fqdn)' is primary domain on SHM AAD."
if ($aadDomain.IsDefault) {
    Add-LogMessage -Level InfoSuccess "'$($config.domain.fqdn)' is already primary domain on SHM AAD."
} else {
    $null = Update-MgDomain -DomainId $config.domain.fqdn -IsDefault
    $aadDomain = Get-MgDomain -DomainId $config.domain.fqdn
    if ($aadDomain.IsDefault) {
        Add-LogMessage -Level Success "Set '$($config.domain.fqdn)' as primary domain on SHM AAD."
    } else {
        Add-LogMessage -Level Fatal "Unable to set '$($config.domain.fqdn)' as primary domain on SHM AAD!"
    }
}


# Sign out of Microsoft Graph
# ---------------------------
Disconnect-MgGraph


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
