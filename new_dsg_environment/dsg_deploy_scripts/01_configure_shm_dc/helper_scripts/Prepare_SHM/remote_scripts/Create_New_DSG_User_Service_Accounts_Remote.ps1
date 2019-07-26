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
  [string]$hackmdPassword,
  $gitlabSamAccountName,
  $gitlabName,
  [string]$gitlabPassword,
  $dsvmSamAccountName,
  $dsvmName,
  [string]$dsvmPassword,
  $testResearcherSamAccountName,
  $testResearcherName,
  [string]$testResearcherPassword
)

# We should really pass the passwords in as secure strings but we get a conversion error if we do.
# Error: Cannot convert the "System.Security.SecureString" value of type "System.String" to type 
#        "System.Security.SecureString".

function New-DsgUser($samAccountName, $name, $path, $password) {
  if(Get-ADUser -Filter "SamAccountName -eq '$samAccountName'"){
    Write-Output " - User '$samAccountName' already exists"
  } else {
    $principalName = $samAccountName + "@" + $dsgFqdn;
    Write-Output " - Creating user '$name' ($samAccountName)"
    return (New-ADUser -Name $name `
               -UserPrincipalName $principalName `
               -Path $path `
               -SamAccountName $samAccountName `
               -DisplayName $name `
               -Description $name `
               -AccountPassword (ConvertTo-SecureString $password -AsPlainText -Force) `
               -Enabled $true `
               -PasswordNeverExpires $true)
  }
}

function New-DsgGroup($name, $description, $path, $groupCategory, $groupScope) {
  if(Get-ADGroup -Filter "Name -eq '$name'"){
    Write-Output " - Group '$name' already exists"
  } else {
    Write-Output " - Creating group '$name' in OU '$ouPath'"
    return (New-ADGroup -Name $name -Description $description -Path $path -GroupScope $groupScope -GroupCategory Security)
  }
}

# Create DSG Security Group
New-DsgGroup -name $researchUserSgName -description $researchUserSgDescription -Path $securityOuPath -GroupScope Global -GroupCategory Security 

# ---- Create Service Accounts for DSG ---
New-DsgUser -samAccountName $hackmdSamAccountName -name $hackmdName -path $serviceOuPath -password $hackmdPassword 
New-DsgUser -samAccountName $gitlabSamAccountName -name $gitlabName -path $serviceOuPath -password $gitlabPassword 
New-DsgUser -samAccountName $dsvmSamAccountName -name $dsvmName -path $serviceOuPath -password $dsvmPassword 
New-DsgUser -samAccountName $testResearcherSamAccountName -name $testResearcherName -path $researchUserOuPath -password $testResearcherPassword

# Add Data Science LDAP users to SG Data Science LDAP Users security group
Write-Output " - Adding '$dsvmSamAccountName' user to group '$ldapUserSgName'"
Add-ADGroupMember $ldapUserSgName $dsvmSamAccountName

# Add DSG test users to the relative Security Groups
Write-Output " - Adding '$testResearcherSamAccountName' user to group '$researchUserSgName'"
Add-ADGroupMember $researchUserSgName $testResearcherSamAccountName
