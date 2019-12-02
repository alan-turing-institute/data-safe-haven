$domain = "DOMAIN" # Active Directory Domain Name
$accountname = "ACCOUNTNAME" # Test account used for testing the environment
$domainpath = "OU=$domain Research Users,DC=$domain,DC=CO,DC=UK"

New-ADUser  -Name "Test User" `
            -UserPrincipalName "$accountname@$domain.co.uk" `
            -Path  $domainpath `
            -SamAccountName  "testuser" `
            -DisplayName "Test User" `
            -Description "Testing User" `
            -AccountPassword (Read-Host -Prompt "User Password:" -AsSecureString) `
            -Enabled $true `
            -PasswordNeverExpires $true