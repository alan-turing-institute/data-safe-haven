# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
  $sreResearchUserSecurityGroup,
  $shmNetbiosName
)

Import-Module NPS
Import-Module RemoteDesktopServices

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
    $_ = Get-Item $("RDS:\GatewayServer\RAP\$rapName\UserGroups\") | Get-ChildItem | Where-Object { $_.Name -ne "$sreResearchUserSecurityGroupWithDomain" } | Remove-Item  -ErrorAction SilentlyContinue
    $success = ($success -And $?)
    # Report success / failure
    if ($success) {
        Write-Host -ForegroundColor DarkGreen " [o] Successfully restricted $rapName User Groups to $sreResearchUserSecurityGroupWithDomain."
    } else {
        Write-Host -ForegroundColor DarkRed " [x] Failed to restrict $rapName User Groups to $sreResearchUserSecurityGroupWithDomain!"
    }
}

