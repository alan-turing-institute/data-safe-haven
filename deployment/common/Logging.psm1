# Write coloured messages using the Information stream
# Adapted from https://blog.kieranties.com/2018/03/26/write-information-with-colours
# ----------------------------------------------------------------------------------
function Write-InformationColoured {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Object]$MessageData,
        [ConsoleColor]$ForegroundColour = $Host.UI.RawUI.ForegroundColor, # Make sure we use the current colours by default
        [ConsoleColor]$BackgroundColour = $Host.UI.RawUI.BackgroundColor,
        [Switch]$NoNewline
    )

    # Construct a coloured message
    $msg = [System.Management.Automation.HostInformationMessage]@{
        Message         = $MessageData
        ForegroundColor = $ForegroundColour
        BackgroundColor = $BackgroundColour
        NoNewline       = $NoNewline.IsPresent
    }

    # Write to the information stream
    # See https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_output_streams?view=powershell-7.2
    Write-Information $msg
}


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
            Write-InformationColoured -ForegroundColour DarkRed "$FormattedDate [  ERROR]: $Message"
        }
        "Warning" {
            Write-InformationColoured -ForegroundColour DarkYellow "$FormattedDate [WARNING]: $Message"
        }
        "Info" {
            Write-InformationColoured -ForegroundColour DarkCyan "$FormattedDate [   INFO]: $Message"
        }
        "Success" {
            Write-InformationColoured -ForegroundColour DarkGreen "$FormattedDate [SUCCESS]: [`u{2714}] $Message"
        }
        "Failure" {
            Write-InformationColoured -ForegroundColour DarkRed "$FormattedDate [FAILURE]: [x] $Message"
        }
        "InfoSuccess" {
            Write-InformationColoured -ForegroundColour DarkCyan "$FormattedDate [SUCCESS]: [`u{2714}] $Message"
        }
        "Fatal" {
            Write-InformationColoured -ForegroundColour DarkRed "$FormattedDate [FAILURE]: [x] $Message"
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
            Write-Information $status.message
        }
        foreach ($substatus in $response.content.Properties.instanceView.substatuses) {
            Add-LogMessage -Level Info "$($response.content.name): $($substatus.code)"
            Write-Information $substatus.message
        }
    }
    if ($ErrorDetails) {
        foreach ($message in $ErrorDetails[0..2] ) {
            Add-LogMessage -Level Failure "$message"
        }
    }
}
Export-ModuleMember -Function Add-DeploymentLogMessages
