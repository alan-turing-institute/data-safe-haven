# NB. This solves the issue of orphaned AAD users when the local AD is deleted
# https://support.microsoft.com/en-gb/help/2619062/you-can-t-manage-or-remove-objects-that-were-synchronized-through-the

# Ensure that MSOnline is installed for current user
if (-not (Get-Module -ListAvailable -Name MSOnline)) {
    Install-Module -Name MSOnline -Scope CurrentUser -Force
}

Write-Host "Please use username admin@$tmplShmFqdn and the $tmplAadPasswordName from $tmplKeyVaultName."
Connect-MsolService
Write-Host "Disabling directory synchronisation..."
Set-MsolDirSyncEnabled -EnableDirSync `$False -Force
Write-Host "Is directory synchronisation currently enabled? `$((Get-MSOLCompanyInformation).DirectorySynchronizationEnabled)"
Write-Host "Removing any connected applications..."
Get-MsolServicePrincipal | Select-Object DisplayName
Get-MsolServicePrincipal | Remove-MsolServicePrincipal