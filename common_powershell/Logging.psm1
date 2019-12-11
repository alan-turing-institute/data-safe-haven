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


function LogMessage {
    Param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,
        [Parameter(Mandatory=$false)]
        [ValidateSet("Error", "Warning", "Info", "Success", "Failure")]
        [string]$Level="Info"
    )
    # Format date for logging
    $FormattedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    # Write message to error, warning, or info
    switch ($Level) {
        "Error" {
            Write-Host -ForegroundColor DarkRed "$FormattedDate   ERROR: $Message"
        }
        "Warning" {
            Write-Host -ForegroundColor DarkYellow "$FormattedDate WARNING: $Message"
        }
        "Info" {
            Write-Host -ForegroundColor DarkCyan "$FormattedDate    INFO: $Message"
        }
        "Success" {
            Write-Host -ForegroundColor DarkGreen "$FormattedDate SUCCESS: [o] $Message"
        }
        "Failure" {
            Write-Host -ForegroundColor DarkRed "$FormattedDate FAILURE: [x] $Message"
        }
    }
}
Export-ModuleMember -Function LogMessage