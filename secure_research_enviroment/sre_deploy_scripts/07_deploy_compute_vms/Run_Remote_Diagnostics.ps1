param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (usually a number e.g enter '9' for DSG9)")]
  [string]$sreId,
  [Parameter(Position=1, Mandatory = $true, HelpMessage = "Enter last octet of compute VM IP address (e.g. 160)")]
  [string]$ipLastOctet
)

Import-Module Az
Import-Module $PSScriptRoot/../../../common_powershell/Configuration.psm1 -Force

# Get SRE config
# --------------
$config = Get-SreConfig($sreId);
$originalContext = Get-AzContext

$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;


# Find VM with private IP address matching the provided last octect
## Turn provided last octect into full IP address in the data subnet
$vmIpAddress = ($config.dsg.network.subnets.data.prefix + "." + $ipLastOctet)
Write-Host " - Finding VM with IP $vmIpAddress"
## Get all compute VMs
$computeVms = Get-AzVM -ResourceGroupName $config.dsg.dsvm.rg
## Get the NICs attached to all the compute VMs
$computeVmNicIds = ($computeVms | ForEach-Object{(Get-AzVM -ResourceGroupName $config.dsg.dsvm.rg -Name $_.Name).NetworkProfile.NetworkInterfaces.Id})
$computeVmNics = ($computeVmNicIds | ForEach-Object{Get-AzNetworkInterface -ResourceGroupName $config.dsg.dsvm.rg -Name $_.Split("/")[-1]})
## Filter the NICs to the one matching the desired IP address and get the name of the VM it is attached to
$computeVmName = ($computeVmNics | Where-Object{$_.IpConfigurations.PrivateIpAddress -match $vmIpAddress})[0].VirtualMachine.Id.Split("/")[-1]

# Run remote scripts
$diagnostic_scripts = @("check_ldap_connection.sh", "restart_name_resolution_service.sh", "rerun_realm_join.sh", "restart_sssd_service.sh")
$testHost = $config.shm.dc.fqdn
$ldapUser = $config.dsg.users.ldap.dsvm.samAccountName
$domainLower = $config.shm.domain.fqdn
$servicePath = $config.shm.domain.serviceOuPath

$params = @{
  TEST_HOST = $config.shm.dc.fqdn
  LDAP_USER = $config.dsg.users.ldap.dsvm.samAccountName
  DOMAIN_LOWER = $config.shm.domain.fqdn
  SERVICE_PATH = "'" + $config.shm.domain.serviceOuPath + "'"
}

Write-Host " - Running diagnostic scripts on VM $computeVmName"

foreach ($diagnostic_script in $diagnostic_scripts) {
  $scriptPath = Join-Path $PSScriptRoot "remote_scripts" $diagnostic_script
  $result = Invoke-AzVMRunCommand -ResourceGroupName $config.dsg.dsvm.rg -Name "$computeVmName" `
                                  -CommandId 'RunShellScript' -ScriptPath $scriptPath `
                                  -Parameter $params
  Write-Output $result.Value;
}

# Switch back to previous subscription
$_ = Set-AzContext -Context $originalContext;
