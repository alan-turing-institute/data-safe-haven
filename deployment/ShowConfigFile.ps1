param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. 'project')")]
    [string]$shmId,
    [Parameter(Mandatory = $false, HelpMessage = "Enter SRE ID (e.g. 'sandbox')")]
    [string]$sreId = $null
)

Import-Module $PSScriptRoot/common/Configuration -Force -ErrorAction Stop


# Generate and return the full config for the SHM or SRE
if ($sreId) {
    $config = Get-SreConfig -shmId $shmId -sreId $sreId
} else {
    $config = Get-ShmConfig -shmId $shmId
}
Write-Output ($config | ConvertTo-Json -Depth 99)
