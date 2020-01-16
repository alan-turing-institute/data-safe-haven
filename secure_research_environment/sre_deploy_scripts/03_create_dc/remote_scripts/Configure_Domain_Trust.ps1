# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
Param(
    [parameter(HelpMessage="Enter FQDN of management domain i.e. turingsafehaven.ac.uk")]
    [ValidateNotNullOrEmpty()]
    [String]$sreFqdn,
    [parameter(HelpMessage="Enter username of an admin")]
    [ValidateNotNullOrEmpty()]
    [String]$sreDcAdminUsername,
    [parameter(HelpMessage="Enter encrypted password of an admin")]
    [ValidateNotNullOrEmpty()]
    [String]$sreDcAdminPasswordEncrypted
)

# Convert encrypted string to secure string and then to plaintext
$sreDcAdminPasswordSecureString = ConvertTo-SecureString -String $sreDcAdminPasswordEncrypted -Key (1..16)
$sreDcAdminPassword = [System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($sreDcAdminPasswordSecureString))

# Connect to remote domain
Write-Host "Connecting to remote domain..."
$remoteDirectoryContext = New-Object System.DirectoryServices.ActiveDirectory.DirectoryContext("Domain", $sreFqdn, $sreDcAdminUsername, $sreDcAdminPassword)
if ($?) {
    Write-Host " [o] Succeeded"
} else {
    Write-Host " [x] Failed!"
}

# Access remote domain
Write-Host "Accessing remote domain '$sreFqdn'..."
$remoteDomainConnection = [System.DirectoryServices.ActiveDirectory.Domain]::GetDomain($remoteDirectoryContext)
if ($?) {
    Write-Host " [o] Succeeded"
} else {
    Write-Host " [x] Failed!"
}

# Access local domain
Write-Host "Accessing local domain..."
$localDomainConnection = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
if ($?) {
    Write-Host " [o] Succeeded"
} else {
    Write-Host " [x] Failed!"
}

# Checking whether that trust relationship exists
Write-Host "Ensuring that trust relationship exists..."
$relationshipExists = $false
foreach($relationship in $localDomainConnection.GetAllTrustRelationships()) {
    if (($relationship.TargetName -eq $sreFqdn) -and ($relationship.TrustDirection -eq "Bidirectional")){
      $relationshipExists = $true
    }
}
# Create relationship if it does not exist
if($relationshipExists) {
    Write-Host " [o] Bidirectional trust relationship already exists"
} else {
    Write-Host "Creating new trust relationship..."
    $localDomainConnection.CreateTrustRelationship($remoteDomainConnection, "Bidirectional")
    if ($?) {
        Write-Host " [o] Succeeded"
    } else {
        Write-Host " [x] Failed!"
    }
}