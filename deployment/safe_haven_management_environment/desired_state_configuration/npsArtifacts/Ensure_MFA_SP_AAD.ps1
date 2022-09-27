Import-Module MSOnline -ErrorAction Stop
Connect-MsolService
New-MsolServicePrincipal -AppPrincipalId 981f26a1-7f43-403b-a875-f8b09b8cd720 -DisplayName "Azure Multi-Factor Auth Client"
New-MsolServicePrincipal -AppPrincipalId 1f5530b3-261a-47a9-b357-ded261e17918 -DisplayName "Azure Multi-Factor Auth Connector"
