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
