$domain = "DOMAIN" # Active Directory Domain Name
$accountname = "ACCOUNTNAME" # Domain account used to sync AD with AAD
$domainpath = "OU=$domain Service Accounts,DC=$domain,DC=CO,DC=UK"

New-ADUser  -Name "Local AD Sync Administrator" `
            -UserPrincipalName "$accountname@$domain.co.uk" `
            -Path  $domainpath `
            -SamAccountName  $accountname `
            -DisplayName "Local AD Sync Administrator" `
            -Description "User used by Azure AD Connect" `
            -AccountPassword (Read-Host -Prompt "User Password:" -AsSecureString) `
            -Enabled $true `
            -PasswordNeverExpires $true

Add-ADGroupMember "Enterprise Admins" $accountname
