# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [Parameter(HelpMessage = "Base-64 encoded secret that is shared with the NPS server")]
    [ValidateNotNullOrEmpty()]
    [string]$npsSecretB64,
    [Parameter(HelpMessage = "Blackout for NPS server")]
    [ValidateNotNullOrEmpty()]
    [string]$remoteNpsBlackout,
    [Parameter(HelpMessage = "Priority for NPS server")]
    [ValidateNotNullOrEmpty()]
    [string]$remoteNpsPriority,
    [Parameter(HelpMessage = "Whether NPS server requires authentication")]
    [ValidateNotNullOrEmpty()]
    [string]$remoteNpsRequireAuthAttrib,
    [Parameter(HelpMessage = "Server group to check for NPS servers")]
    [ValidateNotNullOrEmpty()]
    [string]$remoteNpsServerGroup,
    [Parameter(HelpMessage = "Timeout for NPS server")]
    [ValidateNotNullOrEmpty()]
    [string]$remoteNpsTimeout,
    [Parameter(HelpMessage = "NetBios name for the SHM domain")]
    [ValidateNotNullOrEmpty()]
    [string]$shmNetbiosName,
    [Parameter(HelpMessage = "IP address for the NPS server")]
    [ValidateNotNullOrEmpty()]
    [string]$shmNpsIp,
    [Parameter(HelpMessage = "Security group that research users belong to")]
    [ValidateNotNullOrEmpty()]
    [string]$sreResearchUserSecurityGroup
)

Import-Module NPS -ErrorAction Stop
Import-Module RemoteDesktopServices -ErrorAction Stop

function Get-NpsServerAddresses {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Server group to check for NPS servers")]
        [string]$remoteServerGroup
    )
    $npserverAddresses = netsh nps show remoteserver "$remoteServerGroup" | Select-String "Address + =" | ForEach-Object { ($_.ToString() -replace '(Address + = )(.*)', '$2').Trim() }
    return $npserverAddresses
}


# Deserialise Base-64 encoded variables
# -------------------------------------
$npsSecret = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($npsSecretB64))


# Set RAP user groups
# -------------------
# Format user group as <security-group>@<netbios-domain>
$sreResearchUserSecurityGroupWithDomain = "${sreResearchUserSecurityGroup}@${shmNetbiosName}"
foreach ($rapName in ("RDG_AllDomainComputers", "RDG_RDConnectionBrokers")) {
    $success = $true

    # NOTE: Need to add SRE Researcher user group / ensure it exists prior to removing existing
    #       user groups as there must always be at least one user group assigned for each RAP
    # Ensure SRE Researcher user group is assigned to RAP
    if (-not (Get-Item "RDS:\GatewayServer\RAP\${rapName}\UserGroups\" | Get-ChildItem | Where-Object { $_.Name -eq $sreResearchUserSecurityGroupWithDomain })) {
        $null = New-Item "RDS:\GatewayServer\RAP\${rapName}\UserGroups\" -Name "$sreResearchUserSecurityGroupWithDomain" -ErrorAction SilentlyContinue
        $success = $success -and $?
    }

    # Remove all other user groups from RAP
    # If the SRE Researcher group is not in the RAP User Group list (e.g. if the `New-Item` command above failed)
    # this command to remove all other groups will fail, as there must always be at least one User Group.
    $null = Get-Item "RDS:\GatewayServer\RAP\${rapName}\UserGroups\" | Get-ChildItem | Where-Object { $_.Name -ne "$sreResearchUserSecurityGroupWithDomain" } | Remove-Item -ErrorAction SilentlyContinue
    $success = $success -and $?
    # Report success / failure
    if ($success) {
        Write-Output " [o] Successfully restricted '$rapName' user groups to '$sreResearchUserSecurityGroupWithDomain'."
    } else {
        Write-Output " [x] Failed to restrict '$rapName' user groups to '$sreResearchUserSecurityGroupWithDomain'!"
    }
}

# Configure remote NPS server
# ---------------------------
# Remove all existing remote NPS servers
foreach ($npsServerAddress in (Get-NpsServerAddresses -remoteServerGroup $remoteNpsServerGroup)) {
    $null = netsh nps delete remoteserver remoteservergroup = "$remoteNpsServerGroup" address = "$npsServerAddress"
}
# Add SHM NPS server
$null = netsh nps add remoteserver `
    remoteServerGroup = "$remoteNpsServerGroup" `
    address = "$shmNpsIp" `
    authsharedsecret = "$npsSecret" `
    requireauthattrib = "$remoteNpsRequireAuthAttrib" `
    acctsharedsecret = "$npsSecret" `
    priority = "$remoteNpsPriority" `
    timeout = "$remoteNpsTimeout" `
    blackout = "$remoteNpsBlackout"
# Check that the change has actually been made (the netsh nps command always returns "ok")
[array]$npsServerAddresses = (Get-NpsServerAddresses -remoteServerGroup $remoteNpsServerGroup)
$success = ($npsServerAddresses.Length -eq 1)
if ($success) {
    $firstNpsServerAddress = $npsServerAddresses[0]
    $success = $success -and ($firstNpsServerAddress -eq $shmNpsIp)
}
if ($success) {
    Write-Output " [o] Successfully configured '$firstNpsServerAddress' as the only remote NPS server."
} else {
    Write-Output " [x] Failed to configure remote NPS server. Found $($npsServerAddresses.Length) candidates!"
}

# Set RDS Gateway to use remote NPS server
# ----------------------------------------
$null = Set-Item RDS:\GatewayServer\CentralCAPEnabled\ -Value 1 -ErrorAction SilentlyContinue
if ($?) {
    Write-Output " [o] Successfully set remote NPS server as RD CAP store."
} else {
    Write-Output " [x] Failed to set remote NPS server as RD CAP store!"
}
