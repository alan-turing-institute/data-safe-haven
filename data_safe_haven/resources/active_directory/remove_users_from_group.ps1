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
        Write-Output "INFO: Removing user '<fg=green>$Username</>' from group '<fg=green>$($SREGroup.Name)</>'"
        Remove-ADGroupMember -Identity "$($SREGroup.Name)" -Members $Username
    }
}
