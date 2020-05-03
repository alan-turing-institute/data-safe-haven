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
try {
    # Check if domain name has already been added to AAD
    $_ = Get-AzureADDomain -Name $config.domain.fqdn
    Add-LogMessage -Level Success "'$($config.domain.fqdn)' already present as custom domain on SHM AAD."
} catch {
    # Get-AzureADDomain throws a 404 "Not found" HTTP exception if the 
    # domain name record is not present on the AAD
    $ex = $_.Exception
    # If error code is 404, create the domain name record on the AAD
    # Otherwise rethrow the exception
    if($ex.ErrorCode -eq "404") {
        $_ = New-AzureADDomain -Name $config.domain.fqdn
        Add-LogMessage -Level Success "'$($config.domain.fqdn)' added as custom domain on SHM AAD."
    } else {
        throw $ex
    }
}


# Verify the SHM domain record for the Azure AD
# ---------------------------------------------
Add-LogMessage -Level Info "Verifying SHM domain on AAD..."
$aadDomain = Get-AzureADDomain -Name $config.domain.fqdn
if($aadDomain.IsVerified) {
    Add-LogMessage -Level Success "'$($config.domain.fqdn)' already verified on SHM AAD."
}
else {
    # Print manual verification instructions
    $recordSet = Get-AzureADDomainVerificationDnsRecord -Name $config.domain.fqdn `
                          | Where-Object { $_.RecordType -eq "Txt"}
    
    Write-Host ""
    Write-Host "Domain verification details"
    Write-Host "---------------------------"
    Write-Host "  Name: @"
    Write-Host "  Type: TXT"
    Write-Host "  TTL: $($recordset.Ttl); TTL unit: Seconds"
    Write-Host "  Value: $($recordset.Text)"
    Write-Host ""
}

# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext