# Param(
#   [Parameter(Mandatory = $true, HelpMessage="Data Study Group name i.e DSG1")]
#   [ValidateNotNullOrEmpty()]
#   [string]$dsg,
#   [Parameter(Mandatory = $true, HelpMessage="Data Study Group name i.e DSG1")]
#   [ValidateNotNullOrEmpty()]
#   [string]$dsg,
#   [Parameter(Mandatory = $true, HelpMessage="Data Study Group name i.e DSG1")]
#   [ValidateNotNullOrEmpty()]
#   [string]$dsg
# )

# #Set account OU Paths
# $serviceoupath = "OU=Safe Haven Service Accounts,DC=TURINGSAFEHAVEN,DC=AC,DC=UK"
# $usersoupath = "OU=Safe Haven Research Users,DC=turingsafehaven,DC=ac,DC=uk"

# #Create DSG Security Groups
# New-ADGroup -Name "SG $dsg Research Users" -GroupScope Global -Description "SG $dsg Research Users" -GroupCategory Security -Path "OU=Safe Haven Security Groups,DC=turingsafehaven,DC=ac,DC=uk"


# #Create Service Accounts for DSG
# Write-host "Creating Service Accounts for $dsg"
# $dsghackmdaccountname = ($dsg+"hackmdldap")
# Write-Host "Creating $dsghackmdaccountname account, enter password for this account when prompted"
# New-ADUser  -Name "$dsg HackMD LDAP" `
#             -UserPrincipalName "$dsghackmdaccountname@TURINGSAFEHAVEN.ac.uk" `
#             -Path  $serviceoupath `
#             -SamAccountName  $dsghackmdaccountname `
#             -DisplayName "$dsg HackMD LDAP User" `
#             -Description "$dsg HackMD service account for LDAP lookup" `
#             -AccountPassword (Read-Host -Prompt "User Password:" -AsSecureString) `
#             -Enabled $true `
#             -PasswordNeverExpires $true

# $dsgdsgpuaccountname = ($dsg+"dsgpuldap")
# Write-Host "Creating $dsgdsgpuaccountname account, enter password for this account when prompted"
# New-ADUser  -Name "$dsg Data Science LDAP" `
#             -UserPrincipalName "$dsgdsgpuaccountname@TURINGSAFEHAVEN.ac.uk" `
#             -Path  $serviceoupath `
#             -SamAccountName  $dsgdsgpuaccountname `
#             -DisplayName "$dsg Data Science LDAP User" `
#             -Description "$dsg Data Science server service account for LDAP lookup" `
#             -AccountPassword (Read-Host -Prompt "User Password:" -AsSecureString) `
#             -Enabled $true `
#             -PasswordNeverExpires $true

# $dsggitaccountname = ($dsg+"gitlabldap")
# Write-Host "Creating $dsggitaccountname account, enter password for this account when prompted"
# New-ADUser  -Name "$dsg GITLAB LDAP" `
#             -UserPrincipalName "$dsggitaccountname@TURINGSAFEHAVEN.ac.uk" `
#             -Path  $serviceoupath `
#             -SamAccountName  $dsggitaccountname `
#             -DisplayName "$dsg GitLab LDAP User" `
#             -Description "$dsg GitLab service account for LDAP lookup" `
#             -AccountPassword (Read-Host -Prompt "User Password:" -AsSecureString) `
#             -Enabled $true `
#             -PasswordNeverExpires $true

# $dsgtestaccountname = ($dsg+"testuser")
# Write-Host "Creating $dsgtestaccountname account, enter password for this account when prompted"
# New-ADUser  -Name "$dsg Test User" `
#             -UserPrincipalName "$dsgtestaccountname@TURINGSAFEHAVEN.ac.uk" `
#             -Path  $usersoupath `
#             -SamAccountName  $dsgtestaccountname `
#             -DisplayName "$dsg Test User" `
#             -Description "$dsg Test User" `
#             -AccountPassword (Read-Host -Prompt "User Password:" -AsSecureString) `
#             -Enabled $true `
#             -PasswordNeverExpires $true

# #Add Data Science LDAP users to SG Data Science LDAP Users security group
# Add-ADGroupMember "SG Data Science LDAP Users" $dsgdsgpuaccountname

# #Add DSG test users to the relative Security Groups
# Add-ADGroupMember "SG $dsg Research Users" "$dsgtestaccountname"

# Write-Host "Users, Groups, OUs etc all created!"