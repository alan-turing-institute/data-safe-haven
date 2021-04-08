# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [Parameter(HelpMessage = "Hostname for the VM")]
    [string]$Hostname,
    [Parameter(HelpMessage = "Name/description for the service account user")]
    [string]$Name,
    [Parameter(HelpMessage = "sAMAccountName for the service account user (must be unique in the Active Directory)")]
    [string]$SamAccountName,
    [Parameter(HelpMessage = "FQDN for the SHM")]
    [string]$ShmFqdn,
    [Parameter(HelpMessage = "Name of the service we are registering against")]
    [string]$ServiceName = "POSTGRES"
)

# Initialise SPN and UPN. NB. they must have this *exact* name for authentication to work
$servicePrincipalName = "${ServiceName}/${Hostname}.$($ShmFqdn.ToLower())"
$userPrincipalName = "${servicePrincipalName}@$($ShmFqdn.ToUpper())"

# Ensure that the service account user exists in the AD
Write-Output " [ ] Ensuring that account '$Name' ($SamAccountName) exists"
$adUser = Get-ADUser -Filter "SamAccountName -eq '$SamAccountName'"
if ($? -And $adUser) {
    Write-Output " [o] Found user '$Name' ($SamAccountName)"
} else {
    Write-Output " [x] Failed to find user '$Name' ($SamAccountName)!"
    exit 1
}

# Set the service principal details
Write-Output " [ ] Ensuring that '$Name' ($SamAccountName) is registered as a service principal"
$adUser | Set-ADUser -ServicePrincipalNames @{Replace = $servicePrincipalName } -UserPrincipalName "$userPrincipalName"
if ($?) {
    Write-Output " [o] Registered '$Name' ($SamAccountName) as '$servicePrincipalName'"
} else {
    Write-Output " [x] Failed to register '$Name' ($SamAccountName) as '$servicePrincipalName'!"
    exit 1
}
