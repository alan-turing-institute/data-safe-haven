param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId,
  [Parameter(Position=1, Mandatory = $true, HelpMessage = "Enter last octet of compute VM IP address (e.g. 160)")]
  [string]$ipLastOctet
)

Import-Module Az
Import-Module $PSScriptRoot/../DsgConfig.psm1 -Force

# Get DSG config
$config = Get-DsgConfig($dsgId);

# Temporarily switch to management subscription
$prevContext = Get-AzContext
Set-AzContext -SubscriptionId $config.dsg.subscriptionName;


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
# $diagnostic_scripts = @("restart_name_resolution_service.sh", "rerun_realm_join.sh", "check_ldap_connection.sh", "restart_sssd_service.sh")
$diagnostic_scripts = @("check_ldap_connection.sh")
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
                                  #@{"TEST_HOST"="$testHost"; "LDAP_USER"="$ldapUser"; "DOMAIN_LOWER"="$domainLower"; "SERVICE_PATH"="'$servicePath'"};
  Write-Output $result.Value;
}

# Switch back to previous subscription
Set-AzContext -Context $prevContext;
