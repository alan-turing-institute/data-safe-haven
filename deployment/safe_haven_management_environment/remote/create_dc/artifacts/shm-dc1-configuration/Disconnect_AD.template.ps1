# NB. This solves the issue of orphaned AAD users when the local AD is deleted
# https://support.microsoft.com/en-gb/help/2619062/you-can-t-manage-or-remove-objects-that-were-synchronized-through-the

# Ensure that MSOnline is installed for current user
if (-Not (Get-Module -ListAvailable -Name MSOnline)) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Install-Module -Name MSOnline -Force
}

if (Get-Module -ListAvailable -Name MSOnline) {
    Write-Output "Please use the username and password for an Azure AD global admin. Don't forget the @<shm-fqdn> on the end of the username!"
    Connect-MsolService
    # Disable synchronisation if it is currently enabled
    if ((Get-MSOLCompanyInformation).DirectorySynchronizationEnabled) {
        Write-Output "Disabling directory synchronisation..."
        Set-MsolDirSyncEnabled -EnableDirSync $False -Force
    }
    # Print the current synchronisation status
    if ((Get-MSOLCompanyInformation).DirectorySynchronizationEnabled) {
        Write-Output "[x] Directory synchronisation is currently ENABLED"
    } else {
        Write-Output "[o] Directory synchronisation is currently DISABLED"
    }
    # Remove user-added service principals except the MFA service principal
    Write-Output "Removing any user-added service principals..."
    Get-MsolServicePrincipal | Where-Object { $_.AppPrincipalId -ne "981f26a1-7f43-403b-a875-f8b09b8cd720" } | Remove-MsolServicePrincipal 2>&1 | Out-Null
    $nServicePrincipals = (Get-MsolServicePrincipal | Where-Object { $_.AppPrincipalId -ne "981f26a1-7f43-403b-a875-f8b09b8cd720" } | Measure-Object).Count
    if ((Get-MsolServicePrincipal | Where-Object { $_.AppPrincipalId -ne "981f26a1-7f43-403b-a875-f8b09b8cd720" } | Measure-Object).Count -le 1) {
        Write-Output "[o] There are $nServicePrincipals service principal(s) remaining"
    } else {
        Write-Output "[x] There are $nServicePrincipals service principals remaining"
    }
}
