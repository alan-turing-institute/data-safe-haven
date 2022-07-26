param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Which tier of mirrors should be torn down")]
    [ValidateSet("2", "3")]
    [string]$tier
)

Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Resources -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmConfig -shmId $shmId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.subscriptionName -ErrorAction Stop


# Tear down a single package mirror
# ---------------------------------
function Remove-PackageMirror {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Mirror to tear down (PyPI, CRAN)")]
        $MirrorType,
        [Parameter(Mandatory = $true, HelpMessage = "Whether this is an internal or external mirror")]
        [ValidateSet("Internal", "External")]
        $MirrorDirection
    )
    $vmName = "$MirrorType-$MirrorDirection-MIRROR-TIER-$tier".ToUpper()
    Remove-VirtualMachine -Name $vmName -ResourceGroupName $config.mirrors.rg -Force
    Remove-VirtualMachineDisk -Name "$vmName-OS-DISK" -ResourceGroupName $config.mirrors.rg
    Remove-VirtualMachineDisk -Name "$vmName-DATA-DISK" -ResourceGroupName $config.mirrors.rg
    Remove-VirtualMachineNIC -Name "$vmName-NIC" -ResourceGroupName $config.mirrors.rg
}


# Check if Resource Group exists
# ------------------------------
$null = Get-AzResourceGroup -Name $config.mirrors.rg -Location $config.location -ErrorVariable notExists -ErrorAction SilentlyContinue
if ($notExists) {
    Add-LogMessage -Level InfoSuccess "Resource group '$($config.mirrors.rg)' does not exist"
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
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
