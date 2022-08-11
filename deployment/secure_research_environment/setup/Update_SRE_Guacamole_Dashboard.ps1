param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE ID (e.g. use 'sandbox' for Turing Development Sandbox SREs)")]
    [string]$sreId
)

Import-Module Az.Accounts -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureCompute -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig -shmId $shmId -sreId $sreId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Check that we are using the correct provider
# --------------------------------------------
if ($config.sre.remoteDesktop.provider -ne "ApacheGuacamole") {
    Add-LogMessage -Level Fatal "You should not be running this script when using remote desktop provider '$($config.sre.remoteDesktop.provider)'"
}


# Get list of SRDs
# ----------------
Add-LogMessage -Level Info "Retrieving list of SRD VMs..."
$VMs = Get-AzVM -ResourceGroupName $config.sre.srd.rg | `
    Where-Object { $_.Name -like "*SRD*" } | `
    ForEach-Object {
        $VM = $_;
        $VMSize = Get-AzVMSize -Location $config.sre.location | Where-Object { $_.Name -eq $VM.HardwareProfile.VmSize };
        @{
            "type"      = (($VM.HardwareProfile.VmSize).StartsWith("N") ? "GPU" : "CPU")
            "ipAddress" = (Get-AzNetworkInterface | Where-Object { $_.VirtualMachine.Id -eq $VM.Id }).IpConfigurations[0].PrivateIpAddress
            "cores"     = $VMSize.NumberOfCores
            "memory"    = $VMSize.MemoryInMB * 1mb / 1gb
            "os"        = $VM.OSProfile.WindowsConfiguration ? "Windows" : "Ubuntu"
        }
    } | Sort-Object -Property ipAddress


# Add an index to each Ubuntu and Windows VM
# The number increases with IP address
# ------------------------------------------
$VMs | ForEach-Object { $idxUbuntu = 0; $idxWindows = 0 } {
    if ($_.os -eq "Windows") { $_.index = $idxWindows; $idxWindows++ }
    elseif ($_.os -eq "Ubuntu") { $_.index = $idxUbuntu; $idxUbuntu++ }
}


# Update the remote file list
# ---------------------------
Add-LogMessage -Level Info "Updating Guacamole with $(@($VMs).Count) VMs..."
$lines = @("#! /bin/bash", "truncate -s 0 /opt/postgresql/data/connections.csv")
$lines += $VMs | ForEach-Object { "echo '$($_.os)-$($_.index) [$($_.cores)$($_.type)s $($_.memory)GB] ($($_.ipAddress));$($_.ipAddress)' >> /opt/postgresql/data/connections.csv" }
$lines += @("/opt/pg-ldap-sync/synchronise_database.sh")
$null = Invoke-RemoteScript -VMName $config.sre.remoteDesktop.guacamole.vmName -ResourceGroupName $config.sre.remoteDesktop.rg -Shell "UnixShell" -Script ($lines | Join-String -Separator "`n")


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
