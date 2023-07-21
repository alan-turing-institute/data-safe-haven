param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId
)

Import-Module Az.Accounts -ErrorAction Stop
Import-Module $PSScriptRoot/../common/AzureCompute -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../common/Logging -Force -ErrorAction Stop

# Get config and original context 
# -------------------------------
$config = Get-ShmConfig -shmId $shmId
$originalContext = Get-AzContext

# Extract list of users
# ---------------------
$null = Set-AzContext -SubscriptionId $config.subscriptionName -ErrorAction Stop
Add-LogMessage -Level Info "Exporting user list for $($config.shm.id) from $($config.dc.vmName)..."
# Run remote script
$script = @"
`$userOuPath = (Get-ADObject -Filter * | Where-Object { `$_.Name -eq "Safe Haven Research Users" }).DistinguishedName
`$users = Get-ADUser -Filter * -SearchBase "`$userOuPath" -Properties *
foreach (`$user in `$users) {
    `$groupName = (`$user | Select-Object -ExpandProperty MemberOf | ForEach-Object { ((`$_ -Split ",")[0] -Split "=")[1] }) -join "|"
    `$user | Add-Member -NotePropertyName GroupName -NotePropertyValue `$groupName -Force
}
`$users | Select-Object SamAccountName,GivenName,Surname,Mobile,GroupName | `
         ConvertTo-Csv | Where-Object { `$_ -notmatch '^#' } | `
         ForEach-Object { `$_.replace('"','') }
"@
$result = Invoke-RemoteScript -Shell "PowerShell" -Script $script -VMName $config.dc.vmName -ResourceGroupName $config.dc.rg
$null = Set-AzContext -Context $originalContext -ErrorAction Stop

Write-Output $result

# Construct list of groups
# ------------------------
Add-LogMessage -Level Info "Constructing list of user groups from $($config.shm.id)..."
$users = $result.Value[0].Message | ConvertFrom-Csv
$securityGroups = @()
foreach ($user in $users) {
    $securityGroups += @($user.GroupName.Split("|"))
}
$securityGroups = $securityGroups | Sort-Object | Get-Unique

Write-Output $securityGroups