param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
  [string]$shmId,
  [Parameter(Position=1, Mandatory = $true, HelpMessage = "Which tier of mirrors should be torn down")]
  [ValidateSet("2", "3")]
  [string]$tier
)

Import-Module Az
Import-Module $PSScriptRoot/../../common_powershell/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common_powershell/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common_powershell/Logging.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmFullConfig($shmId)
$originalContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.subscriptionName


# Tear down a single package mirror
# ---------------------------------
function Remove-PackageMirror {
    param(
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Mirror to tear down (PyPI, CRAN)")]
        $MirrorType,
        [Parameter(Position = 1, Mandatory = $true, HelpMessage = "Whether this is an internal or external mirror")]
        [ValidateSet("Internal", "External")]
        $MirrorDirection
    )
    $vmName = "$($MirrorType.ToUpper())-$($MirrorDirection.ToUpper())-MIRROR-TIER-$tier"
    Remove-VirtualMachine -Name $vmName -ResourceGroupName $config.mirrors.rg
    Remove-VirtualMachineDisk -Name "$vmName-OS-DISK" -ResourceGroupName $config.mirrors.rg
    Remove-VirtualMachineDisk -Name "$vmName-DATA-DISK" -ResourceGroupName $config.mirrors.rg
    Remove-VirtualMachineNIC -Name "$vmName-NIC" -ResourceGroupName $config.mirrors.rg
}


# Check if Resource Group exists
# ------------------------------

$_ = Get-AzResourceGroup -Name $config.mirrors.rg -Location $config.location -ErrorVariable notExists -ErrorAction SilentlyContinue
if ($notExists) {
    Add-LogMessage -Level InfoSuccess "Resource group '$config.mirrors.rg' does not exist"
} else {
    # Tear down package mirrors
    # -------------------------
    foreach ($mirrorType in ("PyPI", "CRAN")) {
      foreach ($mirrorDirection in ("External", "Internal")) {
          Remove-PackageMirror -MirrorType $mirrorType -MirrorDirection $mirrorDirection
      }
    }
}


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext
