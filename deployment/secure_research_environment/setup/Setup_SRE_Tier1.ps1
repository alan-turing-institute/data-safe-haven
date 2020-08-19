param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$configId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$adminUserName,
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$adminPublicKeyPath,
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$usersYamlPath
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $configId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Deploy a VM using adminUserName and adminPublicKeyPath usersYamlPath
$vmNic = Deploy-VirtualMachineNIC -Name "$vmName-NIC" -ResourceGroupName $config.sre.dsvm.rg -Subnet $subnet -PrivateIpAddress $vmIpAddress -Location $config.sre.location
$bootDiagnosticsAccount = Deploy-StorageAccount -Name $config.sre.storage.bootdiagnostics.accountName -ResourceGroupName $config.sre.storage.bootdiagnostics.rg -Location $config.sre.location
$params = @{
    Name                   = $vmName
    Size                   = $vmSize
    AdminPassword          = < generate a random $vmAdminPassword >
    AdminUsername          = < generate a random $vmAdminUsername >
    BootDiagnosticsAccount = $bootDiagnosticsAccount
    CloudInitYaml          = $cloudInitTemplate
    location               = $config.sre.location
    NicId                  = $vmNic.Id
    OsDiskSizeGb           = $config.sre.dsvm.disks.os.sizeGb
    OsDiskType             = $config.sre.dsvm.disks.os.type
    ResourceGroupName      = $config.sre.dsvm.rg
    DataDiskIds            = @($homeDisk.Id, $scratchDisk.Id)
    ImageId                = $image.Id
}
$null = Deploy-UbuntuVirtualMachine @params


# Run ansible to configure VM
# generate accounts for admin users (including TOTP)
# this generates TOTP codes for a list of users


# delete the default admin account (could be ansible or separate) could use Invoke-RemoteScript


# NB. to update for new users simply re-run this script
# We need to make sure that this allows us to remove users too


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext
