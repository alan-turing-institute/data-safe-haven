configuration InstallPowershellModulesDC1 {
    Import-DscResource -ModuleName PowerShellModule

    Node localhost {
        PSModuleResource MSOnline {
            Ensure          = "present"
            Module_Name     = "MSOnline"
        }

        PSModuleResource PackageManagement {
            Ensure          = "present"
            Module_Name     = "PackageManagement"
        }

        PSModuleResource PowerShellGet {
            Ensure          = "present"
            Module_Name     = "PowerShellGet"
        }

        PSModuleResource PSWindowsUpdate {
            Ensure          = "present"
            Module_Name     = "PSWindowsUpdate"
        }

        PSModuleResource xActiveDirectory {
            Ensure          = "present"
            Module_Name     = "xActiveDirectory"
            RequiredVersion = "3.0.0.0"
        }

        PSModuleResource xNetworking {
            Ensure          = "present"
            Module_Name     = "xNetworking"
            RequiredVersion = "5.7.0.0"
        }

        PSModuleResource xPendingReboot {
            Ensure          = "present"
            Module_Name     = "xPendingReboot"
            RequiredVersion = "0.4.0.0"
        }

        PSModuleResource xStorage {
            Ensure          = "present"
            Module_Name     = "xStorage"
            RequiredVersion = "3.4.0.0"
        }
    }
}
