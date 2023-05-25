Import-Module $PSScriptRoot/AzureCompute -ErrorAction Stop
Import-Module $PSScriptRoot/DataStructures -ErrorAction Stop
Import-Module $PSScriptRoot/Logging -ErrorAction Stop


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


# Update DNS record on the SHM for a VM
# -------------------------------------
function Update-VMDnsRecords {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of primary DC VM")]
        [string]$DcName,
        [Parameter(Mandatory = $true, HelpMessage = "Resource group of primary DC VM")]
        [string]$DcResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "FQDN for this SHM")]
        [string]$BaseFqdn,
        [Parameter(Mandatory = $true, HelpMessage = "Name of the SHM subscription")]
        [string]$ShmSubscriptionName,
        [Parameter(Mandatory = $true, HelpMessage = "Hostname of VM whose records need to be updated")]
        [string]$VmHostname,
        [Parameter(Mandatory = $true, HelpMessage = "IP address for this VM")]
        [string]$VmIpAddress
    )
    # Get original subscription
    $originalContext = Get-AzContext
    try {
        $null = Set-AzContext -SubscriptionId $ShmSubscriptionName -ErrorAction Stop
        Add-LogMessage -Level Info "[ ] Resetting DNS record for VM '$VmHostname'..."
        $params = @{
            Fqdn      = $BaseFqdn
            HostName  = ($VmHostname | Limit-StringLength -MaximumLength 15)
            IpAddress = $VMIpAddress
        }
        $scriptPath = Join-Path $PSScriptRoot "remote" "ResetDNSRecord.ps1"
        $null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $DcName -ResourceGroupName $DcResourceGroupName -Parameter $params
        if ($?) {
            Add-LogMessage -Level Success "Resetting DNS record for VM '$VmHostname' was successful"
        } else {
            Add-LogMessage -Level Failure "Resetting DNS record for VM '$VmHostname' failed!"
        }
    } finally {
        # Switch back to original subscription
        $null = Set-AzContext -Context $originalContext -ErrorAction Stop
    }
}
Export-ModuleMember -Function Update-VMDnsRecords


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
