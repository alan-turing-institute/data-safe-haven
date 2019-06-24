param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId,
  [Parameter(Position=1, HelpMessage = "Enter VM size to use (defaults to 'Standard_DS2_v2')")]
  [string]$vmSize = (Read-Host -prompt "Enter VM size to use (defaults to 'Standard_DS2_v2')"),
  [Parameter(Position=2, HelpMessage = "Last octet of IP address (if not provided then the next available one will be used)")]
  [string]$fixedIp = (Read-Host -prompt "Last octet of IP address (if not provided then the next available one will be used)")
)
# Set default value if no argument is provided
if (!$vmSize) { $vmSize = "Standard_DS2_v2" }

Import-Module Az
Import-Module $PSScriptRoot/../DsgConfig.psm1 -Force
Import-Module $PSScriptRoot/../GeneratePassword.psm1 -Force

# Get DSG config
$config = Get-DsgConfig($dsgId)

# Fetch root user password (or create if not present)
$computeVmRootPassword = (Get-AzKeyVaultSecret -vaultName $config.dsg.keyVault.name -name $config.dsg.dsvm.admin.passwordSecretName).SecretValueText;
if ($null -eq $computeVmRootPassword) {
  # Create password locally but round trip via KeyVault to ensure it is successfully stored
  $newPassword = New-Password;
  $newPassword = (ConvertTo-SecureString $newPassword -AsPlainText -Force);
  Set-AzKeyVaultSecret -VaultName $config.dsg.keyVault.name -Name $config.dsg.dsvm.admin.passwordSecretName -SecretValue $newPassword;
}

# Set IP address if we have a fixed IP
$vmIpAddress = $null
if ($fixedIp) { $vmIpAddress = $config.dsg.network.subnets.data.prefix + "." + $fixedIp }

# Set machine name
$vmName = "DSG" + (Get-Date -UFormat "%Y%m%d%H%M")
if ($fixedIp) { $vmName = $vmName + "-" + $fixedIp }

$deployScriptDir = Join-Path (Get-Item $PSScriptRoot).Parent.Parent "azure-vms" -Resolve
$cloudInitDir = Join-Path $PSScriptRoot ".." ".." "dsg_configs" "cloud_init" -Resolve

# Read additional parameters that will be passed to the bash script from the config file
$adDcName = $config.shm.dc.hostname
$cloudInitYaml = "$cloudInitDir/cloud-init-compute-vm-DSG-" + $config.dsg.id.ToLower() + ".yaml"
$domainName = $config.shm.domain.fqdn
$ldapBaseDn = $config.shm.domain.userOuPath
$ldapBindDn = "CN=" + $config.dsg.users.ldap.dsvm.name + "," + $config.shm.domain.serviceOuPath
$ldapFilter = "(&(objectClass=user)(memberOf=CN=" + $config.dsg.domain.securityGroups.researchUsers.name + "," + $config.shm.domain.securityOuPath + "))"
$ldapSecretName = $config.dsg.users.ldap.dsvm.passwordSecretName
$ldapUserName = $config.dsg.users.ldap.dsvm.samAccountName
$managementKeyvault = $config.dsg.keyvault.name
$managementSubnetIpRange = $config.shm.network.subnets.identity.cidr
$mirrorIpCran = $config.dsg.mirrors.cran.ip
$mirrorIpPypi = $config.dsg.mirrors.pypi.ip
$sourceImage = $config.dsg.dsvm.vmImageType
$sourceImageVersion = $config.dsg.dsvm.vmImageVersion
$subscriptionSource = $config.dsg.dsvm.vmImageSubscription
$subscriptionTarget = $config.dsg.subscriptionName
$targetNsgName = $config.dsg.network.nsg.data.name
$targetRg = $config.dsg.dsvm.rg
$targetSubnet = $config.dsg.network.subnets.data.name
$targetVnet = $config.dsg.network.vnet.name
$vmAdminPasswordSecretName = $config.dsg.dsvm.admin.passwordSecretName

# If there is no custom cloud-init YAML file then use the default
if (-Not (Test-Path -Path $cloudInitYaml)) {
  $cloudInitYaml = Join-Path $cloudInitDir "cloud-init-compute-vm-DEFAULT.yaml" -Resolve
}
Write-Output "Using cloud-init from '$cloudInitYaml'"

# Convert arguments into the format expected by deploy_azure_dsg_vm.sh
$arguments = "-s '$subscriptionSource' \
              -t '$subscriptionTarget' \
              -i $sourceImage \
              -x $sourceImageVersion \
              -g $targetNsgName \
              -r $targetRg \
              -v $targetVnet \
              -w $targetSubnet \
              -b '$ldapBaseDn' \
              -c '$ldapBindDn' \
              -f '$ldapFilter' \
              -j $ldapUserName \
              -l $ldapSecretName \
              -m $managementKeyvault \
              -e $managementSubnetIpRange \
              -d $domainName \
              -a $adDcName \
              -p $vmAdminPasswordSecretName \
              -n $vmName \
              -y $cloudInitYaml \
              -z $vmSize"

# Add additional arguments if needed
if ($vmIpAddress) { $arguments = $arguments + " -q $vmIpAddress" }
if ($mirrorIpCran) { $arguments = $arguments + " -o $mirrorIpCran" }
if ($mirrorIpPypi) { $arguments = $arguments + " -k $mirrorIpPypi" }

$cmd =  "$deployScriptDir/deploy_azure_dsg_vm.sh $arguments"
bash -c $cmd


# Run PostgreSQL setup
# ====================
# Fetch Postgres DB Admin password (or create if not present)
$dbAdminRole = "admin"
$dbAdminUser = "dbadmin"
$dbAdminPasswordSecretName = ($config.dsg.shortName + "-pgdbadmin-password")
$dbAdminPassword = (Get-AzKeyVaultSecret -vaultName $config.dsg.keyVault.name -name $dbAdminPasswordSecretName).SecretValueText;
if ($null -eq $dbAdminPassword) {
  # Create password locally but round trip via KeyVault to ensure it is successfully stored
  $newPassword = New-Password;
  $newPassword = (ConvertTo-SecureString $newPassword -AsPlainText -Force);
  $_ = Set-AzKeyVaultSecret -VaultName $config.dsg.keyVault.name -Name $dbAdminPasswordSecretName -SecretValue $newPassword;
  $dbAdminPassword = (Get-AzKeyVaultSecret -VaultName $config.dsg.keyVault.name -Name $dbAdminPasswordSecretName).SecretValueText;
}

# Fetch Postgres DB Writer password (or create if not present)
$dbWriterRole = "writer"
$dbWriterUser = "dbwriter"
$dbWriterPasswordSecretName = ($config.dsg.shortName + "-pgdbwriter-password")
$dbWriterPassword = (Get-AzKeyVaultSecret -vaultName $config.dsg.keyVault.name -name $dbWriterPasswordSecretName).SecretValueText;
if ($null -eq $dbWriterPassword) {
  # Create password locally but round trip via KeyVault to ensure it is successfully stored
  $newPassword = New-Password;
  $newPassword = (ConvertTo-SecureString $newPassword -AsPlainText -Force);
  $_ = Set-AzKeyVaultSecret -VaultName $config.dsg.keyVault.name -Name $dbWriterPasswordSecretName -SecretValue $newPassword;
  $dbWriterPassword = (Get-AzKeyVaultSecret -VaultName $config.dsg.keyVault.name -Name $dbWriterPasswordSecretName).SecretValueText;
}

# Fetch Postgres DB Reader password (or create if not present)
$dbReaderRole = "reader"
$dbReaderUser = "dbreader"
$dbReaderPasswordSecretName = ($config.dsg.shortName + "-pgdbreader-password")
$dbReaderPassword = (Get-AzKeyVaultSecret -vaultName $config.dsg.keyVault.name -name $dbReaderPasswordSecretName).SecretValueText;
if ($null -eq $dbReaderPassword) {
  # Create password locally but round trip via KeyVault to ensure it is successfully stored
  $newPassword = New-Password;
  $newPassword = (ConvertTo-SecureString $newPassword -AsPlainText -Force);
  $_ = Set-AzKeyVaultSecret -VaultName $config.dsg.keyVault.name -Name $dbReaderPasswordSecretName -SecretValue $newPassword;
  $dbReaderPassword = (Get-AzKeyVaultSecret -VaultName $config.dsg.keyVault.name -Name $dbReaderPasswordSecretName).SecretValueText;
}

# Run remote script
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "create_postgres_roles.sh"

Write-Output " - Ensuring Postgres DB roles and initial shared users exist on VM $vmName"
Write-Output " - User: '$dbAdminUser'; Role: '$dbAdminRole'; Password in KeyVault secret name '$dbAdminPasswordSecretName'"
Write-Output " - User: '$dbWriterUser'; Role: '$dbWriterRole'; Password in KeyVault secret name '$dbWriterPasswordSecretName'"
Write-Output " - User: '$dbReaderUser'; Role: '$dbReaderRole'; Password in KeyVault secret name '$dbReaderPasswordSecretName'"

$params = @{
  DBADMINROLE = $dbAdminRole
  DBADMINUSER = $dbAdminUser
  DBADMINPWD = $dbAdminPassword
  DBWRITERROLE = $dbWriterRole
  DBWRITERUSER = $dbWriterUser
  DBWRITERPWD = $dbWriterPassword
  DBREADERROLE = $dbReaderRole
  DBREADERUSER = $dbReaderUser
  DBREADERPWD = $dbReaderPassword
};

# Switch to DSG subscription
$prevContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $subscriptionTarget;

$result = Invoke-AzVMRunCommand -ResourceGroupName $targetRg -Name "$vmName" `
          -CommandId 'RunShellScript' -ScriptPath $scriptPath -Parameter $params
Write-Output $result.Value;

# Switch back to previous subscription
$_ = Set-AzContext -Context $prevContext;