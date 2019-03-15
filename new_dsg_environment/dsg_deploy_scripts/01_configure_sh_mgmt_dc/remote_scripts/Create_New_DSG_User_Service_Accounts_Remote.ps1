# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in 
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# Fror details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
  $configJson,
  $hackMdPassword,
  $gitlabPassword,
  $dsvmPassword,
  $testResearcherPassword
)

# For some reason, passing a JSON string as the -Parameter value for Invoke-AzVMRunCommand
# results in the double quotes in the JSON string being stripped in transit
# Escaping these with a single backslash retains the double quotes but the transferred
# string is truncated. Escaping these with backticks still results in the double quotes
# being stripped in transit, but we can then replace the backticks with double quotes 
# at this end to recover a valid JSON string.
$config =  ($configJson.Replace("``","`"") | ConvertFrom-Json)
Write-Host $config.shm.domain.securityOuPath
# Create DSG Security Group
New-ADGroup -Name $config.dsg.domain.securityGroups.researchUsers.name -GroupScope Global -Description $config.dsg.domain.securityGroups.researchUsers.description -GroupCategory Security -Path $config.shm.domain.securityOuPath

# ---- Create Service Accounts for DSG ---
# Hack MD user
$hackMdPrincipalName = $config.dsg.users.ldap.hackmd.samAccountName + "@" + $config.dsg.domain.fqdn;
New-ADUser  -Name $config.dsg.users.ldap.hackmd.name `
            -UserPrincipalName $hackMdPrincipalName `
            -Path $config.shm.domain.serviceOuPath `
            -SamAccountName $config.dsg.users.ldap.hackmd.samAccountName `
            -DisplayName $config.dsg.users.ldap.hackmd.name `
            -Description $config.dsg.users.ldap.hackmd.name `
            -AccountPassword $hackMdPassword `
            -Enabled $true `
            -PasswordNeverExpires $true

# Gitlab user
$gitlabPrincipalName = $config.dsg.users.ldap.gitlab.samAccountName + "@" + $config.dsg.domain.fqdn;
New-ADUser  -Name $config.dsg.users.ldap.gitlab.name `
            -UserPrincipalName $gitlabPrincipalName `
            -Path $config.shm.domain.serviceOuPath `
            -SamAccountName $config.dsg.users.ldap.gitlab.samAccountName `
            -DisplayName $config.dsg.users.ldap.gitlab.name `
            -Description $config.dsg.users.ldap.gitlab.name `
            -AccountPassword $gitlabPassword `
            -Enabled $true `
            -PasswordNeverExpires $true

# DSVM user
$dsvmPrincipalName = $config.dsg.users.ldap.dsvm.samAccountName + "@" + $config.dsg.domain.fqdn;
New-ADUser  -Name $config.dsg.users.ldap.dsvm.name `
            -UserPrincipalName $dsvmPrincipalName `
            -Path $config.shm.domain.serviceOuPath `
            -SamAccountName $config.dsg.users.ldap.dsvm.samAccountName `
            -DisplayName $config.dsg.users.ldap.dsvm.name `
            -Description $config.dsg.users.ldap.dsvm.name `
            -AccountPassword $dsvmPassword `
            -Enabled $true `
            -PasswordNeverExpires $true

# Test Research user
$testResearcherPrincipalName = $config.dsg.users.researchers.test.samAccountName + "@" + $config.dsg.domain.fqdn;
New-ADUser  -Name $config.dsg.users.researchers.test.name `
            -UserPrincipalName $testResearcherPrincipalName `
            -Path $config.shm.domain.userOuPath `
            -SamAccountName $config.dsg.users.researchers.test.samAccountName `
            -DisplayName $config.dsg.users.researchers.test.name `
            -Description $config.dsg.users.researchers.test.name `
            -AccountPassword $testResearcherPassword `
            -Enabled $true `
            -PasswordNeverExpires $true

#Add Data Science LDAP users to SG Data Science LDAP Users security group
Add-ADGroupMember $config.shm.domain.securityGroups.dsvmLdapUsers.name $config.dsg.users.ldap.dsvm.samAccountName

#Add DSG test users to the relative Security Groups
Add-ADGroupMember $config.dsg.domain.securityGroups.researchUsers.name $config.dsg.users.ldap.dsvm.samAccountName
