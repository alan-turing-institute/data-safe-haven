# NB. This solves the issue of orphaned AAD users when the local AD is deleted
# https://support.microsoft.com/en-gb/help/2619062/you-can-t-manage-or-remove-objects-that-were-synchronized-through-the

# Ensure that MSOnline is installed for current user
if (-not (Get-Module -ListAvailable -Name MSOnline)) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Install-Module -Name MSOnline -Force
}

if (Get-Module -ListAvailable -Name MSOnline) {
    Write-Output "INFO: Please use the username and password for an Azure AD global admin."
    Connect-MsolService
    # Print the current synchronisation status
    if ((Get-MSOLCompanyInformation).DirectorySynchronizationEnabled) {
        Write-Output "INFO: Directory synchronisation is ENABLED"
        Write-Output "INFO: Removing synchronised users..."
        Get-MsolUser -Synchronized | Remove-MsolUser -Force
        Write-Output "INFO: Disabling directory synchronisation..."
        Set-MsolDirSyncEnabled -EnableDirSync $False -Force
        # Print the current synchronisation status
        if ((Get-MSOLCompanyInformation).DirectorySynchronizationEnabled) {
            Write-Output "ERROR: Directory synchronisation is still ENABLED"
        } else {
            Write-Output "INFO: Directory synchronisation is now DISABLED"
        }
    } else {
        Write-Output "WARNING: Directory synchronisation is already DISABLED"
    }
    # Remove user-added service principals except the MFA service principal
    Write-Output "INFO: Removing any user-added service principals..."
    $nServicePrincipalsBefore = (Get-MsolServicePrincipal | Measure-Object).Count
    Get-MsolServicePrincipal | Where-Object { $_.AppPrincipalId -ne "981f26a1-7f43-403b-a875-f8b09b8cd720" } | Remove-MsolServicePrincipal 2>&1 | Out-Null
    $nServicePrincipalsAfter = (Get-MsolServicePrincipal | Measure-Object).Count
    Write-Output "INFO: Removed $($nServicePrincipalsBefore - $nServicePrincipalsAfter) service principal(s). There are $nServicePrincipalsAfter remaining"
}
