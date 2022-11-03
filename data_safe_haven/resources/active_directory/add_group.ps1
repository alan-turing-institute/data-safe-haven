param (
    [Parameter(Mandatory = $false, HelpMessage = "Name of group to create")]
    [ValidateNotNullOrEmpty()]
    [string]$GroupName,
    [Parameter(Mandatory = $false, HelpMessage = "OU path to create group under")]
    [ValidateNotNullOrEmpty()]
    [string]$OuPath
)

if (Get-ADGroup -Filter "Name -eq '$GroupName'" -SearchBase $OuPath -ErrorAction SilentlyContinue) {
    Write-Output "Group '$GroupName' already exists."
} else {
    try {
        New-ADGroup -Description "$GroupName" `
                    -GroupCategory "Security" `
                    -GroupScope "Global" `
                    -Name "$GroupName" `
                    -Path $OuPath `
                    -ErrorAction Stop
        Write-Output "Created group '$GroupName'."
    } catch {
        Write-Output "Failed to create group '$GroupName'."
    }
}
