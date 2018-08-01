$domain = "DOMAIN" # Active Directory Domain Name
$accountname = "ACCOUNTNAME" # Account used by SQL Server on NPS server
$domainpath = "OU=$domain Service Accounts,DC=$domain,DC=CO,DC=UK"

New-ADUser  -Name "SQL Admin" `
            -UserPrincipalName "$accountname@$domain.co.uk" `
            -Path  $domainpath `
            -SamAccountName  $accountname `
            -DisplayName "SQL Admin User" `
            -Description "User used by SQL server on NPS" `
            -AccountPassword (Read-Host -Prompt "User Password:" -AsSecureString) `
            -Enabled $true `
            -PasswordNeverExpires $true