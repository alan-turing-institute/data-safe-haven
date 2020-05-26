# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [Parameter(Mandatory = $true, HelpMessage = "sAMAccountName for the service account user (must be unique in the Active Directory)")]
    [string]$PostgresDbServiceAccountName,
    [Parameter(Mandatory = $true, HelpMessage = "Password for the service account user")]
    [string]$PostgresDbServiceAccountPassword,
    [Parameter(Mandatory = $true, HelpMessage = "Hostname for the Postgres VM")]
    [string]$PostgresVmHostname,
    [Parameter(Mandatory = $true, HelpMessage = "OU containing service accounts")]
    [string]$ServiceOuPath,
    [Parameter(Mandatory = $true, HelpMessage = "FQDN for the SHM")]
    [string]$ShmFqdn,
    [Parameter(Mandatory = $true, HelpMessage = "NetBios name for the SHM")]
    [string]$ShmNetbiosName,
    [Parameter(Mandatory = $true, HelpMessage = "NetBios name for the SRE")]
    [string]$SreNetbiosName
)

# Initialise useful variables
$userName = "${SreNetbiosName} ${PostgresVmHostname} Service Account"
$accountPasswordSecureString = ConvertTo-SecureString -AsPlainText $PostgresDbServiceAccountPassword -Force
# NB. the SPN and UPN *must* have this exact name for authentication to work
$servicePrincipalName = "POSTGRES/${PostgresVmHostname}.$($ShmFqdn.ToLower())"
$userPrincipalName = "${servicePrincipalName}@$($ShmFqdn.ToUpper())"

# Ensure that the service account user exists in the AD
if (Get-ADUser -Filter "SamAccountName -eq '$PostgresDbServiceAccountName'") {
    Write-Output " [o] Service principal user '$userName' ('$PostgresDbServiceAccountName') already exists"
} else {
    $_ = New-ADUser -Name "$userName" `
                    -AccountPassword $accountPasswordSecureString `
                    -Description "$userName" `
                    -DisplayName "$userName" `
                    -Enabled $true `
                    -PasswordNeverExpires $true `
                    -Path "$ServiceOuPath" `
                    -SamAccountName "$PostgresDbServiceAccountName" `
                    -ServicePrincipalNames $servicePrincipalName `
                    -UserPrincipalName "$userPrincipalName"
    if ($?) {
        Write-Output " [o] Service principal user '$userName' ($PostgresDbServiceAccountName) created"
    } else {
        Write-Output " [x] Failed to create service principal user '$userName' ($PostgresDbServiceAccountName)!"
    }
}

# Generate a keytab file for the service principal we created above
# Note that this will invalidate any previous keytabs created for this user
$keytabFilename = "postgres.keytab"
# We redirect all output to STDOUT to avoid a Powershell bug when processes write to STDERR
# See https://mnaoumov.wordpress.com/2015/01/11/execution-of-external-commands-in-powershell-done-right/ for more details
$result = cmd /c "ktpass /out $keytabFilename /princ $userPrincipalName /mapuser ${ShmNetbiosName}\${PostgresDbServiceAccountName} /crypto ALL +rndpass -ptype KRB5_NT_PRINCIPAL 2>&1"
Write-Output $result
$b64keytab = [convert]::ToBase64String(([IO.File]::ReadAllBytes($keytabFilename)))
Write-Output " [o] Extracted keytab: $b64keytab"
