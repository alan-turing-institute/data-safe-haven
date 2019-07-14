param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId
)

Import-Module Az
Import-Module $PSScriptRoot/../DsgConfig.psm1 -Force

# Get DSG config
$config = Get-DsgConfig($dsgId);

# Temporarily switch to management subscription
$prevContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName;

# Directory for local and remote helper scripts
$helperScriptDir = Join-Path $PSScriptRoot "helper_scripts" "Prepare_SHM" -Resolve

# === Add DSG users and groups to SHM ====
Write-Host "Creating or retrieving user passwords"
function Create-DsgPassword($secretName){
    $password = (Get-AzKeyVaultSecret -vaultName $config.dsg.keyVault.name -name $secretName).SecretValueText;
    if ($null -eq $password) {
        Write-Host " - Creating secret '$secretName'"
        # Create password locally but round trip via KeyVault to ensure it is successfully stored
        $newPassword = New-Password;
        $newPassword = (ConvertTo-SecureString $newPassword -AsPlainText -Force);
        $_ = Set-AzKeyVaultSecret -VaultName $config.dsg.keyVault.name -Name $secretName -SecretValue $newPassword;
        $password = (Get-AzKeyVaultSecret -VaultName $config.dsg.keyVault.name -Name $secretName).SecretValueText;
    } else {
        Write-Host " - Using existing secret '$secretName'"
    }
    return $password
}
$hackmdPassword = Create-DsgPassword $config.dsg.users.ldap.hackmd.passwordSecretName
$gitlabPassword = Create-DsgPassword $config.dsg.users.ldap.gitlab.passwordSecretName
$dsvmPassword = Create-DsgPassword $config.dsg.users.ldap.dsvm.passwordSecretName
$testResearcherPassword = Create-DsgPassword $config.dsg.users.researchers.test.passwordSecretName

$scriptPath = Join-Path $helperScriptDir "remote_scripts" "Create_New_DSG_User_Service_Accounts_Remote.ps1"
$params = @{
    dsgFqdn = "`"$($config.dsg.domain.fqdn)`""
    researchUserSgName = "`"$($config.dsg.domain.securityGroups.researchUsers.name)`""
    researchUserSgDescription = "`"$($config.dsg.domain.securityGroups.researchUsers.description)`""
    ldapUserSgName = "`"$($config.shm.domain.securityGroups.dsvmLdapUsers.name)`""
    securityOuPath = "`"$($config.shm.domain.securityOuPath)`""
    serviceOuPath = "`"$($config.shm.domain.serviceOuPath)`""
    researchUserOuPath = "`"$($config.shm.domain.userOuPath)`""
    hackmdSamAccountName = "`"$($config.dsg.users.ldap.hackmd.samAccountName)`""
    hackmdName = "`"$($config.dsg.users.ldap.hackmd.name)`""
    hackmdPassword = $hackmdPassword
    gitlabSamAccountName = "`"$($config.dsg.users.ldap.gitlab.samAccountName)`""
    gitlabName = "`"$($config.dsg.users.ldap.gitlab.name)`""
    gitlabPassword = $gitlabPassword
    dsvmSamAccountName = "`"$($config.dsg.users.ldap.dsvm.samAccountName)`""
    dsvmName = "`"$($config.dsg.users.ldap.dsvm.name)`""
    dsvmPassword = $dsvmPassword
    testResearcherSamAccountName = "`"$($config.dsg.users.researchers.test.samAccountName)`""
    testResearcherName = "`"$($config.dsg.users.researchers.test.name)`""
    testResearcherPassword = $testResearcherPassword
}
Write-Host "Adding DSG users and groups to SHM"
$result = Invoke-AzVMRunCommand -ResourceGroupName $config.shm.dc.rg -Name $config.shm.dc.vmName `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
    -Parameter $params   
Write-Host $result.Value[0].Message
Write-Host $result.Value[1].Message   

# === Add DSG DNS entries to SHM ====
$scriptPath = Join-Path $helperScriptDir "remote_scripts" "Add_New_DSG_To_DNS_Remote.ps1"
$params = @{
    dsgFqdn = "`"$($config.dsg.domain.fqdn)`""
    dsgDcIp = "`"$($config.dsg.dc.ip)`""
    identitySubnetCidr = "`"$($config.dsg.network.subnets.identity.cidr)`""
    rdsSubnetCidr = "`"$($config.dsg.network.subnets.rds.cidr)`""
    dataSubnetCidr = "`"$($config.dsg.network.subnets.data.cidr)`""
}
Write-Host "Adding DSG DNS records to SHM"
$result = Invoke-AzVMRunCommand -ResourceGroupName $config.shm.dc.rg -Name $config.shm.dc.vmName `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
    -Parameter $params
Write-Host $result.Value[0].Message
Write-Host $result.Value[1].Message

# Switch back to previous subscription
$_ = Set-AzContext -Context $prevContext;

