# Here we install
# - NuGet (for module management)
# - PowerShellModule (to allow modules to be installed in DSC)
# - various x* modules (to enable DSC functions)
# Other Powershell modules should be installed through DSC
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force;
Install-Module PowerShellModule -MinimumVersion 0.3 -Force;
Install-Module ActiveDirectoryDsc -MinimumVersion 6.2.0 -Force;
Install-Module ComputerManagementDsc -MinimumVersion 8.5.0 -Force;
Install-Module NetworkingDsc -MinimumVersion 9.0.0 -Force;