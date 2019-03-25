param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId
)

Import-Module Az
Import-Module $PSScriptRoot/../DsgConfig.psm1

# Get DSG config
$config = Get-DsgConfig($dsgId)

# Admin user credentials (must be same as for DSG DC for now)
$adminUser = $config.dsg.dc.admin.username
$adminPassword = (Get-AzKeyVaultSecret -vaultName $config.dsg.keyVault.name -name $config.dsg.dc.admin.passwordSecretName).SecretValueText

# VM sizes
$hackMdVmSize = "Standard_DS2_v2"
$gitlabVmSize = "Standard_DS2_v2"

# Patch cloud init templates
$shmDcFqdn = ($config.shm.dc.hostname + "." + $config.shm.domain.fqdn)
## -- GITLAB --
$gitlabFqdn = $config.dsg.linux.gitlab.hostname + "." + $config.dsg.domain.fqdn
$gitlabLdapUserDn = "CN=" + $config.dsg.users.ldap.gitlab.name + "," + $config.shm.domain.serviceOuPath
$gitlabUserPassword = (Get-AzKeyVaultSecret -vaultName $config.dsg.keyVault.name -name $config.dsg.users.ldap.gitlab.passwordSecretName).SecretValueText;
$gitlabUserFilter = "(&(objectClass=user)(memberOf=CN=" + $config.dsg.domain.securityGroups.researchUsers.name + "," + $config.shm.domain.securityOuPath + "))"
## Read template into string array (one entry per line in file)
$gitlabCloudInitTemplatePath = Join-Path $PSScriptRoot "cloud-init-gitlab.yaml"
$gitlabCloudInitTemplate = (Get-Content -Raw -Path $gitlabCloudInitTemplatePath)
## Patch template with DSG specific values
$gitlabCloudInit = $gitlabCloudInitTemplate.replace('<gitlab-rb-host>', $shmDcFqdn).
                                            replace('<gitlab-rb-bind-dn>', $gitlabLdapUserDn).
                                            replace('<gitlab-rb-pw>',$gitlabUserPassword).
                                            replace('<gitlab-rb-base>',$config.shm.domain.userOuPath).
                                            replace('<gitlab-rb-user-filter>',$gitlabUserFilter).
                                            replace('<gitlab-ip>',$config.dsg.linux.gitlab.ip).
                                            replace('<gitlab-hostname>',$config.dsg.linux.gitlab.hostname).
                                            replace('<gitlab-fqdn>',$gitlabFqdn)
Write-Output $gitlabCloudInit
## Encode as base64
$gitlabCustomData = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($gitlabCloudInit))
Write-Output $gitlabCustomData

$params = @{
"GITLab Server Name" = $config.dsg.linux.gitlab.vmName
"GITLab VM Size" = $gitlabVMSize
"GITLab IP Address" =  $config.dsg.linux.gitlab.ip 
"HACKMD Server Name" = $config.dsg.linux.hackmd.vmName
"HACKMD VM Size" = $hackmdVMSize
"HACKMD IP Address" = $config.dsg.linux.hackmd.ip
"Administrator User" = $adminUser
"Administrator Password" = (ConvertTo-SecureString $adminPassword -AsPlainText -Force)
"Virtual Network Name" = $config.dsg.network.vnet.name
"Virtual Network Resource Group" = $config.dsg.network.vnet.rg
"Virtual Network Subnet" = $config.dsg.network.subnets.data.name
"customData" = $gitlabCustomData
}

Write-Output $params

Exit 1

$templatePath = Join-Path $PSScriptRoot "linux-master-template.json"

New-AzResourceGroup -Name $config.dsg.linux.rg -Location $config.dsg.location
New-AzResourceGroupDeployment -ResourceGroupName $config.dsg.linux.rg `
  -TemplateFile $templatePath @params -Verbose
