param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId,
  [Parameter(Position=1, Mandatory = $false, HelpMessage = "Remote folder to write SSL certificate to")]
  [string]$remoteDirectory,
  [Parameter(Position=2, Mandatory = $false, HelpMessage = "Working directory (defaults to '~/Certificates')")]
  [string]$localDirectory = $null
)

if([String]::IsNullOrEmpty($localDirectory)) {
  $localDirectory = "~/Certificates"
}
if([String]::IsNullOrEmpty($remoteDirectory)) {
  $remoteDirectory = "/Certificates"
}


Import-Module Az
Import-Module (Join-Path $PSScriptRoot ".." ".." ".." ".." "DsgConfig.psm1") -Force

# Get DSG config
$config = Get-DsgConfig($dsgId);

# Temporarily switch to DSG subscription
$prevContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;

# Find RDS Gateway VM name by IP address
$vmResourceGroup = $config.dsg.rds.rg;
$vmIpAddress = $config.dsg.rds.gateway.ip
Write-Host " - Finding VM with IP $vmIpAddress"
## Get all VMs in resource group
$vms = Get-AzVM -ResourceGroupName $vmResourceGroup
## Get the NICs attached to all the VMs in the resource group
$vmNicIds = ($vms | ForEach-Object{(Get-AzVM -ResourceGroupName $vmResourceGroup -Name $_.Name).NetworkProfile.NetworkInterfaces.Id})
$vmNics = ($vmNicIds | ForEach-Object{Get-AzNetworkInterface -ResourceGroupName $vmResourceGroup -Name $_.Split("/")[-1]})
## Filter the NICs to the one matching the desired IP address and get the name of the VM it is attached to
$vmName = ($vmNics | Where-Object{$_.IpConfigurations.PrivateIpAddress -match $vmIpAddress})[0].VirtualMachine.Id.Split("/")[-1]
Write-Host " - VM '$vmName' found"

# Run remote script
$scriptPath = Join-Path $PSScriptRoot ".." "remote_scripts" "Create_Ssl_Csr_Remote.ps1"

$csrParams = @{
    "rdsFqdn" = "`"$($config.dsg.rds.gateway.fqdn)`""
    "shmName" = "`"$($config.shm.name)`""
    "orgName" = "`"$($config.shm.organisation.name)`""
    "townCity" = "`"$($config.shm.organisation.townCity)`""
    "stateCountyRegion" = "`"$($config.shm.organisation.stateCountyRegion)`""
    "countryCode" = "`"$($config.shm.organisation.countryCode)`""
    "remoteDirectory" = "`"$remoteDirectory`""
};

Write-Host " - Generating CSR on VM '$vmName'"

$result = Invoke-AzVMRunCommand -ResourceGroupName $vmResourceGroup -Name $vmName `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
    -Parameter $csrParams

$msg = $result.Value[0].Message
# Extract CSR from result message
$csr = ($msg -replace "(?sm).*(-----BEGIN NEW CERTIFICATE REQUEST-----)(.*)(-----END NEW CERTIFICATE REQUEST-----).*", '$1$2$3') 
# Remove any leading spaces or tabs from CSR lines
$csr = ($csr -replace '(?m)^[ \t]*', '')
# Extract CSR filename from result message (to allow easy matching to remote VM for troubleshooting)
$csrFilestem = ($msg -replace "(?sm).*-----BEGIN CSR FILESTEM-----(.*)-----END CSR FILESTEM-----.*", '$1') 

# Write the CSR to temprary storage
$csrDir = New-Item -Path "$localDirectory" -Name "$csrFilestem" -ItemType "directory"
$csrPath = (Join-Path $csrDir "$csrFilestem.csr")
$csr | Out-File -Filepath $csrPath
Write-Host " - CSR saved to '$csrPath'"

# Switch back to previous subscription
$_ = Set-AzContext -Context $prevContext;

return $csrPath