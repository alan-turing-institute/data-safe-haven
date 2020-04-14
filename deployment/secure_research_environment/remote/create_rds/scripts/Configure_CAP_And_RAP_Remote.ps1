# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
  $sreResearchUserSecurityGroup,
  $shmNetbiosName,
  $shmNpsIp,
  $remoteNpsPriority,
  $remoteNpsTimeout,
  $remoteNpsBlackout,
  $remoteNpsSecret,
  $remoteNpsServerGroup
)

Import-Module NPS
Import-Module RemoteDesktopServices

function Get-NpsServerAddresses ($remoteServerGroup){
    $npserverAddresses = netsh nps show remoteserver "$remoteServerGroup" | Select-String "Address + =" | ForEach-Object { ($_.ToString() -replace '(Address + = )(.*)', '$2').Trim() }
    return $npserverAddresses
}

# Set RAP user groups
# -------------------
# Format user group as <security-group>@<netbios-domain>
$sreResearchUserSecurityGroupWithDomain = $("$sreResearchUserSecurityGroup@$shmNetbiosName")
ForEach ($rapName in ("RDG_AllDomainComputers", "RDG_RDConnectionBrokers")) {
    $success = $true
    # NOTE: Need to add SRE Researcher user group / ensure it exists prior to removing existing
    #       user groups as there must always be at least one user group assigned for each RAP
    # Ensure SRE Researcher user group is assigned to RAP
    if((Get-Item RDS:\GatewayServer\RAP\$rapName\UserGroups\ | Get-ChildItem | Where-Object { $_.Name -eq  $sreResearchUserSecurityGroupWithDomain  }).Length -eq 0) {
        $_ = New-Item $("RDS:\GatewayServer\RAP\$rapName\UserGroups\") -Name "$sreResearchUserSecurityGroupWithDomain" -ErrorAction SilentlyContinue
        $success = ($success -And $?)
    }
    # Remove all other user groups from RAP
    $_ = Get-Item $("RDS:\GatewayServer\RAP\$rapName\UserGroups\") | Get-ChildItem | Where-Object { $_.Name -ne "$sreResearchUserSecurityGroupWithDomain" } | Remove-Item -ErrorAction SilentlyContinue
    $success = ($success -And $?)
    # Report success / failure
    if ($success) {
        Write-Host -ForegroundColor DarkGreen " [o] Successfully restricted '$rapName' User Groups to '$sreResearchUserSecurityGroupWithDomain'."
    } else {
        Write-Host -ForegroundColor DarkRed " [x] Failed to restrict '$rapName' User Groups to '$sreResearchUserSecurityGroupWithDomain'!"
    }
}

# Configure remote NPS server
# ---------------------------
# Remove all existing remote NPS servers
$npsServerAddresses = (Get-NpsServerAddresses $remoteNpsServerGroup)
Foreach ($npsServerAddress in $npsServerAddresses ) {
    $_ = netsh nps delete remoteserver remoteservergroup = "`"$remoteNpsServerGroup`"" address = "`"$npsServerAddress`""
}
# Add SHM NPS server
$_ = netsh nps add remoteserver remoteServerGroup = "`"$remoteNpsServerGroup`"" address = "`"$shmNpsIp`"" authsharedsecret = "`"$remoteNpsSecret`"" priority = $remoteNpsPriority timeout = $remoteNpsTimeout blackout = $remoteNpsBlackout
# Check that the change has actually been made (the netsh nps command always returns "ok")
$success = $true
[array]$npsServerAddresses = (Get-NpsServerAddresses $remoteNpsServerGroup)
$numNpsServers = $npsServerAddresses.Length
if($numNpsServers -ne 1){
    $success = $false
}
else {
    $firstNpsServerAddress = $npsServerAddresses[0]
    $success = ($success -And ($firstNpsServerAddress -eq $shmNpsIp))
}
if($success) {
    Write-Host -ForegroundColor DarkGreen " [o] Successfully configured '$firstNpsServerAddress' as the only remote NPS server."
} else {
    Write-Host -ForegroundColor DarkRed " [x] Failed to configure '$firstNpsServerAddress' as the only remote NPS server!"
}

# Set RDS Gateway to use remote NPS server
# ----------------------------------------
$_ = Set-Item RDS:\GatewayServer\CentralCAPEnabled\ -Value 1 -ErrorAction SilentlyContinue
$success = $?
if($success) {
    Write-Host -ForegroundColor DarkGreen " [o] Successfully set remote NPS server as RD CAP store."
} else {
    Write-Host -ForegroundColor DarkRed " [x] Failed to set remote NPS server as RD CAP store!"
}

