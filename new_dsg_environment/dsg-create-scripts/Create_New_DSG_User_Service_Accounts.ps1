Param(
  [Parameter(Mandatory = $true, 
             HelpMessage="Data Study Group name i.e DSG1")]
  [ValidateNotNullOrEmpty()]
  [string]$dsg
)

#Set account OU Paths
$serviceoupath = "OU=Safe Haven Service Accounts,DC=DSGROUPDEV,DC=co,DC=uk"
$usersoupath = "OU=Safe Haven Research Users,DC=DSGROUPDEV,DC=co,DC=uk"

#Create DSG Security Groups
New-ADGroup -Name "SG $dsg Research Users" -GroupScope Global -Description "SG $dsg Research Users" -GroupCategory Security -Path "OU=Safe Haven Security Groups,DC=dsgroupdev,DC=co,DC=uk"

#Create Service Accounts for DSG
write-host -ForegroundColor Green "Creating Service Accounts for $dsg"
$dsghackmdaccountname = ($dsg+"hackmdldap")
write-Host -ForegroundColor Cyan "Creating $dsghackmdaccountname account, enter password for this account when prompted"
New-ADUser  -Name "$dsg HackMD LDAP" `
            -UserPrincipalName "$dsghackmdaccountname@DSGROUPDEV.co.uk" `
            -Path  $serviceoupath `
            -SamAccountName  $dsghackmdaccountname `
            -DisplayName "$dsg HackMD LDAP User" `
            -Description "$dsg HackMD service account for LDAP lookup" `
            -AccountPassword (Read-Host -Prompt "User Password:" -AsSecureString) `
            -Enabled $true `
            -PasswordNeverExpires $true

$dsgdsgpuaccountname = ($dsg+"dsgpuldap")
write-Host -ForegroundColor Cyan "Creating $dsgdsgpuaccountname account, enter password for this account when prompted"
New-ADUser  -Name "$dsg Data Science LDAP" `
            -UserPrincipalName "$dsgdsgpuaccountname@DSGROUPDEV.co.uk" `
            -Path  $serviceoupath `
            -SamAccountName  $dsgdsgpuaccountname `
            -DisplayName "$dsg Data Science LDAP User" `
            -Description "$dsg Data Science server service account for LDAP lookup" `
            -AccountPassword (Read-Host -Prompt "User Password:" -AsSecureString) `
            -Enabled $true `
            -PasswordNeverExpires $true

$dsggitaccountname = ($dsg+"gitlabldap")
write-Host -ForegroundColor Cyan "Creating $dsggitaccountname account, enter password for this account when prompted"
New-ADUser  -Name "$dsg GITLAB LDAP" `
            -UserPrincipalName "$dsggitaccountname@DSGROUPDEV.co.uk" `
            -Path  $serviceoupath `
            -SamAccountName  $dsggitaccountname `
            -DisplayName "$dsg GitLab LDAP User" `
            -Description "$dsg GitLab service account for LDAP lookup" `
            -AccountPassword (Read-Host -Prompt "User Password:" -AsSecureString) `
            -Enabled $true `
            -PasswordNeverExpires $true

$dsgtestaccountname = ($dsg+"testuser")
write-Host -ForegroundColor Cyan "Creating $dsgtestaccountname account, enter password for this account when prompted"
New-ADUser  -Name "$dsg Test User" `
            -UserPrincipalName "$dsgtestaccountname@DSGROUPDEV.co.uk" `
            -Path  $usersoupath `
            -SamAccountName  $dsgtestaccountname `
            -DisplayName "$dsg Test User" `
            -Description "$dsg Test User" `
            -AccountPassword (Read-Host -Prompt "User Password:" -AsSecureString) `
            -Enabled $true `
            -PasswordNeverExpires $true

#Add Data Science LDAP users to SG Data Science LDAP Users security group
Add-ADGroupMember "SG Data Science LDAP Users" $dsgdsgpuaccountname

#Add DSG test users to the relative Security Groups
Add-ADGroupMember "SG $dsg Research Users" "$dsgtestaccountname" 

write-Host -ForegroundColor Cyan "Users, Groups, OUs etc all created!"