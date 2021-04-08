param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $false, HelpMessage = "Enter SRE ID (e.g. use 'sandbox' for Turing Development Sandbox SREs)")]
    [string]$sreId = $null
)

Import-Module $PSScriptRoot/common/Configuration -ErrorAction Stop -Force


# Generate and return the full config for the SHM or SRE
if (-not $sreId) {
    $config = Get-ShmConfig -shmId $shmId
} else {
    $config = Get-SreConfig -shmId $shmId -sreId $sreId
}
Write-Output ($config | ConvertTo-Json -Depth 10)
