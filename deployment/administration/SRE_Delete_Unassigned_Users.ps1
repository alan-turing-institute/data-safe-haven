param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId
)

Import-Module Az.Accounts -ErrorAction Stop
Import-Module $PSScriptRoot/../common/AzureCompute -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../common/Logging -Force -ErrorAction Stop

# Get config
# -------------------------------
$config = Get-ShmConfig -shmId $shmId
# $originalContext = Get-AzContext

# Extract list of users
# ---------------------
# $null = Set-AzContext -SubscriptionId $config.subscriptionName -ErrorAction Stop
# Add-LogMessage -Level Info "Exporting user list for $($config.shm.id) from $($config.dc.vmName)..."
# Run remote script
# $script = @"
# `$userOuPath = (Get-ADObject -Filter * | Where-Object { `$_.Name -eq "Safe Haven Research Users" }).DistinguishedName
# `$users = Get-ADUser -Filter * -SearchBase "`$userOuPath" -Properties *
# foreach (`$user in `$users) {
#     `$groupName = (`$user | Select-Object -ExpandProperty MemberOf | ForEach-Object { ((`$_ -Split ",")[0] -Split "=")[1] }) -join "|"
#     `$user | Add-Member -NotePropertyName GroupName -NotePropertyValue `$groupName -Force
# }
# `$users | Select-Object SamAccountName,GivenName,Surname,Mobile,GroupName | `
#          ConvertTo-Csv | Where-Object { `$_ -notmatch '^#' } | `
#          ForEach-Object { `$_.replace('"','') }
# "@


$script = @"
`$userOuPath = (Get-ADObject -Filter * | Where-Object { `$_.Name -eq "Safe Haven Research Users" }).DistinguishedName
`$users = Get-ADUser -Filter * -SearchBase "`$userOuPath" -Properties *
foreach (`$user in `$users) {
    `$groupName = (`$user | Select-Object -ExpandProperty MemberOf | ForEach-Object { ((`$_ -Split ",")[0] -Split "=")[1] }) -join "|"
    `$user | Add-Member -NotePropertyName GroupName -NotePropertyValue `$groupName -Force
}

# Delete users not found in any group
foreach (`$user in `$users) {
    if (!(`$user.GroupName)) {
        `$name = `$user.SamAccountName
        Remove-ADUser -Identity `$name
    }
}

# Force sync with AzureAD. It will still take around 5 minutes for changes to propagate
Write-Output "Synchronising locally Active Directory with Azure"
try {
    Import-Module -Name "C:\Program Files\Microsoft Azure AD Sync\Bin\ADSync" -ErrorAction Stop
    Start-ADSyncSyncCycle -PolicyType Delta
}
catch [System.IO.FileNotFoundException] {
    Write-Output "Skipping as Azure AD Sync is not installed"
}
catch {
    Write-Output "Unable to run Azure Active Directory synchronisation!"
}
"@

$result = Invoke-RemoteScript -Shell "PowerShell" -Script $script -VMName $config.dc.vmName -ResourceGroupName $config.dc.rg

# # Delete users not found in any group (with exception for named SG e.g. "Sandbox")
# # --------------------------------------------------------------------------------
# Add-LogMessage -Level Info "Deleting users from $($config.shm.id) not in any security group..."
# $users = $result.Value[0].Message | ConvertFrom-Csv
# foreach ($user in $users) {
#     if (!($user.GroupName)) {
#         $name = $user.SamAccountName
#         $script = "Remove-ADUser -Identity $name"
#         Invoke-RemoteScript -Shell "PowerShell" -Script $script -VMName $config.dc.vmName -ResourceGroupName $config.dc.rg
#     }
# }

# $null = Set-AzContext -Context $originalContext -ErrorAction Stop