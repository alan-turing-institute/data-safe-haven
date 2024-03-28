param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID for the old SHM (e.g. 'project')")]
    [string]$oldShmId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID for the new SHM (e.g. 'project')")]
    [string]$newShmId
)

Import-Module Az.Accounts -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureCompute -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$oldConfig = Get-ShmConfig -shmId $oldShmId
$newConfig = Get-ShmConfig -shmId $newShmId
$originalContext = Get-AzContext


# Extract list of users
# ---------------------
$null = Set-AzContext -SubscriptionId $oldConfig.subscriptionName -ErrorAction Stop
Add-LogMessage -Level Info "Exporting user list for $($oldConfig.shm.id) from $($oldConfig.dc.vmName)..."
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
$result = Invoke-RemoteScript -Shell "PowerShell" -Script $script -VMName $oldConfig.dc.vmName -ResourceGroupName $oldConfig.dc.rg
$null = Set-AzContext -Context $originalContext -ErrorAction Stop


# Construct list of groups
# ------------------------
Add-LogMessage -Level Info "Constructing list of user groups from $($oldConfig.shm.id)..."
$users = $result.Value[0].Message | ConvertFrom-Csv
$securityGroups = @()
foreach ($user in $users) {
    $securityGroups += @($user.GroupName.Split("|"))
}
$securityGroups = $securityGroups | Sort-Object | Get-Unique


# Create security groups on new SHM
# ---------------------------------
$null = Set-AzContext -SubscriptionId $newConfig.subscriptionName -ErrorAction Stop
Write-Output "Creating security groups and user list for $($newConfig.shm.id) on $($newConfig.dc.vmName)..."
$script = @"
foreach (`$groupName in @('$($securityGroups -join "','")')) {
    `$groupExists = `$(Get-ADGroup -Filter "Name -eq '`$groupName'").Name
    if (`$groupExists) {
        Write-Output " [o] Security group '`$groupName' already exists"
    } else {
        New-ADGroup -Name "`$groupName" -GroupScope Global -Description "`$groupName" -GroupCategory Security -Path "OU=$($newConfig.domain.ous.securityGroups.name),$($newConfig.domain.dn)"
        if (`$?) {
            Write-Output " [o] Security group '`$groupName' created successfully"
        } else {
            Write-Output " [x] Security group '`$groupName' creation failed!"
        }
    }
}
`$userFilePath = "$($newConfig.dc.installationDirectory)\$(Get-Date -UFormat %Y%m%d)_imported_user_details.csv"
"$($($users | ConvertTo-Csv | ForEach-Object { $_.replace('"', '') }) -join ';')" -split ';' | Out-File `$userFilePath
$($newConfig.dc.installationDirectory)\CreateUsers.ps1 -userFilePath `$userFilePath 2> Out-Null
"@
$null = Invoke-RemoteScript -Shell "PowerShell" -Script $script -VMName $newConfig.dc.vmName -ResourceGroupName $newConfig.dc.rg
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
