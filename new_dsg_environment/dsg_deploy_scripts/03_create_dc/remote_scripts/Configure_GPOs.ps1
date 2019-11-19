# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
Param(
  [Parameter(HelpMessage="Enter Path to GPO backup files")]
  [ValidateNotNullOrEmpty()]
  [string]$oubackuppath,
  [Parameter(HelpMessage="DSG Netbios name")]
  [ValidateNotNullOrEmpty()]
  [string]$sreNetbiosName,
  [Parameter(HelpMessage="Domain (eg. testsandbox.turingsafehaven.ac.uk)")]
  [ValidateNotNullOrEmpty()]
  [string]$sreFqdn,
  [Parameter(HelpMessage="Domain OU (eg. DC=testsandbox,DC=turingsafehaven,DC=ac,DC=uk)")]
  [ValidateNotNullOrEmpty()]
  [string]$sreDomainOu
)


# Import GPOs into Domain
# -----------------------
Write-Host "Importing GPOs..."
ForEach($backupTargetPair in (("0AF343A0-248D-4CA5-B19E-5FA46DAE9F9C", "All servers - Local Administrators"),
                              ("D320C1D9-52EF-47D8-80A7-1E73A457CDAD", "Research Users - Mapped Drives"),
                              ("EE9EF278-1F3F-461C-9F7A-97F2B82C04B4", "All Servers - Windows Update"),
                              ("B0A14FC3-292E-4A23-B280-9CC172D92FD5", "Session Servers - Remote Desktop Control"),
                              ("742211F9-1482-4D06-A8DE-BA66101933EB", "All Servers - Windows Services"))) {
  $backup, $target = $backupTargetPair
  $_ = Import-GPO -BackupId "$backup" -TargetName "$target" -Path $oubackuppath -CreateIfNeeded
  if ($?) {
    Write-Host " [o] Importing '$backup' to '$target' succeeded"
  } else {
    Write-Host " [x] Importing '$backup' to '$target' failed!"
  }
}


# Link GPOs with OUs
# ------------------
Write-Host "Linking GPOs to OUs..."
ForEach ($gpoOuNamePair in (("All servers - Local Administrators", "$sreNetbiosName Data Servers"),
                            ("All servers - Local Administrators", "$sreNetbiosName RDS Session Servers"),
                            ("All servers - Local Administrators", "$sreNetbiosName Service Servers"),
                            ("All Servers - Windows Services", "Domain Controllers"),
                            ("All Servers - Windows Services", "$sreNetbiosName Data Servers"),
                            ("All Servers - Windows Services", "$sreNetbiosName RDS Session Servers"),
                            ("All Servers - Windows Services", "$sreNetbiosName Service Servers"),
                            ("All Servers - Windows Update", "Domain Controllers"),
                            ("All Servers - Windows Update", "$sreNetbiosName Data Servers"),
                            ("All Servers - Windows Update", "$sreNetbiosName RDS Session Servers"),
                            ("All Servers - Windows Update", "$sreNetbiosName Service Servers"),
                            ("Research Users - Mapped Drives", "$sreNetbiosName RDS Session Servers"),
                            ("Session Servers - Remote Desktop Control", "$sreNetbiosName RDS Session Servers"))) {
  $gpoName, $ouName = $gpoOuNamePair
  $gpo = Get-GPO -Name "$gpoName"
  # Check for a match in existing GPOs
  [xml]$gpoReportXML = Get-GPOReport -Guid $gpo.ID -ReportType xml
  $hasGPLink = $false
  ForEach ($existingGPLink in $gpoReportXML.GPO.LinksTo) {
    if (($existingGPLink.SOMName -like "*$ouName*") -and ($existingGPLink.SOMPath -eq "$sreFqdn/$ouName")) {
      $hasGPLink=$true
    }
  }
  # Create a GP link if it doesn't already exist
  if ($hasGPLink) {
    Write-Host " [o] GPO '$gpoName' already linked to '$ouName'"
  } else {
    $_ = New-GPLink -Guid $gpo.ID -Target "OU=$ouName,$sreDomainOu" -LinkEnabled Yes
    if ($?) {
      Write-Host " [o] Linking GPO '$gpoName' to '$ouName' succeeded"
    } else {
      Write-Host " [x] Linking GPO '$gpoName' to '$ouName' failed!"
    }
  }
}


# Set the layout file for the Remote Desktop servers
# --------------------------------------------------
Write-Host "Setting the layout file for the Remote Desktop servers..."
$_ = Set-GPRegistryValue -Name "Session Servers - Remote Desktop Control" -Type "ExpandString" -Key "HKCU\Software\Policies\Microsoft\Windows\Explorer\" `
                         -ValueName "StartLayoutFile" -Value "\\$sreFqdn\SYSVOL\$sreFqdn\scripts\ServerStartMenu\LayoutModification.xml"
if ($?) {
  Write-Host " [o] Succeeded"
} else {
  Write-Host " [x] Failed!"
}


# Configure group policies
# ------------------------
Write-Host "Configuring group policies"

# Get GPO for the Local Administrators group
$gpo = Get-GPO -Name "All servers - Local Administrators"

# Get SIDs for the relevant groups
$domainAdminsSID = (Get-ADGroup "Domain Admins").SID.Value
$serverAdminsSID = (Get-ADGroup "SG $sreNetbiosName Server Administrators").SID.Value

# Get path to the GptTmpl file
$GptTmplPath = "F:"; "SYSVOL", "domain", "Policies", "{$($gpo.ID)}", "Machine", "Microsoft", "Windows NT", "SecEdit", "GptTmpl.inf" | ForEach-Object -Process { $GptTmplPath = Join-Path $GptTmplPath $_ }

# Get the old and new lines in the GptTmpl file
$oldLine = Select-String -Path $GptTmplPath -Pattern "__Members =" | % {$_.Line} #| % {$_ -Replace "\*", "\*"}
$newLine = $($oldLine -Split '=')[0] + "= *$domainAdminsSID,*$serverAdminsSID"

# Update GptTmpl file
$_ = ((Get-Content -Path $GptTmplPath -Raw) -Replace [regex]::escape($oldLine), $newLine) | Set-Content -Path $GptTmplPath
if ($?) {
  Write-Host " [o] Successfully configured group policies for 'Local Administrators'"
} else {
  Write-Host " [x] Failed to configure group policies for 'Local Administrators'"
}
