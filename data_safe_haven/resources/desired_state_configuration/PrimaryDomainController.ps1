Configuration InstallDscModules {
    # Here we install
    # - PowerShellModule (to allow modules to be installed in DSC)
    # - Various *Dsc modules (to enable DSC functions)
    # Other Powershell modules should be installed in InstallPowershellModules

    $RequiredModules = @{
        ActiveDirectoryDsc = "6.2.0"
        ComputerManagementDsc = "8.5.0"
        DnsServerDsc = "3.0.0"
        NetworkingDsc = "9.0.0"
        PowerShellModule = "0.3"
    }

    Script InstallModules {
        SetScript = {
            try {
                foreach ($ModuleDetails in ($using:RequiredModules).GetEnumerator()) {
                    Write-Verbose -Verbose "$($ModuleDetails.Name) -> $($ModuleDetails.Value)"
                    Write-Verbose -Verbose "Installing module: $($ModuleDetails.Name) [$($ModuleDetails.Value)]"
                    Install-Module $ModuleDetails.Name -MinimumVersion $ModuleDetails.Value -Force
                    if ($?) {
                        Write-Verbose -Verbose "Successfully installed module '$($ModuleDetails.Name)'"
                    } else {
                        throw "Failed to install module '$($ModuleDetails.Name) '!"
                    }
                }
            } catch {
                Write-Error "InstallModules: $($_.Exception)"
            }
        }
        GetScript = { @{} }
        TestScript = {
            return $false
        }
    }
}


Configuration PrimaryDomainController {
    Node localhost {
        InstallDscModules InstallDscModules {}

        InstallPowershellModules InstallPowershellModules {}
    }
}