# NB. This solves the issue of orphaned AAD users when the local AD is deleted
# https://support.microsoft.com/en-gb/help/2619062/you-can-t-manage-or-remove-objects-that-were-synchronized-through-the

# Ensure that MSOnline is installed for current user
if (-Not (Get-Module -ListAvailable -Name MSOnline)) {
    Install-Module -Name MSOnline -Force
}

Write-Host "Please use username admin@$tmplShmFqdn and the $tmplAadPasswordName from $tmplKeyVaultName."
Connect-MsolService
Write-Host "Disabling directory synchronisation..."
Set-MsolDirSyncEnabled -EnableDirSync `$False -Force
Write-Host "Is directory synchronisation currently enabled? `$((Get-MSOLCompanyInformation).DirectorySynchronizationEnabled)"
# Remove user-added service principals except the MFA service principal
Write-Host "Removing any connected applications..."
Get-MsolServicePrincipal | Where-Object { `$_.AppPrincipalId -ne "981f26a1-7f43-403b-a875-f8b09b8cd720" } | Remove-MsolServicePrincipal 2> Out-Null
Write-Host "Finished"
