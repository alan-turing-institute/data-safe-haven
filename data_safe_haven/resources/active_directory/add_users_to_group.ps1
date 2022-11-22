param (
    [Parameter(Mandatory = $false, HelpMessage = "SRE name")]
    [ValidateNotNullOrEmpty()]
    [string]$SREName,
    [Parameter(Mandatory = $false, HelpMessage = "Usernames as base64-encoded string")]
    [ValidateNotNullOrEmpty()]
    [string]$UsernamesB64
)

# Find SRE security group
$SREGroup = Get-ADGroup -Filter "Name -like '*SRE $SREName*'" | Where-Object { $_.DistinguishedName -like '*Data Safe Haven Security Groups*' } | Select-Object -First 1

# Load usernames
$Usernames = ([Text.Encoding]::Utf8.GetString([Convert]::FromBase64String($UsernamesB64))).Split()

# Add each user to the SRE group
if ($SREGroup -and $Usernames) {
    foreach ($Username in $Usernames) {
        Write-Output "INFO: Adding user '<fg=green>$Username</>' to group '<fg=green>$($SREGroup.Name)</>'"
        Add-ADGroupMember "$($SREGroup.Name)" $Username
    }
}
