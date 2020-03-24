# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [Parameter(Position = 7,HelpMessage = "ADSync account password as an encrypted string")]
    [ValidateNotNullOrEmpty()]
    [string]$adsyncAccountPasswordEncrypted,
    [Parameter(Position = 2,HelpMessage = "Domain (eg. turingsafehaven.ac.uk)")]
    [ValidateNotNullOrEmpty()]
    [string]$domain,
    [Parameter(Position = 1,HelpMessage = "Domain OU (eg. DC=TURINGSAFEHAVEN,DC=AC,DC=UK)")]
    [ValidateNotNullOrEmpty()]
    [string]$domainou,
    [Parameter(Position = 9, HelpMessage = "Name of the LDAP users group")]
    [ValidateNotNullOrEmpty()]
    [string]$ldapUsersSgName,
    [Parameter(Position = 0,HelpMessage = "Enter Path to GPO backup files")]
    [ValidateNotNullOrEmpty()]
    [string]$oubackuppath,
    [Parameter(Position = 6,HelpMessage = "Server admin name")]
    [ValidateNotNullOrEmpty()]
    [string]$serverAdminName,
    [Parameter(Position = 8, HelpMessage = "Name of the server administrator group")]
    [ValidateNotNullOrEmpty()]
    [string]$serverAdminSgName,
    [Parameter(Position = 5,HelpMessage = "Server name")]
    [ValidateNotNullOrEmpty()]
    [string]$serverName
)

# Convert encrypted string to secure string
$adsyncAccountPasswordSecureString = ConvertTo-SecureString -String $adsyncAccountPasswordEncrypted -Key (1..16)

# Enable AD Recycle Bin
Write-Host "Configuring AD recycle bin..."
$featureExists = $(Get-ADOptionalFeature -Identity "Recycle Bin Feature" -Server $serverName).EnabledScopes | Select-String "$domainou"
if ("$featureExists" -ne "") {
    Write-Host " [o] already enabled"
} else {
    Enable-ADOptionalFeature -Identity "Recycle Bin Feature" -Scope ForestOrConfigurationSet -Target $domain -Server $serverName -confirm:$false
    if ($?) {
        Write-Host " [o] Succeeded"
    } else {
        Write-Host " [x] Failed!"
    }
}

# Set admin user account password to never expire
Write-Host "Setting admin account to never expire..."
Set-ADUser -Identity $serverAdminName -PasswordNeverExpires $true
if ($?) {
    Write-Host " [o] Succeeded"
} else {
    Write-Host " [x] Failed!"
}

# Set minumium password age to 0
Write-Host "Changing minimum password age to 0..."
Set-ADDefaultDomainPasswordPolicy -Identity $domain -MinPasswordAge 0.0:0:0.0
if ($?) {
    Write-Host " [o] Succeeded"
} else {
    Write-Host " [x] Failed!"
}

# Ensure that OUs exist
Write-Host "Creating management OUs..."
foreach ($ouName in ("Safe Haven Research Users",
                     "Safe Haven Security Groups",
                     "Safe Haven Service Accounts",
                     "Safe Haven Service Servers",
                     "Secure Research Environment Data Servers",
                     "Secure Research Environment RDS Session Servers",
                     "Secure Research Environment Service Servers")
                     ) {
    $ouExists = Get-ADOrganizationalUnit -Filter "Name -eq '$ouName'"
    if ("$ouExists" -ne "") {
        Write-Host " [o] OU '$ouName' already exists"
    } else {
        New-ADOrganizationalUnit -Name "$ouName" -Description "$ouName"
        if ($?) {
            Write-Host " [o] OU '$ouName' created successfully"
        } else {
            Write-Host " [x] OU '$ouName' creation failed!"
        }
    }
}

# Create security groups
Write-Host "Creating security groups..."
foreach ($groupName in ($serverAdminSgName, $ldapUsersSgName)) {
    $groupExists = $(Get-ADGroup -Filter "Name -eq '$groupName'").Name
    if ("$groupExists" -ne "") {
        Write-Host " [o] Security group '$groupName' already exists"
    } else {
        New-ADGroup -Name "$groupName" -GroupScope Global -Description "$groupName" -GroupCategory Security -Path "OU=Safe Haven Security Groups,$domainou"
        if ($?) {
            Write-Host " [o] Security group '$groupName' created successfully"
        } else {
            Write-Host " [x] Security group '$groupName' creation failed!"
        }
    }
}

# Creating global service accounts
$adsyncAccountName = "localadsync"
Write-Host "Creating AD Sync Service account ($adsyncAccountName)..." # - enter password for this account when prompted"
$adsyncUserName = "Local AD Sync Administrator" # NB. name must be less than 20 characters
$serviceOuPath = "OU=Safe Haven Service Accounts,$domainou"
$userExists = $(Get-ADUser -Filter "Name -eq '$adsyncUserName'").Name
if ("$userExists" -ne "") {
    Write-Host " [o] Account '$adsyncUserName' already exists"
} else {
    New-ADUser -Name "$adsyncUserName" `
         -UserPrincipalName "$adsyncAccountName@$domain" `
         -Path "$serviceOuPath" `
         -SamAccountName $adsyncAccountName `
         -DisplayName "$adsyncUserName" `
         -Description "Azure AD Connect service account" `
         -AccountPassword $adsyncAccountPasswordSecureString `
         -Enabled $true `
         -PasswordNeverExpires $true
    if ($?) {
        Write-Host " [o] AD Sync Service account '$adsyncUserName' created successfully"
    } else {
        Write-Host " [x] AD Sync Service account '$adsyncUserName' creation failed!"
    }
}

# Add users to security groups
Write-Host "Adding users to security groups..."
# NB. As of build 1.4.###.# it is no longer supported to use an Enterprise Admin or a Domain Admin account as the AD DS Connector account.
$membershipExists = $(Get-ADGroupMember -Identity "$serverAdminSgName").Name | Select-String "$serverAdminName"
if ("$membershipExists" -eq "$serverAdminName") {
    Write-Host " [o] Account '$serverAdminName' is already in '$serverAdminSgName'"
} else {
    Add-ADGroupMember "$serverAdminSgName" "$serverAdminName"
    if ($?) {
        Write-Host " [o] Account '$serverAdminName' added to '$serverAdminSgName' group"
    } else {
        Write-Host " [x] Account '$serverAdminName' could not be added to '$serverAdminSgName' group!"
    }
}

# Import GPOs into Domain
Write-Host "Importing GPOs..."
foreach ($backupTargetPair in (("0AF343A0-248D-4CA5-B19E-5FA46DAE9F9C", "All servers - Local Administrators"),
                               ("EE9EF278-1F3F-461C-9F7A-97F2B82C04B4", "All Servers - Windows Update"),
                               ("742211F9-1482-4D06-A8DE-BA66101933EB", "All Servers - Windows Services"),
                               ("B0A14FC3-292E-4A23-B280-9CC172D92FD5", "Session Servers - Remote Desktop Control"))) {
    $backup,$target = $backupTargetPair
    Import-GPO -BackupId "$backup" -TargetName "$target" -Path $oubackuppath -CreateIfNeeded
    if ($?) {
        Write-Host " [o] Importing '$backup' to '$target' succeeded"
    } else {
        Write-Host " [x] Importing '$backup' to '$target' failed!"
    }
}

# Link GPO with OUs
Write-Host "Linking GPOs to OUs..."
foreach ($gpoOuNamePair in (("All servers - Local Administrators", "Safe Haven Service Servers"),
                            ("All servers - Local Administrators", "Secure Research Environment Data Servers"),
                            ("All servers - Local Administrators", "Secure Research Environment RDS Session Servers"),
                            ("All servers - Local Administrators", "Secure Research Environment Service Servers"),
                            ("All Servers - Windows Services", "Domain Controllers"),
                            ("All Servers - Windows Services", "Safe Haven Service Servers"),
                            ("All Servers - Windows Services", "Secure Research Environment Data Servers"),
                            ("All Servers - Windows Services", "Secure Research Environment RDS Session Servers"),
                            ("All Servers - Windows Services", "Secure Research Environment Service Servers"),
                            ("All Servers - Windows Update", "Domain Controllers"),
                            ("All Servers - Windows Update", "Safe Haven Service Servers"),
                            ("All Servers - Windows Update", "Secure Research Environment Data Servers"),
                            ("All Servers - Windows Update", "Secure Research Environment RDS Session Servers"),
                            ("All Servers - Windows Update", "Secure Research Environment Service Servers"),
                            ("Session Servers - Remote Desktop Control", "Secure Research Environment RDS Session Servers"))) {
    $gpoName,$ouName = $gpoOuNamePair
    $gpo = Get-GPO -Name "$gpoName"
    # Check for a match in existing GPOs
    [xml]$gpoReportXML = Get-GPOReport -Guid $gpo.Id -ReportType xml
    $hasGPLink = $false
    foreach ($existingGPLink in $gpoReportXML.GPO.LinksTo) {
        if (($existingGPLink.SOMName -like "*$ouName*") -and ($existingGPLink.SOMPath -eq "$domain/$ouName")) {
            $hasGPLink = $true
        }
    }
    # Create a GP link if it doesn't already exist
    if ($hasGPLink) {
        Write-Host " [o] GPO '$gpoName' already linked to '$ouName'"
    } else {
        New-GPLink -Guid $gpo.Id -Target "OU=$ouName,$domainou" -LinkEnabled Yes
        if ($?) {
            Write-Host " [o] Linking GPO '$gpoName' to '$ouName' succeeded"
        } else {
            Write-Host " [x] Linking GPO '$gpoName' to '$ouName' failed!"
        }
    }
}
