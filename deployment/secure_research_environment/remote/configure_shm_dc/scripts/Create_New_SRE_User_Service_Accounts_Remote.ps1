# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# Fror details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [String]$shmSystemAdministratorSgName,
    [String]$groupsB64,
    [String]$serviceUsersB64,
    [String]$securityOuPath,
    [String]$serviceOuPath
)
# [String]$shmLdapUserSgName,
# [String]$computerManagersB64,


# Create a new security group associated with this SRE
# ----------------------------------------------------
function New-SreGroup {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of the group to be created")]
        $Name,
        [Parameter(Mandatory = $true, HelpMessage = "Description of the group to be created.")]
        $Description,
        [Parameter(Mandatory = $true, HelpMessage = "Path that the group will be created under.")]
        $Path,
        [Parameter(Mandatory = $true, HelpMessage = "Group category.")]
        $groupCategory,
        [Parameter(Mandatory = $true, HelpMessage = "Group scope.")]
        $groupScope
    )
    if (Get-ADGroup -Filter "Name -eq '$Name'") {
        Write-Output " [o] Group '$Name' already exists"
    } else {
        Write-Output " [ ] Creating group '$Name' in OU '$path'..."
        $group = (New-ADGroup -Name "$Name" -Description $description -Path $path -GroupScope $groupScope -GroupCategory Security)
        if ($?) {
            Write-Output " [o] Group '$Name' created"
        } else {
            Write-Output " [x] Failed to create group '$Name'!"
        }
        return $Group
    }
}


# Create a new user associated with this SRE
# ------------------------------------------
function New-SreUser {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Security Account Manager (SAM) account name of the user. Maximum 20 characters for backwards compatibility.")]
        $SamAccountName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of the user to be created.")]
        $Name,
        [Parameter(Mandatory = $true, HelpMessage = "Path that the user will be created under.")]
        $Path,
        [Parameter(Mandatory = $true, HelpMessage = "User password as a secure string.")]
        $PasswordSecureString
    )
    if (Get-ADUser -Filter "SamAccountName -eq '$SamAccountName'") {
        Write-Output " [o] User '$Name' ('$SamAccountName') already exists"
    } else {
        $principalName = "${SamAccountName}@${shmFqdn}"
        Write-Output " [ ] Creating user '$Name' ($SamAccountName)..."
        $user = (New-ADUser -Name "$Name" `
                            -UserPrincipalName $principalName `
                            -Path $path `
                            -SamAccountName $SamAccountName `
                            -DisplayName "$Name" `
                            -Description "$Name" `
                            -AccountPassword $passwordSecureString `
                            -Enabled $true `
                            -PasswordNeverExpires $true)
        if ($?) {
            Write-Output " [o] User '$Name' ($SamAccountName) created"
        } else {
            Write-Output " [x] Failed to create user '$Name' ($SamAccountName)!"
        }
        return $user
    }
}


# Add a user to a group associated with this SRE
# ----------------------------------------------
function Add-SreUserToGroup {
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


# Unserialise JSON and read into PSCustomObject
$groups = [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($groupsB64)) | ConvertFrom-Json
# $computerManagers = [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($computerManagersB64)) | ConvertFrom-Json
$serviceUsers = [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($serviceUsersB64)) | ConvertFrom-Json

# Create SRE Security Groups
foreach ($group in $groups.PSObject.Members) {
    if ($group.TypeNameOfValue -ne "System.Management.Automation.PSCustomObject") { continue }
    New-SreGroup -Name $group.Value.name -description $group.Value.description -Path $securityOuPath -GroupScope Global -GroupCategory Security
}

# Add SHM sysadmins group to the SRE sysadmins group
Add-SreUserToGroup -SamAccountName "$shmSystemAdministratorSgName" -GroupName $groups.systemAdministrators.name

# # Create SRE LDAP users and add them to the LDAP users group
# foreach ($user in $computerManagers.PSObject.Members) {
#     if ($user.TypeNameOfValue -ne "System.Management.Automation.PSCustomObject") { continue }
#     New-SreUser -SamAccountName "$($user.Value.samAccountName)" -Name "$($user.Value.name)" -Path $serviceOuPath -PasswordSecureString (ConvertTo-SecureString $user.Value.password -AsPlainText -Force)
#     Add-SreUserToGroup -SamAccountName "$($user.Value.samAccountName)" -GroupName $shmLdapUserSgName
# }

# Create SRE service accounts
foreach ($user in $serviceUsers.PSObject.Members) {
    if ($user.TypeNameOfValue -ne "System.Management.Automation.PSCustomObject") { continue }
    New-SreUser -SamAccountName "$($user.Value.samAccountName)" -Name "$($user.Value.name)" -Path $serviceOuPath -PasswordSecureString (ConvertTo-SecureString $user.Value.password -AsPlainText -Force)
}
