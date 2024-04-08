param (
    [Parameter(Mandatory = $false, HelpMessage = "SRE name")]
    [ValidateNotNullOrEmpty()]
    [string]$SREName,
    [Parameter(Mandatory = $false, HelpMessage = "Usernames as base64-encoded string")]
    [ValidateNotNullOrEmpty()]
    [string]$UsernamesB64
)

# Find SRE security group
$SREGroup = Get-ADGroup -Filter "Name -eq 'Data Safe Haven SRE $SREName Users'" | Where-Object { $_.DistinguishedName -like '*Data Safe Haven Security Groups*' } | Select-Object -First 1
if (-not $SREGroup) {
    Write-Output "ERROR: No user group found on the domain controller for SRE '[green]$SREName[/]'."
}

# Load usernames
$Usernames = ([Text.Encoding]::Utf8.GetString([Convert]::FromBase64String($UsernamesB64))).Split()
if (-not $Usernames) {
    Write-Output "ERROR: No usernames provided to add to SRE '[green]$SREName[/]'."
}

# Add each user to the SRE group
if ($SREGroup -and $Usernames) {
    foreach ($Username in $Usernames) {
        Write-Output "INFO: Adding user '[green]$Username[/]' to group '[green]$($SREGroup.Name)[/]'."
        Add-ADGroupMember -Identity "$($SREGroup.Name)" -Members $Username
    }
}
