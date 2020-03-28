Import-Module MSOnline
Connect-MsolService
New-MsolServicePrincipal -AppPrincipalId 981f26a1-7f43-403b-a875-f8b09b8cd720 -DisplayName "Azure Multi-Factor Auth Client"
