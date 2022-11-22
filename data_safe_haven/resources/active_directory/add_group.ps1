param (
    [Parameter(Mandatory = $false, HelpMessage = "Name of group to create")]
    [ValidateNotNullOrEmpty()]
    [string]$GroupName,
    [Parameter(Mandatory = $false, HelpMessage = "OU path to create group under")]
    [ValidateNotNullOrEmpty()]
    [string]$OuPath
)

if (Get-ADGroup -Filter "Name -eq '$GroupName'" -SearchBase $OuPath -ErrorAction SilentlyContinue) {
    Write-Output "INFO: Group <fg=green>'$GroupName'</> already exists."
} else {
    try {
        New-ADGroup -Description "$GroupName" `
                    -GroupCategory "Security" `
                    -GroupScope "Global" `
                    -Name "$GroupName" `
                    -Path $OuPath `
                    -ErrorAction Stop
        Write-Output "INFO: Created group <fg=green>'$GroupName'</>."
    } catch {
        Write-Output "ERROR: Failed to create group <fg=green>'$GroupName'</>."
    }
}
