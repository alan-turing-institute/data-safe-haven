# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# Fror details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
  [Parameter(Mandatory = $false, HelpMessage = "SAM account name for LDAP search account")]
  [string]$ldapSearchSamAccountName,
  [Parameter(Mandatory = $false, HelpMessage = "Base-64 encoded password for LDAP search account")]
  [string]$ldapSearchPasswordB64
)

# Deserialise Base-64 encoded variables
# -------------------------------------
$ldapSearchPassword = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($ldapSearchPasswordB64))

# Reset password in Active Directory
# ----------------------------------
Write-Output "Resetting password for '$ldapSearchSamAccountName'..."
Get-ADUser -Filter "SamAccountName -eq '$ldapSearchSamAccountName'"
Set-ADAccountPassword -Identity $ldapSearchSamAccountName -NewPassword (ConvertTo-SecureString -AsPlainText "$ldapSearchPassword" -Force)
