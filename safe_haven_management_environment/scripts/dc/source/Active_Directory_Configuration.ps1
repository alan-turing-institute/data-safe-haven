# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in 
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# Fror details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
  $configJson,
  [string]$adsyncpassword,
  [string]$oubackuppath
)

# For some reason, passing a JSON string as the -Parameter value for Invoke-AzVMRunCommand
# results in the double quotes in the JSON string being stripped in transit
# Escaping these with a single backslash retains the double quotes but the transferred
# string is truncated. Escaping these with backticks still results in the double quotes
# being stripped in transit, but we can then replace the backticks with double quotes 
# at this end to recover a valid JSON string.
$config =  ($configJson.Replace("``","`"") | ConvertFrom-Json)

#Domain Details
$domainou = $config.domain.dn
$domain = $config.domain.fqdn 


#Enable AD Recycle Bin
Write-Host -ForegroundColor Green "Configuring AD recycle bin..."
Enable-ADOptionalFeature -Identity "Recycle Bin Feature" -Scope ForestOrConfigurationSet -Target $domain -Server shmdc1 -confirm:$false
write-Host -ForegroundColor Cyan "Done!"

#Set ATIAdmin user account password to never expire
Write-Host -ForegroundColor Green "Setting admin account to never expire..."
Set-ADUser -Identity "atiadmin" -PasswordNeverExpires $true
write-Host -ForegroundColor Cyan "Done!"

#Set minumium password age to 0
Write-Host -ForegroundColor Green "Changing minimum password age to 0"
Set-ADDefaultDomainPasswordPolicy -Identity $domain -MinPasswordAge 0.0:0:0.0
write-Host -ForegroundColor Cyan "Done!"

# Create OUs
Write-Host -ForegroundColor Green "Creating management OUs..."
New-ADOrganizationalUnit -Name "Safe Haven Research Users" -Description "Safe Haven Reseach Users"
New-ADOrganizationalUnit -Name "Safe Haven Security Groups" -Description "Safe Haven Security Groups"
New-ADOrganizationalUnit -Name "Safe Haven Service Accounts" -Description "Safe Haven Service Accounts"
New-ADOrganizationalUnit -Name "Safe Haven Service Servers" -Description "Safe Haven Service Servers"
write-Host -ForegroundColor Cyan "OU Created!"

#Create Server administrators group and add atiadmin to group
Write-Host -ForegroundColor Green "Setting up security groups..."
New-ADGroup -Name "SG Safe Haven Server Administrators" -GroupScope Global -Description "SG Safe Haven Server Administrators" -GroupCategory Security -Path "OU=Safe Haven Security Groups,$domainou"
Add-ADGroupMember "SG Safe Haven Server Administrators" "atiadmin"
write-Host -ForegroundColor Cyan "Groups configured!"

#Create DSG Security Groups
Write-Host -ForegroundColor Green "Creating DSG LDAP users group..."
New-ADGroup -Name "SG Data Science LDAP Users" -GroupScope Global -Description "SG Data Science LDAP Users" -GroupCategory Security -Path "OU=Safe Haven Security Groups,$domainou" 
write-Host -ForegroundColor Cyan "Group created!"

#Set account OU Paths
$serviceoupath = "OU=Safe Haven Service Accounts,$domainou"

# #Creating global service accounts
$adsyncaccountname = "localadsync"
write-Host -ForegroundColor Cyan "Creating AD Sync Service account - $adsyncaccountname - enter password for this account when prompted"
New-ADUser  -Name "Local AD Sync Administrator" `
            -UserPrincipalName "$adsyncaccountname@$domain" `
            -Path  $serviceoupath `
            -SamAccountName  $adsyncaccountname `
            -DisplayName "Local AD Sync Administrator" `
            -Description "Azure AD Connect service account" `
            -AccountPassword (ConvertTo-SecureString $adsyncpassword -AsPlainText -Force) `
            -Enabled $true `
            -PasswordNeverExpires $true

Add-ADGroupMember "Enterprise Admins" $adsyncaccountname
write-Host -ForegroundColor Cyan "Users, Groups, OUs etc all created!"

#Import GPOs into Domain
Write-Host -ForegroundColor Green "Importing GPOs..."
Import-GPO -BackupId 0AF343A0-248D-4CA5-B19E-5FA46DAE9F9C -TargetName "All servers – Local Administrators" -Path $oubackuppath -CreateIfNeeded
Import-GPO -BackupId EE9EF278-1F3F-461C-9F7A-97F2B82C04B4 -TargetName "All Servers – Windows Update" -Path $oubackuppath -CreateIfNeeded
Import-GPO -BackupId 742211F9-1482-4D06-A8DE-BA66101933EB -TargetName "All Servers – Windows Services" -Path $oubackuppath -CreateIfNeeded
write-Host -ForegroundColor Cyan "Import complete!"

#Link GPO with OUs
Write-Host -ForegroundColor Green "Linking GPOs..."
Get-GPO -Name "All servers – Local Administrators" | New-GPLink -Target "OU=Safe Haven Service Servers,$domainou" -LinkEnabled Yes
Get-GPO -Name "All Servers – Windows Services" | New-GPLink -Target "OU=Domain Controllers,$domainou" -LinkEnabled Yes
Get-GPO -Name "All Servers – Windows Services" | New-GPLink -Target "OU=Safe Haven Service Servers,$domainou" -LinkEnabled Yes
Get-GPO -Name "All Servers – Windows Update" | New-GPLink -Target  "OU=Domain Controllers,$domainou" -LinkEnabled Yes
Get-GPO -Name "All Servers – Windows Update" | New-GPLink -Target  "OU=Safe Haven Service Servers,$domainou" -LinkEnabled Yes
write-Host -ForegroundColor Cyan "GPO linking complete!"

#Create Reverse Lookup Zones
#SHM
write-host -ForegroundColor Green "Creating reverse lookup zones..."
Add-DnsServerPrimaryZone -DynamicUpdate Secure -NetworkId "10.251.0.0/24" -ReplicationScope Domain
Add-DnsServerPrimaryZone -DynamicUpdate Secure -NetworkId "10.251.1.0/24" -ReplicationScope Domain
write-Host -ForegroundColor Cyan "Reverse zones created!"