$domain = "DOMAIN" # Active Directory Domain Name
$accountname = "ACCOUNTNAME" # User create for GitLab to use LDAP against AD
$domainpath = "OU=$domain Service Accounts,DC=$domain,DC=CO,DC=UK"

New-ADUser  -Name "GITLAB LDAP" `
            -UserPrincipalName "$accountname@$domain.co.uk" `
            -Path  $domainpath `
            -SamAccountName  $accountname `
            -DisplayName "GitLab LDAP User" `
            -Description "User used by GitLab for LDAP lookup" `
            -AccountPassword (Read-Host -Prompt "User Password:" -AsSecureString) `
            -Enabled $true `
            -PasswordNeverExpires $true