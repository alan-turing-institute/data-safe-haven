# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# Fror details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [Parameter(HelpMessage = "Name of security group that will contain SHM sysadmins")]
    [ValidateNotNullOrEmpty()]
    [String]$ShmSystemAdministratorSgName,
    [Parameter(HelpMessage = "Base64-encoded group details")]
    [ValidateNotNullOrEmpty()]
    [String]$GroupsB64,
    [Parameter(HelpMessage = "LDAP OU that SRE security groups belong to")]
    [ValidateNotNullOrEmpty()]
    [String]$SecurityOuPath,
    [Parameter(HelpMessage = "LDAP OU that SRE service accounts belong to")]
    [ValidateNotNullOrEmpty()]
    [String]$ServiceOuPath,
    [Parameter(HelpMessage = "Base64-encoded service user details")]
    [ValidateNotNullOrEmpty()]
    [String]$ServiceUsersB64
)

# Create a new security group
function New-ActiveDirectoryGroup {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of the group to be created")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Description of the group to be created.")]
        [string]$Description,
        [Parameter(Mandatory = $true, HelpMessage = "Path that the group will be created under.")]
        [string]$Path,
        [Parameter(Mandatory = $true, HelpMessage = "Group category.")]
        [string]$GroupCategory,
        [Parameter(Mandatory = $true, HelpMessage = "Group scope.")]
        [string]$GroupScope
    )
    if (Get-ADGroup -Filter "Name -eq '$Name'") {
        Write-Output " [o] Group '$Name' already exists"
    } else {
        Write-Output " [ ] Creating group '$Name' in OU '$Path'..."
        New-ADGroup -Description $Description `
                    -GroupCategory $GroupCategory `
                    -GroupScope $GroupScope `
                    -Name "$Name" `
                    -Path $Path
        if ($?) {
            Write-Output " [o] Group '$Name' created"
        } else {
            Write-Output " [x] Failed to create group '$Name'!"
        }
    }
}

# Create a new user
function New-ActiveDirectoryUser {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of the user to be created.")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "User password as a secure string.")]
        [securestring]$PasswordSecureString,
        [Parameter(Mandatory = $true, HelpMessage = "Path that the user will be created under.")]
        [string]$Path,
        [Parameter(Mandatory = $true, HelpMessage = "Security Account Manager (SAM) account name of the user. Maximum 20 characters for backwards compatibility.")]
        [string]$SamAccountName
    )
    if (Get-ADUser -Filter "SamAccountName -eq '$SamAccountName'") {
        Write-Output " [o] User '$Name' ('$SamAccountName') already exists"
    } else {
        $UserPrincipalName = "${SamAccountName}@${shmFqdn}"
        Write-Output " [ ] Creating user '$Name' ($SamAccountName)..."
        New-ADUser -AccountPassword $PasswordSecureString `
                   -Description "$Name" `
                   -DisplayName "$Name" `
                   -Enabled $true `
                   -Name "$Name" `
                   -PasswordNeverExpires $true `
                   -Path $path `
                   -UserPrincipalName $UserPrincipalName `
                   -SamAccountName $SamAccountName
        if ($?) {
            Write-Output " [o] User '$Name' ($SamAccountName) created"
        } else {
            Write-Output " [x] Failed to create user '$Name' ($SamAccountName)!"
        }
    }
}


# Add a user to a group
function Add-ActiveDirectoryAccountToGroup {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of the group that the user or group will be added to.")]
        [string]$GroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Security Account Manager (SAM) account name of the Active Directory account.")]
        [string]$SamAccountName
    )
    $Account = Get-ADObject -Filter "SamAccountName -eq '$SamAccountName'"
    # Note that Get-ADGroupMember suffers from this bug: https://docs.microsoft.com/en-us/troubleshoot/windows-server/identity/get-adgroupmember-error-remote-forest-members
    if (Get-ADGroup -Identity "$GroupName" -Properties Members | Select-Object -ExpandProperty Members | Where-Object { $_ -eq $Account.DistinguishedName }) {
        Write-Output " [o] Account '$SamAccountName' is already a member of '$GroupName'"
    } else {
        Write-Output " [ ] Adding '$SamAccountName' to group '$GroupName'..."
        Add-ADGroupMember -Identity "$GroupName" -Members $Account.ObjectGUID
        if ($?) {
            Write-Output " [o] Account '$SamAccountName' was added to '$GroupName'"
        } else {
            Write-Output " [x] Account '$SamAccountName' could not be added to '$GroupName'!"
        }
    }
}


# Unserialise JSON and read into PSCustomObject
# ---------------------------------------------
$Groups = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($GroupsB64)) | ConvertFrom-Json
$ServiceUsers = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($ServiceUsersB64)) | ConvertFrom-Json


# Create SRE security groups
# --------------------------
foreach ($Group in $Groups.PSObject.Members) {
    if ($Group.TypeNameOfValue -ne "System.Management.Automation.PSCustomObject") { continue }
    New-ActiveDirectoryGroup -Description $Group.Value.description `
                             -GroupCategory "Security" `
                             -GroupScope "Global" `
                             -Name $Group.Value.name `
                             -Path $SecurityOuPath
}


# Add SHM sysadmins group to the SRE sysadmins group
# --------------------------------------------------
Add-ActiveDirectoryAccountToGroup -SamAccountName "$ShmSystemAdministratorSgName" -GroupName $Groups.systemAdministrators.name


# Create SRE service accounts
# ---------------------------
foreach ($ServiceUser in $ServiceUsers.PSObject.Members) {
    if ($ServiceUser.TypeNameOfValue -ne "System.Management.Automation.PSCustomObject") { continue }
    New-ActiveDirectoryUser -Name "$($ServiceUser.Value.name)" `
                            -PasswordSecureString (ConvertTo-SecureString $ServiceUser.Value.password -AsPlainText -Force) `
                            -Path $ServiceOuPath `
                            -SamAccountName "$($ServiceUser.Value.samAccountName)"
}
