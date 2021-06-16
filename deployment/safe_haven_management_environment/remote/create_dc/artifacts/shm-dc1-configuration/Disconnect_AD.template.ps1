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
    # Print the current synchronisation status
    if ((Get-MSOLCompanyInformation).DirectorySynchronizationEnabled) {
        Write-Output "[ ] Directory synchronisation is ENABLED"
        Write-Output "Disabling directory synchronisation..."
        Set-MsolDirSyncEnabled -EnableDirSync $False -Force
        # Print the current synchronisation status
        if ((Get-MSOLCompanyInformation).DirectorySynchronizationEnabled) {
            Write-Output "[x] Directory synchronisation is still ENABLED"
        } else {
            Write-Output "[o] Directory synchronisation is now DISABLED"
        }
    } else {
        Write-Output "[o] Directory synchronisation is already DISABLED"
    }
    # Remove user-added service principals except the MFA service principal
    Write-Output "Removing any user-added service principals..."
    $nServicePrincipalsBefore = (Get-MsolServicePrincipal | Measure-Object).Count
    Get-MsolServicePrincipal | Where-Object { $_.AppPrincipalId -ne "981f26a1-7f43-403b-a875-f8b09b8cd720" } | Remove-MsolServicePrincipal 2>&1 | Out-Null
    $nServicePrincipalsAfter = (Get-MsolServicePrincipal | Measure-Object).Count
    Write-Output "[o] Removed $($nServicePrincipalsBefore - $nServicePrincipalsAfter) service principal(s). There are $nServicePrincipalsAfter remaining"
}
