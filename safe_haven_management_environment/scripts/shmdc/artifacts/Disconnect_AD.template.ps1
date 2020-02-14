# NB. This solves the issue of orphaned AAD users when the local AD is deleted
# https://support.microsoft.com/en-gb/help/2619062/you-can-t-manage-or-remove-objects-that-were-synchronized-through-the
Write-Host "Please use username admin@$tmplShmFqdn and the $tmplAadPasswordName from $tmplKeyVaultName."
Connect-MsolService
Write-Host "Disabling directory synchronisation..."
Set-MsolDirSyncEnabled -EnableDirSync `$False -Force
Write-Host "Is directory synchronisation currently enabled? $((Get-MSOLCompanyInformation).DirectorySynchronizationEnabled)"