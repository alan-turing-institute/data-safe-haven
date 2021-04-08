# Add a message to the log
# ------------------------
function Add-LogMessage {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [ValidateSet("Error", "Warning", "Info", "Success", "Failure", "InfoSuccess", "Fatal")]
        [string]$Level = "Info",
        [Parameter(Mandatory = $false)]
        [Exception]$Exception
    )
    # Format date for logging
    $FormattedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    # Write message to error, warning, or info
    switch ($Level) {
        "Error" {
            Write-Host -ForegroundColor DarkRed "$FormattedDate [  ERROR]: $Message"
        }
        "Warning" {
            Write-Host -ForegroundColor DarkYellow "$FormattedDate [WARNING]: $Message"
        }
        "Info" {
            Write-Host -ForegroundColor DarkCyan "$FormattedDate [   INFO]: $Message"
        }
        "Success" {
            Write-Host -ForegroundColor DarkGreen "$FormattedDate [SUCCESS]: [`u{2714}] $Message"
        }
        "Failure" {
            Write-Host -ForegroundColor DarkRed "$FormattedDate [FAILURE]: [x] $Message"
        }
        "InfoSuccess" {
            Write-Host -ForegroundColor DarkCyan "$FormattedDate [SUCCESS]: [`u{2714}] $Message"
        }
        "Fatal" {
            Write-Host -ForegroundColor DarkRed "$FormattedDate [FAILURE]: [x] $Message"
            if ($Exception) {
                throw $Exception
            } else {
                throw "$Message"
            }
        }
    }
}
Export-ModuleMember -Function Add-LogMessage


# Add a message to the log
# ------------------------
function Add-DeploymentLogMessages {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        $ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of deployment to track")]
        $DeploymentName,
        [Parameter(Mandatory = $true, HelpMessage = "Error messages from template deployment")]
        $ErrorDetails
    )
    $operations = Get-AzResourceGroupDeploymentOperation -ResourceGroupName $ResourceGroupName -DeploymentName $DeploymentName
    foreach ($operation in $operations) {
        $response = $operation.Properties.Response
        foreach ($status in $response.content.Properties.instanceView.statuses) {
            Add-LogMessage -Level Info "$($response.content.name): $($status.code)"
            Write-Host $status.message
        }
        foreach ($substatus in $response.content.Properties.instanceView.substatuses) {
            Add-LogMessage -Level Info "$($response.content.name): $($substatus.code)"
            Write-Host $substatus.message
        }
    }
    if ($ErrorDetails) {
        foreach ($message in $ErrorDetails[0..2] ) {
            Add-LogMessage -Level Failure "$message"
        }
    }
}
Export-ModuleMember -Function Add-DeploymentLogMessages
