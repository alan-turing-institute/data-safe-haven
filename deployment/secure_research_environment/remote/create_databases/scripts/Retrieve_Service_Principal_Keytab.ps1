# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [Parameter(Mandatory = $true, HelpMessage = "Whether SSIS should be enabled")]
    [string]$ShmFqdn,
    [Parameter(Mandatory = $true, HelpMessage = "Whether SSIS should be enabled")]
    [string]$ShmNetbiosName,
    [Parameter(Mandatory = $true, HelpMessage = "Whether SSIS should be enabled")]
    [string]$SreNetbiosName,
    [Parameter(Mandatory = $true, HelpMessage = "Whether SSIS should be enabled")]
    [string]$PostgresDbServiceAccountName,
    [Parameter(Mandatory = $true, HelpMessage = "Whether SSIS should be enabled")]
    [string]$PostgresDbServiceAccountPassword,
    [Parameter(Mandatory = $true, HelpMessage = "Whether SSIS should be enabled")]
    [string]$PostgresDbHostname,
    [Parameter(Mandatory = $true, HelpMessage = "Whether SSIS should be enabled")]
    [string]$ServiceOuPath
)

# setspn -S POSTGRES/PGS-ANA-SANDBOX.testa.dsgroupdev.co.uk SAFEHAVENTESTA\pgdbsasandbox
# ktpass /out postgres.keytab /princ POSTGRES/PGS-ANA-SANDBOX.testa.dsgroupdev.co.uk@TESTA.DSGROUPDEV.CO.UK /mapuser SAFEHAVENTESTA\pgdbsasandbox /crypto ALL +rndpass -ptype KRB5_NT_PRINCIPAL

# Create useful variables
$shmFqdnLower = $ShmFqdn.ToLower()
$shmFqdnUpper = $ShmFqdn.ToUpper()
$userName = "${SreNetbiosName} ${PostgresDbHostname} Service Account"
$servicePrincipalName = "POSTGRES/${PostgresDbHostname}.${shmFqdnLower}"
$userPrincipalName = "${servicePrincipalName}@${shmFqdnUpper}"
$PostgresDbServiceAccountPasswordSecureString = ConvertTo-SecureString -AsPlainText $PostgresDbServiceAccountPassword -Force


# Ensure that the SPN user exists in the AD
if (Get-ADUser -Filter "SamAccountName -eq '$PostgresDbServiceAccountName'") {
    Write-Output " [o] User '$userName' ('$PostgresDbServiceAccountName') already exists"
} else {
    $_ = New-ADUser -Name "$userName" `
                    -AccountPassword $PostgresDbServiceAccountPasswordSecureString `
                    -Description "$userName" `
                    -DisplayName "$userName" `
                    -Enabled $true `
                    -PasswordNeverExpires $true `
                    -Path "$ServiceOuPath" `
                    -SamAccountName "$PostgresDbServiceAccountName" `
                    -ServicePrincipalNames $servicePrincipalName `
                    -UserPrincipalName "${userPrincipalName}"
    if ($?) {
        Write-Output " [o] Service principal user '$userName' ($PostgresDbServiceAccountName) created"
    } else {
        Write-Output " [x] Failed to create service principal user '$userName' ($PostgresDbServiceAccountName)!"
    }
}

# setspn -S ${servicePrincipalName} ${ShmNetbiosName}\${PostgresDbServiceAccountName}
# $mapUser = "${ShmNetbiosName}\${PostgresDbServiceAccountName}"
# ktpass /out postgres.keytab /princ $userPrincipalName /mapuser $mapUser /crypto ALL +rndpass -ptype KRB5_NT_PRINCIPAL


# We need to change ErrorActionPreference to avoid a Powershell bug when processes write to STDERR
# See https://mnaoumov.wordpress.com/2015/01/11/execution-of-external-commands-in-powershell-done-right/
# $originalPreference = $ErrorActionPreference
# $ErrorActionPreference = "Continue"
# ktpass /out postgres.keytab /princ $userPrincipalName /mapuser "${ShmNetbiosName}\${PostgresDbServiceAccountName}" /crypto ALL +rndpass -ptype KRB5_NT_PRINCIPAL
$result = cmd /c "ktpass /out postgres.keytab /princ $userPrincipalName /mapuser ${ShmNetbiosName}\${PostgresDbServiceAccountName} /crypto ALL +rndpass -ptype KRB5_NT_PRINCIPAL 2>&1"
Write-Output $result
foreach ($line in $result) { Write-Output $result }

# $ErrorActionPreference = $originalPreference
$b64keytab = [convert]::ToBase64String(([IO.File]::ReadAllBytes("postgres.keytab")))
Write-Output "Keytab: $b64keytab"

$result = cmd /c "ktpass /out postgres.keytab /princ $userPrincipalName /mapuser ${ShmNetbiosName}\${PostgresDbServiceAccountName} /crypto ALL +rndpass -ptype KRB5_NT_PRINCIPAL" 2>&1 | ForEach-Object { "$_" }
