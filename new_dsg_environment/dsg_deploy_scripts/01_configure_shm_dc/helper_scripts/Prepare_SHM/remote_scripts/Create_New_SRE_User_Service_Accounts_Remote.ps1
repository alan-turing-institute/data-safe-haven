# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# Fror details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
  $dsgFqdn,
  $researchUserSgName,
  $researchUserSgDescription,
  $ldapUserSgName,
  $securityOuPath,
  $serviceOuPath,
  $researchUserOuPath,
  $hackmdSamAccountName,
  $hackmdName,
  $hackmdPasswordEncrypted,
  $gitlabSamAccountName,
  $gitlabName,
  $gitlabPasswordEncrypted,
  $dsvmSamAccountName,
  $dsvmName,
  $dsvmPasswordEncrypted,
  $testResearcherSamAccountName,
  $testResearcherName,
  $testResearcherPasswordEncrypted
)

function New-DsgGroup($name, $description, $path, $groupCategory, $groupScope) {
  if(Get-ADGroup -Filter "Name -eq '$name'"){
    Write-Output " - Group '$name' already exists"
  } else {
    Write-Output " - Creating group '$name' in OU '$serviceOuPath'"
    return (New-ADGroup -Name "$name" -Description $description -Path $path -GroupScope $groupScope -GroupCategory Security)
  }
}

function New-DsgUser($samAccountName, $name, $path, $passwordSecureString) {
  if(Get-ADUser -Filter "SamAccountName -eq '$samAccountName'"){
    Write-Output " - User '$samAccountName' already exists"
  } else {
    $principalName = $samAccountName + "@" + $dsgFqdn;
    Write-Output " - Creating user '$name' ($samAccountName)"
    Write-Host "-Name: $name"
    Write-Host "-UserPrincipalName: $principalName"
    Write-Host "-Path: $path"
    Write-Host "-SamAccountName: $samAccountName"
    Write-Host "-DisplayName: $name"
    Write-Host "-Description: $name"
    Write-Host "-AccountPassword: $password"
    return (New-ADUser -Name "$name" `
               -UserPrincipalName $principalName `
               -Path $path `
               -SamAccountName $samAccountName `
               -DisplayName "$name" `
               -Description "$name" `
               -AccountPassword $passwordSecureString `
               -Enabled $true `
               -PasswordNeverExpires $true)
  }
}

# Convert encrypted string to secure string
$hackmdPasswordSecureString = ConvertTo-SecureString -String $hackmdPasswordEncrypted -Key (1..16)
$gitlabPasswordSecureString = ConvertTo-SecureString -String $gitlabPasswordEncrypted -Key (1..16)
$dsvmPasswordSecureString = ConvertTo-SecureString -String $dsvmPasswordEncrypted -Key (1..16)
$testResearcherPasswordSecureString = ConvertTo-SecureString -String $testResearcherPasswordEncrypted -Key (1..16)

# Create DSG Security Group
New-DsgGroup -name $researchUserSgName -description $researchUserSgDescription -Path $securityOuPath -GroupScope Global -GroupCategory Security

# ---- Create Service Accounts for DSG ---
New-DsgUser -samAccountName $hackmdSamAccountName -name $hackmdName -path $serviceOuPath -passwordSecureString $hackmdPasswordSecureString
New-DsgUser -samAccountName $gitlabSamAccountName -name $gitlabName -path $serviceOuPath -passwordSecureString $gitlabPasswordSecureString
New-DsgUser -samAccountName $dsvmSamAccountName -name $dsvmName -path $serviceOuPath -passwordSecureString $dsvmPasswordSecureString
New-DsgUser -samAccountName $testResearcherSamAccountName -name $testResearcherName -path $researchUserOuPath -passwordSecureString $testResearcherPasswordSecureString

# Add Data Science LDAP users to SG Data Science LDAP Users security group
Write-Output " - Adding '$dsvmSamAccountName' user to group '$ldapUserSgName'"
Add-ADGroupMember "$ldapUserSgName" "$dsvmSamAccountName"

# Add DSG test users to the relative Security Groups
Write-Output " - Adding '$testResearcherSamAccountName' user to group '$researchUserSgName'"
Add-ADGroupMember "$researchUserSgName" "$testResearcherSamAccountName"
