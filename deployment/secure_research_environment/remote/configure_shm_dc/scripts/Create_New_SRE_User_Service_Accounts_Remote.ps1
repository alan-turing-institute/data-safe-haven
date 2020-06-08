# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# Fror details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [String]$shmLdapUserSgName,
    [String]$shmSystemAdministratorSgName,
    [String]$groupsB64,
    [String]$ldapUsersB64,
    [String]$researchUsersB64,
    [String]$serviceUsersB64,
    [String]$researchUserOuPath,
    [String]$securityOuPath,
    [String]$serviceOuPath
)

function New-SreGroup($name, $description, $path, $groupCategory, $groupScope) {
    if (Get-ADGroup -Filter "Name -eq '$name'") {
        Write-Output " [o] Group '$name' already exists"
    } else {
        Write-Output " [ ] Creating group '$name' in OU '$serviceOuPath'..."
        $group = (New-ADGroup -Name "$name" -Description $description -Path $path -GroupScope $groupScope -GroupCategory Security)
        if ($?) {
            Write-Output " [o] Group '$name' created"
        } else {
            Write-Output " [x] Failed to create group '$name'!"
        }
        return $group
    }
}

function New-SreUser($samAccountName, $name, $path, $passwordSecureString) {
    if (Get-ADUser -Filter "SamAccountName -eq '$samAccountName'") {
        Write-Output " [o] User '$name' ('$samAccountName') already exists"
    } else {
        $principalName = $samAccountName + "@" + $shmFqdn;
        Write-Output " [ ] Creating user '$name' ($samAccountName)..."
        $user = (New-ADUser -Name "$name" `
                            -UserPrincipalName $principalName `
                            -Path $path `
                            -SamAccountName $samAccountName `
                            -DisplayName "$name" `
                            -Description "$name" `
                            -AccountPassword $passwordSecureString `
                            -Enabled $true `
                            -PasswordNeverExpires $true)
        if ($?) {
            Write-Output " [o] User '$name' ($samAccountName) created"
        } else {
            Write-Output " [x] Failed to create user '$name' ($samAccountName)!"
        }
        return $user
    }
}

function Add-SreUserToGroup($name, $samAccountName, $groupName) {
    if ((Get-ADGroupMember -Identity $groupName | Where-Object { $_.SamAccountName -eq "$samAccountName" })) {
        Write-Output " [o] User '$name' ('$samAccountName') is already a member of '$groupName'"
    } else {
        Write-Output " [ ] Adding '$samAccountName)' user to group '$groupName'"
        Add-ADGroupMember -Identity "$groupName" -Members "$samAccountName"
        if ($?) {
            Write-Output " [o] User '$name' ('$samAccountName') was added to '$groupName'"
        } else {
            Write-Output " [x] User '$name' ('$samAccountName') could not be added to '$groupName'!"
        }
        return $user
    }
}

# Unserialise JSON and read into PSCustomObject
$groups = [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($groupsB64)) | ConvertFrom-Json
$ldapUsers = [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($ldapUsersB64)) | ConvertFrom-Json
$researchUsers = [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($researchUsersB64)) | ConvertFrom-Json
$serviceUsers = [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($serviceUsersB64)) | ConvertFrom-Json

# Create SRE Security Groups
$researchUserSgName = $null
foreach ($group in $groups.PSObject.Members) {
    if ($group.TypeNameOfValue -ne "System.Management.Automation.PSCustomObject") { continue }
    New-SreGroup -name $group.Value.name -description $group.Value.description -Path $securityOuPath -GroupScope Global -GroupCategory Security
}

# Add SHM sysadmins group to the SRE sysadmins group
Add-SreUserToGroup -samAccountName "$shmSystemAdministratorSgName" -name "$shmSystemAdministratorSgName" -groupName $groups.systemAdministrators.name

# Create LDAP users for SRE and add them to the LDAP users SG
foreach ($user in $ldapUsers.PSObject.Members) {
    if ($user.TypeNameOfValue -ne "System.Management.Automation.PSCustomObject") { continue }
    New-SreUser -samAccountName "$($user.Value.samAccountName)" -name "$($user.Value.name)" -path $serviceOuPath -passwordSecureString (ConvertTo-SecureString $user.Value.password -AsPlainText -Force)
    Add-SreUserToGroup -samAccountName "$($user.Value.samAccountName)" -name "$($user.Value.name)" -groupName $shmLdapUserSgName
}

# Create service accounts for SRE
foreach ($user in $serviceUsers.PSObject.Members) {
    if ($user.TypeNameOfValue -ne "System.Management.Automation.PSCustomObject") { continue }
    New-SreUser -samAccountName "$($user.Value.samAccountName)" -name "$($user.Value.name)" -path $serviceOuPath -passwordSecureString (ConvertTo-SecureString $user.Value.password -AsPlainText -Force)
}

# Create research users for SRE and add them to the researchers SG
foreach ($user in $researchUsers.PSObject.Members) {
    if ($user.TypeNameOfValue -ne "System.Management.Automation.PSCustomObject") { continue }
    New-SreUser -samAccountName "$($user.Value.samAccountName)" -name "$($user.Value.name)" -path $researchUserOuPath -passwordSecureString (ConvertTo-SecureString $user.Value.password -AsPlainText -Force)
    Add-SreUserToGroup -samAccountName "$($user.Value.samAccountName)" -name "$($user.Value.name)" -groupName $groups.researchUsers.name
}
