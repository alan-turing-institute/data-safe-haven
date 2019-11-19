function LogTemplateOutput($ResourceGroupName, $DeploymentName) {
    $operations = Get-AzResourceGroupDeploymentOperation -ResourceGroupName $ResourceGroupName -DeploymentName $DeploymentName
    foreach($operation in $operations) {
        $response = $operation.Properties.Response
        foreach ($status in $response.content.properties.instanceView.statuses) {
            Write-Host -ForegroundColor DarkCyan " [-] $($response.content.name): $($status.code)"
            Write-Host $status.message
        }
        foreach ($substatus in $response.content.properties.instanceView.substatuses) {
            Write-Host -ForegroundColor DarkCyan " [-] $($response.content.name): $($substatus.code)"
            Write-Host $substatus.message
        }
    }
}
Export-ModuleMember -Function LogTemplateOutput

# function Write-Log
# {
#     [CmdletBinding()]
#     Param (
#         [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
#         [ValidateNotNullOrEmpty()]
#         [Alias("LogContent")]
#         [string]$Message,
#         [Parameter(Mandatory=$false)]
#         [Alias('LogPath')]
#         [string]$Path='C:\Logs\PowerShellLog.log',
#         [Parameter(Mandatory=$false)]
#         [ValidateSet("Error","Warn","Info")]
#         [string]$Level="Info"
#     )
#     # If attempting to write to a log file in a folder/path that doesn't exist create the file including the path.
#     if (!(Test-Path $Path)) {
#         Write-Verbose "Creating $Path."
#         $NewLogFile = New-Item $Path -Force -ItemType File
#     }

#     # Format Date for our Log File
#     $FormattedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

#     # Write message to error, warning, or verbose pipeline and specify $LevelText
#     $FormattedMessage = "$FormattedDate $Message"
#     switch ($Level) {
#         'Error' {
#             Write-Host -ForegroundColor DarkRed "$FormattedMessage"
#             }
#         'Warn' {
#             Write-Host -ForegroundColor Yellow "$FormattedMessage"
#             }
#         'Info' {
#             Write-Host -ForegroundColor DarkCyan "$FormattedMessage"
#             }
#         }

#     # Write log entry to $Path
#     "$FormattedDate $LevelText $Message" | Out-File -FilePath $Path -Append
# }
# Export-ModuleMember -Function Write-Log