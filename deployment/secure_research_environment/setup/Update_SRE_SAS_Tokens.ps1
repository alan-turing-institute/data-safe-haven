param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. 'project')")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE ID (e.g. 'sandbox')")]
    [string]$sreId
)

Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Resources -ErrorAction Stop
Import-Module Az.Storage -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureStorage -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/DataStructures -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig -shmId $shmId -sreId $sreId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop

# Update each SAS Access Policy to be valid for one year from now
# ---------------------------------------------------------------
$persistentStorageAccount = Get-StorageAccount -ResourceGroupName $config.shm.storage.persistentdata.rg -Name $config.sre.storage.persistentdata.account.name
foreach ($receptacleName in $config.sre.storage.persistentdata.containers.Keys) {
    $accessPolicyName = $config.sre.storage.persistentdata.containers[$receptacleName].accessPolicyName
    $null = Deploy-SasAccessPolicy -Name $accessPolicyName `
                                   -Permission $config.sre.storage.accessPolicies[$accessPolicyName].permissions `
                                   -StorageAccount $persistentStorageAccount `
                                   -ContainerName $receptacleName `
                                   -ValidityYears 1 `
                                   -Force
}

# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
