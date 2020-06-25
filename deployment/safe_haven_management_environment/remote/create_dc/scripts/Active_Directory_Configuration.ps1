# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [Parameter(HelpMessage = "Username for a user with domain admin privileges")]
    [ValidateNotNullOrEmpty()]
    [string]$domainAdminUsername,
    [Parameter(HelpMessage = "Name of this VM (the domain controller)")]
    [ValidateNotNullOrEmpty()]
    [string]$domainControllerVmName,
    [Parameter(HelpMessage = "NetBios name")]
    [ValidateNotNullOrEmpty()]
    [string]$netbiosName,
    [Parameter(HelpMessage = "Path to GPO backup files")]
    [ValidateNotNullOrEmpty()]
    [string]$ouBackupPath,
    [Parameter(HelpMessage = "Name of the computer managers user group (eg. 'SG Safe Haven Computer Management Users')")]
    [ValidateNotNullOrEmpty()]
    [string]$sgComputerManagersName,
    [Parameter(HelpMessage = "Name of the server administrator group (eg. 'SG Safe Haven Server Administrators')")]
    [ValidateNotNullOrEmpty()]
    [string]$sgServerAdminsName,
    [Parameter(HelpMessage = "Name of the service servers group (eg. 'Safe Haven Service Servers')")]
    [ValidateNotNullOrEmpty()]
    [string]$sgServiceServersName,
    [Parameter(HelpMessage = "Domain OU (eg. DC=TURINGSAFEHAVEN,DC=AC,DC=UK)")]
    [ValidateNotNullOrEmpty()]
    [string]$shmDomainOu,
    [Parameter(HelpMessage = "Domain (eg. turingsafehaven.ac.uk)")]
    [ValidateNotNullOrEmpty()]
    [string]$shmFdqn,
    [Parameter(HelpMessage = "Base64-encoded user account details")]
    [ValidateNotNullOrEmpty()]
    [string]$userAccountsB64
)

Import-Module ActiveDirectory


function Add-ShmUserToGroup {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Security Account Manager (SAM) account name of the user, group, computer, or service account. Maximum 20 characters for backwards compatibility.")]
        $SamAccountName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of the group that the user or group will be added to.")]
        $GroupName
    )
    if ((Get-ADGroupMember -Identity $GroupName | Where-Object { $_.SamAccountName -eq "$SamAccountName" })) {
        Write-Output " [o] User '$SamAccountName' is already a member of '$GroupName'"
    } else {
        Write-Output " [ ] Adding '$SamAccountName' user to group '$GroupName'"
        Add-ADGroupMember -Identity "$GroupName" -Members "$SamAccountName"
        if ($?) {
            Write-Output " [o] User '$SamAccountName' was added to '$GroupName'"
        } else {
            Write-Output " [x] User '$SamAccountName' could not be added to '$GroupName'!"
        }
    }
}

function Grant-ComputerRegistrationPermissions {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of a container to grant permissions over")]
        $ContainerName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of the user or group that will be given permissions.")]
        $UserPrincipalName
    )
    # TODO: check whether these permissions can replace the GRGWCCDC set
    # dsacls $computersContainer /I:S /G "$($user):GR;;computer"
    # dsacls $computersContainer /I:S /G "$($user):WP;pwdLastSet;computer"
    # dsacls $computersContainer /I:S /G "$($user):WP;Logon Information;computer"
    # dsacls $computersContainer /I:S /G "$($user):WP;description;computer"
    # dsacls $computersContainer /I:S /G "$($user):WP;displayName;computer"
    # dsacls $computersContainer /I:S /G "$($user):WP;sAMAccountName;computer"
    # dsacls $computersContainer /I:S /G "$($user):WP;DNS Host Name Attributes;computer"
    # dsacls $computersContainer /I:S /G "$($user):WP;Account Restrictions;computer"
    # dsacls $computersContainer /I:S /G "$($user):WP;servicePrincipalName;computer"
    # dsacls $computersContainer /I:S /G "$($user):CC;computer;organizationalUnit"
    $adContainer = Get-ADObject -Filter "Name -eq '$ContainerName'"
    # Add 'generic read', 'generic write', 'create child' and 'delete child' permissions on the container
    $null = dsacls $adContainer /I:T /G "${UserPrincipalName}:GRGWCCDC"
    $success = $?
    # Add 'read property' and 'write property' on service principal name
    $null = dsacls $adContainer /I:T /G "${UserPrincipalName}:RPWP;servicePrincipalName"
    $success = $success -And $?
    # Add 'read property' and 'write property' on DNS attributes
    $null = dsacls $adContainer /I:T /G "${UserPrincipalName}:RPWP;DNS Host Name Attributes"
    $success = $success -And $?
    # Add 'read property' and 'write property' on supported encryption types
    $null = dsacls $adContainer /I:T /G "${UserPrincipalName}:RPWP;msDS-SupportedEncryptionTypes"
    $success = $success -And $?
    # Add 'control access' permission on computer password for child computers
    $null = dsacls $adContainer /I:T /G "${UserPrincipalName}:CA;Change Password;computer"
    $success = $?
    $null = dsacls $adContainer /I:S /G "${UserPrincipalName}:CA;Reset Password;computer"
    $success = $?
    # Add 'read property' and 'write property' on operating system attributes for child computers
    $null = dsacls $adContainer /I:S /G "${UserPrincipalName}:RPWP;operatingSystem;computer"
    $success = $success -And $?
    $null = dsacls $adContainer /I:S /G "${UserPrincipalName}:RPWP;operatingSystemVersion;computer"
    $success = $success -And $?
    $null = dsacls $adContainer /I:S /G "${UserPrincipalName}:RPWP;operatingSystemServicePack;computer"
    $success = $success -And $?
    if ($success) {
        Write-Output " [o] Successfully delegated permissions on the '$ContainerName' container to ${UserPrincipalName}"
    } else {
        Write-Output " [x] Failed to delegate permissions on the '$ContainerName' container to ${UserPrincipalName}!"
    }
}


function New-ShmUser {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of AD user")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "sAMAccountName of AD user")]
        [string]$SamAccountName,
        [Parameter(Mandatory = $true, HelpMessage = "Domain to create user under")]
        [string]$Domain,
        [Parameter(Mandatory = $true, HelpMessage = "OU path for AD user")]
        [string]$Path,
        [Parameter(Mandatory = $true, HelpMessage = "Password as secure string ")]
        [securestring]$AccountPassword
    )
    if (Get-ADUser -Filter "Name -eq '$Name'") {
        Write-Output " [o] Account '$Name' ($SamAccountName) already exists"
    } else {
        New-ADUser -Name "$Name" `
                   -UserPrincipalName "$SamAccountName@$Domain" `
                   -Path "$Path" `
                   -SamAccountName $SamAccountName `
                   -DisplayName "$Name" `
                   -Description "$Name" `
                   -AccountPassword $AccountPassword `
                   -Enabled $true `
                   -PasswordNeverExpires $true
        if ($?) {
            Write-Output " [o] Account '$Name' ($SamAccountName) created successfully"
        } else {
            Write-Output " [x] Account '$Name' ($SamAccountName) creation failed!"
        }
    }
}


# Enable AD Recycle Bin
# ---------------------
Write-Output "Configuring AD recycle bin..."
$featureExists = $(Get-ADOptionalFeature -Identity "Recycle Bin Feature" -Server $domainControllerVmName).EnabledScopes | Select-String "$shmDomainOu"
if ($featureExists) {
    Write-Output " [o] AD recycle bin is already enabled"
} else {
    Enable-ADOptionalFeature -Identity "Recycle Bin Feature" -Scope ForestOrConfigurationSet -Target $shmFdqn -Server $domainControllerVmName -Confirm:$false
    if ($?) {
        Write-Output " [o] Successfully enabled AD recycle bin"
    } else {
        Write-Output " [x] Failed to enable AD recycle bin!"
    }
}

# Set domain admin user account password to never expire
# ------------------------------------------------------
Write-Output "Setting domain admin password to never expire..."
Set-ADUser -Identity $domainAdminUsername -PasswordNeverExpires $true
if ($?) {
    Write-Output " [o] Successfully set domain admin password expiry"
} else {
    Write-Output " [x] Failed to set domain admin password expiry!"
}


# Set minumium password age to 0
# ------------------------------
Write-Output "Changing minimum password age to 0..."
Set-ADDefaultDomainPasswordPolicy -Identity $shmFdqn -MinPasswordAge 0.0:0:0.0
if ($?) {
    Write-Output " [o] Successfully changed minimum password age"
} else {
    Write-Output " [x] Failed to change minimum password age!"
}


# Ensure that OUs exist
# ---------------------
Write-Output "Creating management OUs..."
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
        Write-Output " [o] OU '$ouName' already exists"
    } else {
        New-ADOrganizationalUnit -Name "$ouName" -Description "$ouName"
        if ($?) {
            Write-Output " [o] OU '$ouName' created successfully"
        } else {
            Write-Output " [x] OU '$ouName' creation failed!"
        }
    }
}

# Create security groups
# ----------------------
Write-Output "Creating security groups..."
foreach ($groupName in ($sgServerAdminsName, $sgComputerManagersName)) {
    $groupExists = $(Get-ADGroup -Filter "Name -eq '$groupName'").Name
    if ("$groupExists" -ne "") {
        Write-Output " [o] Security group '$groupName' already exists"
    } else {
        New-ADGroup -Name "$groupName" -GroupScope Global -Description "$groupName" -GroupCategory Security -Path "OU=Safe Haven Security Groups,$shmDomainOu"
        if ($?) {
            Write-Output " [o] Security group '$groupName' created successfully"
        } else {
            Write-Output " [x] Security group '$groupName' creation failed!"
        }
    }
}


# Decode user accounts and create them
# ------------------------------------
$userAccounts = [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($userAccountsB64)) | ConvertFrom-Json
$serviceOuPath = "OU=Safe Haven Service Accounts,$shmDomainOu"
# Azure active directory synchronisation service account
# NB. As of build 1.4.###.# it is no longer supported to use an enterprise admin or a domain admin account with AD Connect.
Write-Output "Creating AD Sync Service account $($userAccounts.aadLocalSync.samAccountName)..."
New-ShmUser -Name "$($userAccounts.aadLocalSync.name)" -SamAccountName "$($userAccounts.aadLocalSync.samAccountName)" -Path $serviceOuPath -AccountPassword $(ConvertTo-SecureString $userAccounts.aadLocalSync.password -AsPlainText -Force) -Domain $shmFdqn
# Service servers domain joining service account
Write-Output "Creating service servers domain joining account $($userAccounts.serviceServers.samAccountName)..."
New-ShmUser -Name "$($userAccounts.serviceServers.name)" -SamAccountName "$($userAccounts.serviceServers.samAccountName)" -Path $serviceOuPath -AccountPassword $(ConvertTo-SecureString $userAccounts.serviceServers.password -AsPlainText -Force) -Domain $shmFdqn


# Add users to security groups
# ----------------------------
Write-Output "Adding users to security groups..."
Add-ShmUserToGroup -SamAccountName $domainAdminUsername -GroupName $sgServerAdminsName
Add-ShmUserToGroup -SamAccountName $userAccounts.serviceServers.samAccountName -GroupName $sgComputerManagersName


# Import GPOs onto domain controller
# ----------------------------------
Write-Output "Importing GPOs..."
foreach ($backupTargetPair in (("0AF343A0-248D-4CA5-B19E-5FA46DAE9F9C", "All servers - Local Administrators"),
                               ("EE9EF278-1F3F-461C-9F7A-97F2B82C04B4", "All Servers - Windows Update"),
                               ("742211F9-1482-4D06-A8DE-BA66101933EB", "All Servers - Windows Services"),
                               ("B0A14FC3-292E-4A23-B280-9CC172D92FD5", "Session Servers - Remote Desktop Control"))) {
    $backup,$target = $backupTargetPair
    $null = Import-GPO -BackupId "$backup" -TargetName "$target" -Path $ouBackupPath -CreateIfNeeded
    if ($?) {
        Write-Output " [o] Importing '$backup' to '$target' succeeded"
    } else {
        Write-Output " [x] Importing '$backup' to '$target' failed!"
    }
}


# Link GPO with OUs
# -----------------
Write-Output "Linking GPOs to OUs..."
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
        if (($existingGPLink.SOMName -like "*$ouName*") -and ($existingGPLink.SOMPath -eq "$shmFdqn/$ouName")) {
            $hasGPLink = $true
        }
    }
    # Create a GP link if it doesn't already exist
    if ($hasGPLink) {
        Write-Output " [o] GPO '$gpoName' already linked to '$ouName'"
    } else {
        New-GPLink -Guid $gpo.Id -Target "OU=$ouName,$shmDomainOu" -LinkEnabled Yes
        if ($?) {
            Write-Output " [o] Linking GPO '$gpoName' to '$ouName' succeeded"
        } else {
            Write-Output " [x] Linking GPO '$gpoName' to '$ouName' failed!"
        }
    }
}


# Set AAD sync permissions for the localadsync account.
# Without this self-service password reset will not work.
# -------------------------------------------------------
Write-Output "Setting AAD sync permissions for AD Sync Service account ($($userAccounts.aadLocalSync.samAccountName))..."
$rootDse = Get-ADRootDSE
$defaultNamingContext = $rootDse.DefaultNamingContext
$configurationNamingContext = $rootDse.ConfigurationNamingContext
$schemaNamingContext = $rootDse.SchemaNamingContext
# Create a hashtables to store the GUID values of each schema class and attribute and each extended right in the forest
$guidmap = @{}
Get-ADObject -SearchBase $schemaNamingContext -LDAPFilter "(schemaidguid=*)" -Properties lDAPDisplayName,schemaIDGUID | ForEach-Object {$guidmap[$_.lDAPDisplayName] = [System.GUID]$_.schemaIDGUID }
$extendedRightsMap = @{}
Get-ADObject -SearchBase $configurationNamingContext -LDAPFilter "(&(objectclass=controlAccessRight)(rightsguid=*))" -Properties displayName,rightsGuid | ForEach-Object { $extendedRightsMap[$_.displayName] = [System.GUID]$_.rightsGuid }
# Get the SID for the localadsync account
$adsyncSID = New-Object System.Security.Principal.SecurityIdentifier (Get-ADUser $userAccounts.aadLocalSync.samAccountName).SID
$success = $?
# Get a copy of the current ACL on the OU
$acl = Get-ACL -Path "AD:\${shmDomainOu}"
$success = $success -and $?
# Allow the localadsync account to reset and change passwords on all descendent user objects
$acl.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule $adsyncSID, "ExtendedRight", "Allow", $extendedrightsmap["Reset Password"], "Descendents", $guidmap["user"]))
$success = $success -and $?
$acl.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule $adsyncSID, "ExtendedRight", "Allow", $extendedrightsmap["Change Password"], "Descendents", $guidmap["user"]))
$success = $success -and $?
# Allow the localadsync account to write lockoutTime and pwdLastSet extended property on all descendent user objects
$acl.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule $adsyncSID, "WriteProperty", "Allow", $guidmap["lockoutTime"], "Descendents", $guidmap["user"]))
$success = $success -and $?
$acl.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule $adsyncSID, "WriteProperty", "Allow", $guidmap["pwdLastSet"], "Descendents", $guidmap["user"]))
$success = $success -and $?
# Set the ACL properties
Set-ACL -ACLObject $acl -Path "AD:\${shmDomainOu}"
$success = $success -and $?
# Allow the localadsync account to replicate directory changes
$null = dsacls "$defaultNamingContext" /G "${adsyncSID}:CA;Replicating Directory Changes"
$success = $success -and $?
$null = dsacls "$configurationNamingContext" /G "$($UserPrincipal):CA;Replicating Directory Changes"
$success = $success -and $?
$null = dsacls "$defaultNamingContext" /G "${adsyncSID}:CA;Replicating Directory Changes All"
$success = $success -and $?
$null = dsacls "$configurationNamingContext" /G "$($UserPrincipal):CA;Replicating Directory Changes All"
$success = $success -and $?
if ($success) {
    Write-Output " [o] Successfully updated ACL permissions for AD Sync Service account '$($userAccounts.aadLocalSync.samAccountName)'"
} else {
    Write-Output " [x] Failed to update ACL permissions for AD Sync Service account '$($userAccounts.aadLocalSync.samAccountName)'!"
}


# Delegate Active Directory permissions to users/groups that allow them to register computers in the domain
# ---------------------------------------------------------------------------------------------------------
Write-Output "Delegating Active Directory registration permissions to service users..."
# Allow computer managers to register computers in the 'Computers' container
Grant-ComputerRegistrationPermissions -ContainerName "Computers" -UserPrincipalName "${netbiosname}\${sgComputerManagersName}"
# Allow the service server user to register computers in the 'Safe Haven Service Servers' container
Grant-ComputerRegistrationPermissions -ContainerName "$sgServiceServersName" -UserPrincipalName "${netbiosname}\$($userAccounts.serviceServers.samAccountName)"
