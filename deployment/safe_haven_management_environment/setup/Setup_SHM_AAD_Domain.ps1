param(
  [Parameter(Position = 0,Mandatory = $true,HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
  [string]$shmId
)

Import-Module Az
Import-Module AzureAD.Standard.Preview
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force

# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmFullConfig $shmId
$originalContext = Get-AzContext


# Add the SHM domain record to the Azure AD
# -----------------------------------------
Add-LogMessage -Level Info "Adding SHM domain to AAD..."

# Check if domain name has already been added to AAD. Calling Get-AzureADDomain with no
# arguments avoids having to use a try/catch to handle an expected 404 "Not found exception"
# if the domain has not yet been added.
$aadDomain = Get-AzureADDomain | Where-Object { $_.Name -eq $config.domain.fqdn }
if($aadDomain) {
    Add-LogMessage -Level Success "'$($config.domain.fqdn)' already present as custom domain on SHM AAD."
} else {
    $_ = New-AzureADDomain -Name $config.domain.fqdn
    Add-LogMessage -Level Success "'$($config.domain.fqdn)' added as custom domain on SHM AAD."
}

# Verify the SHM domain record for the Azure AD
# ---------------------------------------------
Add-LogMessage -Level Info "Verifying domain on SHM AAD..."
if($aadDomain.IsVerified) {
    Add-LogMessage -Level Success "'$($config.domain.fqdn)' already verified on SHM AAD."
}
else {
    # Fetch TXT version of AAD domain verification record set
    $validationRecord = Get-AzureADDomainVerificationDnsRecord -Name $config.domain.fqdn `
                          | Where-Object { $_.RecordType -eq "Txt"}
    # Make a DNS TXT Record object containing the validation code
    $validationCode = New-AzDnsRecordConfig -Value $validationRecord.Text

    # Temporarily switch to domain subscription
    $_ = Set-AzContext -Subscription $config.dns.subscriptionName

    # Check if this validation record already exists for the domain
    $recordSet = Get-AzDnsRecordSet -RecordType TXT -Name "@" `
                 -ZoneName $config.domain.fqdn -ResourceGroupName $config.dns.rg `
                 -ErrorVariable notExists -ErrorAction SilentlyContinue
    if($notExists) {
        # If no TXT record set exists at all, create a new TXT record set with the domain validation code
        $_ = New-AzDnsRecordSet -RecordType TXT -Name "@" `
             -Ttl $validationRecord.Ttl -DnsRecords $validationCode `
             -ZoneName $config.domain.fqdn -ResourceGroupName $config.dns.rg
        Add-LogMessage -Level Success "Verification TXT record added to '$($config.domain.fqdn)' DNS zone."
    } else {
        # Check if the verification TXT record already exists in domain DNS zone
        $existingRecord = $recordSet.Records | Where-Object { $_.Value -eq $validationCode}
        if($existingRecord) {
            Add-LogMessage -Level Success "Verification TXT record already exists in '$($config.domain.fqdn)' DNS zone."
        } else {
            # Add the verification TXT record if it did not already exist
            $_ = Add-AzDnsRecordConfig -RecordSet $recordSet -Value $validationCode
            $_ = Set-AzDnsRecordSet -RecordSet $recordSet
            Add-LogMessage -Level Success "Verification TXT record added to '$($config.domain.fqdn)' DNS zone."
        }
    }
    # Verify domain on AAD
    $maxTries = 10
    $retryDelaySeconds = 60

    for($tries = 1; $tries -le $maxTries; $tries++){
        Add-LogMessage -Level Info "Checking domain verification status on SHM AAD (attempt $tries of $maxTries)..."
        try {
            $_ = Confirm-AzureADDomain -Name $config.domain.fqdn
        } catch {
            # Confirm-AzureADDomain throws a 400 BadRequest exception if either the verification TXT record is not
            # found or if the domain is already verified. Checking the exception message text to only ignore these
            # conditions feels error prone. Instead print the exception messahe as a warning and continue with the
            # retry loop
            $ex = $_.Exception
            $errorMessage = $ex.ErrorContent.Message.Value
            Add-LogMessage -Level Warning "$errorMessage"
        }
        $aadDomain = Get-AzureADDomain -Name $config.domain.fqdn
        if($aadDomain.IsVerified) {
            Add-LogMessage -Level Success "Domain '$($config.domain.fqdn)' is verified on SHM AAD."
            break
        } elseif($tries -eq $maxTries) {
            Add-LogMessage -Level Fatal "Failed to verify domain after $tries attempts. Please try again later."
        } else {
            Add-LogMessage -Level Warning "Verification check failed. Retrying in $retryDelaySeconds seconds..."
            Start-Sleep -Seconds $retryDelaySeconds
        }
    }
}

# Make domain primary on SHM AAD
# ------------------------------
if($aadDomain.IsVerified) {
    Add-LogMessage -Level Info "Making '$($config.domain.fqdn)' is primary domain on SHM AAD."
    if($aadDomain.isDefault){
        Add-LogMessage -Level Success "'$($config.domain.fqdn)' is already primary domain on SHM AAD."
    } else {
        $_ = Set-AzureADDomain -Name $config.domain.fqdn -IsDefault $TRUE
        Add-LogMessage -Level Success "Set '$($config.domain.fqdn)' as primary domain on SHM AAD."

    }
}

# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext