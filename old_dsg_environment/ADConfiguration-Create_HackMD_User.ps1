$domain = "DOMAIN" # Active Directory Domain Name
$accountname = "ACCOUNTNAME" # Account used by HackMD for LDAP lookup
$domainpath = "OU=$domain Service Accounts,DC=$domain,DC=CO,DC=UK"  #Update OU path for both OU and DC"

New-ADUser  -Name "HackMD LDAP" `
            -UserPrincipalName "$accountname@$domain.co.uk" `
            -Path  $domainpath `
            -SamAccountName  $accountname `
            -DisplayName "HackMD LDAP User" `
            -Description "User used by HackMD for LDAP lookup" `
            -AccountPassword (Read-Host -Prompt "User Password:" -AsSecureString) `
            -Enabled $true `
            -PasswordNeverExpires $true