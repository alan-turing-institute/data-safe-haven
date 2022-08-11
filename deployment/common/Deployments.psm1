Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Compute -ErrorAction Stop
Import-Module Az.Dns -ErrorAction Stop
Import-Module Az.KeyVault -ErrorAction Stop
Import-Module Az.Network -ErrorAction Stop
Import-Module Az.OperationalInsights -ErrorAction Stop
Import-Module Az.Resources -ErrorAction Stop
Import-Module Az.Storage -ErrorAction Stop
Import-Module $PSScriptRoot/AzureCompute -ErrorAction Stop
Import-Module $PSScriptRoot/AzureNetwork -ErrorAction Stop
Import-Module $PSScriptRoot/DataStructures -ErrorAction Stop
Import-Module $PSScriptRoot/Logging -ErrorAction Stop


# Get image definition from the type specified in the config file
# ---------------------------------------------------------------
function Get-ImageDefinition {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Type of image to retrieve the definition for")]
        [string]$Type
    )
    Add-LogMessage -Level Info "[ ] Getting image type from gallery..."
    if ($Type -eq "Ubuntu") {
        $imageDefinition = "SecureResearchDesktop-Ubuntu"
    } else {
        Add-LogMessage -Level Fatal "Failed to interpret $Type as an image type!"
    }
    Add-LogMessage -Level Success "Interpreted $Type as image type $imageDefinition"
    return $imageDefinition
}
Export-ModuleMember -Function Get-ImageDefinition


# Run remote shell script
# -----------------------
function Invoke-RemoteScript {
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "ByPath", HelpMessage = "Path to local script that will be run remotely")]
        [string]$ScriptPath,
        [Parameter(Mandatory = $true, ParameterSetName = "ByString", HelpMessage = "Contents of script that will be run remotely")]
        [string]$Script,
        [Parameter(Mandatory = $true, HelpMessage = "Name of VM to run on")]
        [string]$VMName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group VM belongs to")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $false, HelpMessage = "Type of script to run")]
        [ValidateSet("PowerShell", "UnixShell")]
        [string]$Shell = "PowerShell",
        [Parameter(Mandatory = $false, HelpMessage = "Suppress script output on success")]
        [switch]$SuppressOutput,
        [Parameter(Mandatory = $false, HelpMessage = "(Optional) hashtable of script parameters")]
        [System.Collections.IDictionary]$Parameter = $null
    )
    # If we're given a script then create a file from it
    $tmpScriptFile = $null
    if ($Script) {
        $tmpScriptFile = New-TemporaryFile
        $Script | Out-File -FilePath $tmpScriptFile.FullName
        $ScriptPath = $tmpScriptFile.FullName
    }
    # Validate any external parameters as non-string arguments or arguments containing special characters will cause Invoke-AzVMRunCommand to fail
    $params = @{}
    if ($Parameter) { $params["Parameter"] = $Parameter }
    $params["CommandId"] = ($Shell -eq "PowerShell") ? "RunPowerShellScript" : "RunShellScript"
    if ($params.Contains("Parameter")) {
        foreach ($kv in $params["Parameter"].GetEnumerator()) {
            if ($kv.Value -isnot [string]) {
                Add-LogMessage -Level Fatal "$($kv.Key) argument ($($kv.Value)) must be a string!"
            }
            foreach ($unsafeCharacter in @("|", "&")) {
                if ($kv.Value.Contains($unsafeCharacter)) {
                    Add-LogMessage -Level Fatal "$($kv.Key) argument ($($kv.Value)) contains '$unsafeCharacter' which will cause Invoke-AzVMRunCommand to fail. Consider encoding this variable in Base-64."
                }
            }
            foreach ($whitespaceCharacter in @(" ", "`t")) {
                if (($Shell -eq "UnixShell") -and ($kv.Value.Contains($whitespaceCharacter))) {
                    if (-not (($kv.Value[0] -eq "'") -or ($kv.Value[0] -eq '"'))) {
                        Write-Information -InformationAction "Continue" $kv.Value[0]
                        Add-LogMessage -Level Fatal "$($kv.Key) argument ($($kv.Value)) contains '$whitespaceCharacter' which will cause the shell script to fail. Consider wrapping this variable in single quotes."
                    }
                }
            }
        }
    }
    try {
        # Catch failures from running two commands in close proximity and rerun
        while ($true) {
            try {
                $result = Invoke-AzVMRunCommand -Name $VMName -ResourceGroupName $ResourceGroupName -ScriptPath $ScriptPath @params -ErrorAction Stop
                $success = $?
                break
            } catch [Microsoft.Azure.Commands.Compute.Common.ComputeCloudException] {
               if (-not ($_.Exception.Message -match "Run command extension execution is in progress")) { throw }
            }
        }
    } catch {
        Add-LogMessage -Level Fatal "Running '$ScriptPath' on remote VM '$VMName' failed." -Exception $_.Exception
    }
    $success = $success -and ($result.Status -eq "Succeeded")
    foreach ($outputStream in $result.Value) {
        # Check for 'ComponentStatus/<stream name>/succeeded' as a signal of success
        $success = $success -and (($outputStream.Code -split "/")[-1] -eq "succeeded")
        # Check for ' [x] ' in the output stream as a signal of failure
        if ($outputStream.Message -ne "") {
            $success = $success -and ([string]($outputStream.Message) -NotLike '* `[x`] *')
        }
    }
    # Clean up any temporary scripts
    if ($tmpScriptFile) { Remove-Item $tmpScriptFile.FullName }
    # Check for success or failure
    if ($success) {
        Add-LogMessage -Level Success "Remote script execution succeeded"
        if (-not $SuppressOutput) { Write-Information -InformationAction "Continue" ($result.Value | Out-String) }
    } else {
        Add-LogMessage -Level Info "Script output:"
        Write-Information -InformationAction "Continue" ($result | Out-String)
        Add-LogMessage -Level Fatal "Remote script execution has failed. Please check the output above before re-running this script."
    }
    return $result
}
Export-ModuleMember -Function Invoke-RemoteScript


# Update and reboot a machine
# ---------------------------
function Invoke-WindowsConfiguration {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of VM to run on")]
        [string]$VMName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Time zone to use")]
        [string]$TimeZone,
        [Parameter(Mandatory = $true, HelpMessage = "NTP server to use")]
        [string]$NtpServer,
        [Parameter(Mandatory = $false, HelpMessage = "Additional Powershell modules")]
        [string[]]$AdditionalPowershellModules = @()
    )
    # Install core Powershell modules
    Add-LogMessage -Level Info "[ ] Installing core Powershell modules on '$VMName'"
    $corePowershellScriptPath = Join-Path $PSScriptRoot "remote" "Install_Core_Powershell_Modules.ps1"
    $null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $corePowershellScriptPath -VMName $VMName -ResourceGroupName $ResourceGroupName
    # Install additional Powershell modules
    if ($AdditionalPowershellModules) {
        Add-LogMessage -Level Info "[ ] Installing additional Powershell modules on '$VMName'"
        $additionalPowershellScriptPath = Join-Path $PSScriptRoot "remote" "Install_Additional_Powershell_Modules.ps1"
        $null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $additionalPowershellScriptPath -VMName $VMName -ResourceGroupName $ResourceGroupName -Parameter @{"ModuleNamesB64" = ($AdditionalPowershellModules | ConvertTo-Json -Depth 99 | ConvertTo-Base64) }
    }
    # Set locale and run update script
    Add-LogMessage -Level Info "[ ] Setting time/locale and installing updates on '$VMName'"
    $InstallationScriptPath = Join-Path $PSScriptRoot "remote" "Configure_Windows.ps1"
    $null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $InstallationScriptPath -VMName $VMName -ResourceGroupName $ResourceGroupName -Parameter @{"TimeZone" = "$TimeZone"; "NTPServer" = "$NtpServer"; "Locale" = "en-GB" }
    # Reboot the VM
    Start-VM -Name $VMName -ResourceGroupName $ResourceGroupName -ForceRestart
}
Export-ModuleMember -Function Invoke-WindowsConfiguration


# Update LDAP secret in the local Active Directory
# ------------------------------------------------
function Update-AdLdapSecret {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of DC that holds the local Active Directory")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Resource group for DC that holds the local Active Directory")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Subscription name for DC that holds the local Active Directory")]
        [string]$SubscriptionName,
        [Parameter(Mandatory = $true, HelpMessage = "Password for LDAP search account")]
        [string]$LdapSearchPassword,
        [Parameter(Mandatory = $true, HelpMessage = "SAM account name for LDAP search account")]
        [string]$LdapSearchSamAccountName
    )
    # Get original subscription
    $originalContext = Get-AzContext
    try {
        $null = Set-AzContext -SubscriptionId $SubscriptionName -ErrorAction Stop
        Add-LogMessage -Level Info "[ ] Setting LDAP secret in local AD (${Name})"
        $params = @{
            ldapSearchSamAccountName = $LdapSearchSamAccountName
            ldapSearchPasswordB64    = $LdapSearchPassword | ConvertTo-Base64
        }
        $scriptPath = Join-Path $PSScriptRoot "remote" "ResetLdapPasswordOnAD.ps1"
        $null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $Name -ResourceGroupName $ResourceGroupName -Parameter $params
    } finally {
        # Switch back to original subscription
        $null = Set-AzContext -Context $originalContext -ErrorAction Stop
    }
}
Export-ModuleMember -Function Update-AdLdapSecret


# Update LDAP secret for a VM
# ---------------------------
function Update-VMLdapSecret {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "VM name")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "VM resource group")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Password for LDAP search account")]
        [string]$LdapSearchPassword
    )
    Add-LogMessage -Level Info "[ ] Setting LDAP secret on SRD '${Name}'"
    $params = @{
        ldapSearchPasswordB64 = $LdapSearchPassword | ConvertTo-Base64
    }
    $scriptPath = Join-Path $PSScriptRoot "remote" "ResetLdapPasswordOnVm.sh"
    $null = Invoke-RemoteScript -Shell "UnixShell" -ScriptPath $scriptPath -VMName $Name -ResourceGroupName $ResourceGroupName -Parameter $params
}
Export-ModuleMember -Function Update-VMLdapSecret
