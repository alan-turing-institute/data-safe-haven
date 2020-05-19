# NB. This solves the issue of orphaned AAD users when the local AD is deleted
# https://support.microsoft.com/en-gb/help/2619062/you-can-t-manage-or-remove-objects-that-were-synchronized-through-the

# Ensure that MSOnline is installed for current user
if (-Not (Get-Module -ListAvailable -Name MSOnline)) {
    Install-Module -Name MSOnline -Force
}

Write-Output "Please use username admin@<shm-fqdn> and the <aad-admin-password-name> from <shm-keyvault-name>."
Connect-MsolService
Write-Output "Is directory synchronisation currently enabled? $((Get-MSOLCompanyInformation).DirectorySynchronizationEnabled)"
Write-Output "Disabling directory synchronisation..."
Set-MsolDirSyncEnabled -EnableDirSync $False -Force
Write-Output "Is directory synchronisation currently enabled? $((Get-MSOLCompanyInformation).DirectorySynchronizationEnabled)"
# Remove user-added service principals except the MFA service principal
Write-Output "Removing any user-added service principals..."
Get-MsolServicePrincipal | Where-Object { $_.AppPrincipalId -ne "981f26a1-7f43-403b-a875-f8b09b8cd720" } | Remove-MsolServicePrincipal 2>&1 | Out-Null
Write-Output "Finished"
