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
    [Parameter(HelpMessage = "Domain NetBIOS name")]
    [ValidateNotNullOrEmpty()]
    [string]$domainNetBiosName,
    [Parameter(HelpMessage = "Domain OU (eg. DC=TURINGSAFEHAVEN,DC=AC,DC=UK)")]
    [ValidateNotNullOrEmpty()]
    [string]$domainOuBase,
    [Parameter(HelpMessage = "Domain (eg. turingsafehaven.ac.uk)")]
    [ValidateNotNullOrEmpty()]
    [string]$shmFdqn,
    [Parameter(HelpMessage = "Base64-encoded user account details")]
    [ValidateNotNullOrEmpty()]
    [string]$userAccountsB64
)

Import-Module ActiveDirectory -ErrorAction Stop


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
    $adContainer = Get-ADObject -Filter "Name -eq '$ContainerName'"
    $success = $?
    # Add permission to create child computer objects
    $null = dsacls $adContainer /I:T /G "${UserPrincipalName}:CC;computer"
    $success = $success -and $?
    # Give 'write property' permissions over several attributes of child computers
    $null = dsacls $adContainer /I:S /G "${UserPrincipalName}:WP;DNS Host Name Attributes;computer"
    $success = $success -and $?
    $null = dsacls $adContainer /I:S /G "${UserPrincipalName}:WP;msDS-SupportedEncryptionTypes;computer"
    $success = $success -and $?
    $null = dsacls $adContainer /I:S /G "${UserPrincipalName}:WP;operatingSystem;computer"
    $success = $success -and $?
    $null = dsacls $adContainer /I:S /G "${UserPrincipalName}:WP;operatingSystemVersion;computer"
    $success = $success -and $?
    $null = dsacls $adContainer /I:S /G "${UserPrincipalName}:WP;operatingSystemServicePack;computer"
    $success = $success -and $?
    $null = dsacls $adContainer /I:S /G "${UserPrincipalName}:WP;sAMAccountName;computer"
    $success = $success -and $?
    $null = dsacls $adContainer /I:S /G "${UserPrincipalName}:WP;servicePrincipalName;computer"
    $success = $success -and $?
    $null = dsacls $adContainer /I:S /G "${UserPrincipalName}:WP;userPrincipalName;computer"
    $success = $success -and $?
    if ($success) {
        Write-Output " [o] Successfully delegated permissions on the '$ContainerName' container to '${UserPrincipalName}'"
    } else {
        Write-Output " [x] Failed to delegate permissions on the '$ContainerName' container to '${UserPrincipalName}'!"
    }
}


function New-ShmUser {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of AD user")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "SAM account name of AD user")]
        [string]$SamAccountName,
        [Parameter(Mandatory = $true, HelpMessage = "Domain to create user under")]
        [string]$Domain,
        [Parameter(Mandatory = $true, HelpMessage = "OU path for AD user")]
        [string]$Path,
        [Parameter(Mandatory = $true, HelpMessage = "Password as secure string ")]
        [securestring]$AccountPassword
    )
    if (Get-ADUser -Filter "SamAccountName -eq '$SamAccountName'") {
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


# Decode user accounts and create them
# ------------------------------------
$userAccounts = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($userAccountsB64)) | ConvertFrom-Json
$serviceOuPath = "OU={{domain.ous.serviceAccounts.name}},$domainOuBase"
# Azure active directory synchronisation service account
# NB. As of build 1.4.###.# it is no longer supported to use an enterprise admin or a domain admin account with AD Connect.
Write-Output "Creating AD Sync Service account $($userAccounts.aadLocalSync.samAccountName)..."
New-ShmUser -Name "$($userAccounts.aadLocalSync.name)" -SamAccountName "$($userAccounts.aadLocalSync.samAccountName)" -Path $serviceOuPath -AccountPassword $(ConvertTo-SecureString $userAccounts.aadLocalSync.password -AsPlainText -Force) -Domain $shmFdqn
# Service servers domain joining service account
foreach ($serviceAccountCfg in $($userAccounts.PSObject.Members | Where-Object { $_.TypeNameOfValue -eq "System.Management.Automation.PSCustomObject" } )) {
    Write-Output "Creating $($serviceAccountCfg.Value.name) domain joining account $($serviceAccountCfg.Value.samAccountName)..."
    New-ShmUser -Name "$($serviceAccountCfg.Value.name)" -SamAccountName "$($serviceAccountCfg.Value.samAccountName)" -Path $serviceOuPath -AccountPassword $(ConvertTo-SecureString $serviceAccountCfg.Value.password -AsPlainText -Force) -Domain $shmFdqn
}

# Add users to security groups
# ----------------------------
Write-Output "Adding users to security groups..."
Add-ShmUserToGroup -SamAccountName $domainAdminUsername -GroupName $securityGroups.serverAdmins.name
foreach ($serviceAccount in $userAccounts.Keys) {
    Add-ShmUserToGroup -SamAccountName $userAccounts."$serviceAccount".samAccountName -GroupName $securityGroups.computerManagers.name
}


# Set AAD sync permissions for the localadsync account.
# Without this self-service password reset will not work.
# -------------------------------------------------------
Write-Output "Setting AAD sync permissions for AD Sync Service account ($($userAccounts.aadLocalSync.samAccountName))..."
$rootDse = Get-ADRootDSE
$defaultNamingContext = $rootDse.DefaultNamingContext
$configurationNamingContext = $rootDse.ConfigurationNamingContext
$schemaNamingContext = $rootDse.SchemaNamingContext
# Create hashtables to store the GUID values of each schema class and attribute and each extended right in the forest
$guidmap = @{}
Get-ADObject -SearchBase $schemaNamingContext -LDAPFilter "(schemaidguid=*)" -Properties lDAPDisplayName, schemaIDGUID | ForEach-Object { $guidmap[$_.lDAPDisplayName] = [System.GUID]$_.schemaIDGUID }
$extendedRightsMap = @{}
Get-ADObject -SearchBase $configurationNamingContext -LDAPFilter "(&(objectclass=controlAccessRight)(rightsguid=*))" -Properties displayName, rightsGuid | ForEach-Object { $extendedRightsMap[$_.displayName] = [System.GUID]$_.rightsGuid }
# Get the SID for the localadsync account
$adsyncSID = New-Object System.Security.Principal.SecurityIdentifier (Get-ADUser $userAccounts.aadLocalSync.samAccountName).SID
$success = $?
# Get a copy of the current ACL on the OU
$acl = Get-ACL -Path "AD:\${domainOuBase}"
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
# Allow the localadsync account to write the mS-DS-ConsistencyGuid extended property (used as an anchor) on all descendent user objects
$acl.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule $adsyncSID, "WriteProperty", "Allow", $guidmap["mS-DS-ConsistencyGuid"], "Descendents", $guidmap["user"]))
$success = $success -and $?
$acl.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule $adsyncSID, "WriteProperty", "Allow", $guidmap["msDS-KeyCredentialLink"], "Descendents", $guidmap["user"]))
$success = $success -and $?
# Set the ACL properties
Set-ACL -ACLObject $acl -Path "AD:\${domainOuBase}"
$success = $success -and $?
# Allow the localadsync account to replicate directory changes
$null = dsacls "$defaultNamingContext" /G "${adsyncSID}:CA;Replicating Directory Changes"
$success = $success -and $?
$null = dsacls "$configurationNamingContext" /G "${adsyncSID}:CA;Replicating Directory Changes"
$success = $success -and $?
$null = dsacls "$defaultNamingContext" /G "${adsyncSID}:CA;Replicating Directory Changes All"
$success = $success -and $?
$null = dsacls "$configurationNamingContext" /G "${adsyncSID}:CA;Replicating Directory Changes All"
$success = $success -and $?
if ($success) {
    Write-Output " [o] Successfully updated ACL permissions for AD Sync Service account '$($userAccounts.aadLocalSync.samAccountName)'"
} else {
    Write-Output " [x] Failed to update ACL permissions for AD Sync Service account '$($userAccounts.aadLocalSync.samAccountName)'!"
}


# Delegate Active Directory permissions to users/groups that allow them to register computers in the domain
# ---------------------------------------------------------------------------------------------------------
Write-Output "Delegating Active Directory registration permissions to service users..."
# Allow the database server user to register computers in the '{{domain.ous.databaseServers.name}}' container
Grant-ComputerRegistrationPermissions -ContainerName "{{domain.ous.databaseServers.name}}" -UserPrincipalName "${domainNetBiosName}\$($userAccounts.databaseServers.samAccountName)"
# Allow the identity server user to register computers in the '{{domain.ous.identityServers.name}}' container
Grant-ComputerRegistrationPermissions -ContainerName "{{domain.ous.identityServers.name}}" -UserPrincipalName "${domainNetBiosName}\$($userAccounts.identityServers.samAccountName)"
# Allow the Linux server user to register computers in the '{{domain.ous.linuxServers.name}}' container
Grant-ComputerRegistrationPermissions -ContainerName "{{domain.ous.linuxServers.name}}" -UserPrincipalName "${domainNetBiosName}\$($userAccounts.linuxServers.samAccountName)"
# Allow the RDS gateway server user to register computers in the '{{domain.ous.rdsGatewayServers.name}}' container
Grant-ComputerRegistrationPermissions -ContainerName "{{domain.ous.rdsGatewayServers.name}}" -UserPrincipalName "${domainNetBiosName}\$($userAccounts.rdsGatewayServers.samAccountName)"
# Allow the RDS session server user to register computers in the '{{domain.ous.rdsSessionServers.name}}' container
Grant-ComputerRegistrationPermissions -ContainerName "{{domain.ous.rdsSessionServers.name}}" -UserPrincipalName "${domainNetBiosName}\$($userAccounts.rdsSessionServers.samAccountName)"
