Import-Module $PSScriptRoot/Logging.psm1 -Force


# Create resource group if it does not exist
# ------------------------------------------
function Deploy-ResourceGroup {
    param(
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Name of resource group to deploy")]
        $Name,
        [Parameter(Position = 1, Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
        $Location
    )
    Add-LogMessage -Level Info "Ensuring that resource group '$Name' exists..."
    $resourceGroup = Get-AzResourceGroup -Name $Name -Location $Location -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating resource group '$Name'"
        $resourceGroup = New-AzResourceGroup -Name $Name -Location $Location -Force
        if ($?) {
            Add-LogMessage -Level Success "Created resource group '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create resource group '$Name'!"
        }
    } else {
        Add-LogMessage -Level Success "Resource group '$Name' already exists"
    }
    return $resourceGroup
}
Export-ModuleMember -Function Deploy-ResourceGroup


# Create storage account if it does not exist
# ------------------------------------------
function Deploy-StorageAccount {
    param(
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Name of storage account to deploy")]
        $Name,
        [Parameter(Position = 1, Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        $ResourceGroupName,
        [Parameter(Position = 2, Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
        $Location
    )
    Add-LogMessage -Level Info "Ensuring that storage account '$Name' exists..."
    $storageAccount = Get-AzStorageAccount -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating storage account '$Name'"
        $storageAccount = New-AzStorageAccount -Name $Name -ResourceGroupName $ResourceGroupName -Location $Location -SkuName "Standard_LRS" -Kind "StorageV2"
        if ($?) {
            Add-LogMessage -Level Success "Created storage account '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create storage account '$Name'!"
        }
    } else {
        Add-LogMessage -Level Success "Storage account '$Name' already exists"
    }
    return $storageAccount
}
Export-ModuleMember -Function Deploy-StorageAccount


# Create storage container if it does not exist
# ------------------------------------------
function Deploy-StorageContainer {
    param(
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Name of storage container to deploy")]
        $Name,
        [Parameter(Position = 1, Mandatory = $true, HelpMessage = "Name of storage account to deploy into")]
        $StorageAccount
    )
    Add-LogMessage -Level Info "Ensuring that storage container '$Name' exists..."
    $storageContainer = Get-AzStorageContainer -Name $Name -Context $StorageAccount.Context -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating storage container '$Name' in storage account '$($StorageAccount.StorageAccountName)'"
        $storageContainer = New-AzStorageContainer -Name $Name -Context $StorageAccount.Context
        if ($?) {
            Add-LogMessage -Level Success "Created storage container"
        } else {
            Add-LogMessage -Level Failure "Failed to create storage container!"
            throw "Failed to create storage container '$Name' in storage account '$($StorageAccount.StorageAccountName)'!"
        }
    } else {
        Add-LogMessage -Level Success "Storage container '$Name' already exists in storage account '$($StorageAccount.StorageAccountName)'"
    }
    return $storageContainer
}
Export-ModuleMember -Function Deploy-StorageContainer


# Deploy an ARM template and log the output
# -----------------------------------------
function Deploy-ArmTemplate {
    param(
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Path to template file")]
        $TemplatePath,
        [Parameter(Position = 1, Mandatory = $true, HelpMessage = "Template parameters")]
        $Params,
        [Parameter(Position = 2, Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        $ResourceGroupName
    )
    $templateName = Split-Path -Path "$TemplatePath" -LeafBase
    New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -TemplateFile $TemplatePath @params -Verbose -DeploymentDebugLogLevel ResponseContent
    $result = $?
    Add-DeploymentLogMessages -ResourceGroupName $ResourceGroupName -DeploymentName $templateName
    if ($result) {
        Add-LogMessage -Level Success "Template deployment '$templateName' succeeded"
    } else {
        Add-LogMessage -Level Failure "Template deployment '$templateName' failed!"
        throw "Template deployment has failed for '$templateName'. Please check the error message above before re-running this script."
    }
}
Export-ModuleMember -Function Deploy-ArmTemplate


# Run remote Powershell script
# ----------------------------
function Invoke-LoggedRemotePowershell {
    param(
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Path to remote script")]
        $ScriptPath,
        [Parameter(Position = 1, Mandatory = $true, HelpMessage = "Name of VM to run on")]
        $VMName,
        [Parameter(Position = 2, Mandatory = $true, HelpMessage = "Name of resource group VM belongs to")]
        $ResourceGroupName,
        [Parameter(Position = 3, Mandatory = $false, HelpMessage = "(Optional) script parameters")]
        $Parameter = $null
    )
    if ($Parameter -eq $null) {
        $result = Invoke-AzVMRunCommand -Name $VMName -ResourceGroupName $ResourceGroupName -CommandId 'RunPowerShellScript' -ScriptPath $ScriptPath
        $success = $?
    } else {
        $result = Invoke-AzVMRunCommand -Name $VMName -ResourceGroupName $ResourceGroupName -CommandId 'RunPowerShellScript' -ScriptPath $ScriptPath -Parameter $Parameter
        $success = $?
    }
    Write-Output $result.Value
    $stdoutCode = ($result.Value[0].Code -split "/")[-1]
    $stderrCode = ($result.Value[1].Code -split "/")[-1]
    if ($success -and ($stdoutCode -eq "succeeded") -and ($stderrCode -eq "succeeded")) {
        Add-LogMessage -Level Success "Remote script execution succeeded"
    } else {
        Add-LogMessage -Level Failure "Remote script execution failed!"
        throw "Remote script execution has failed. Please check the error message above before re-running this script."
    }
}
Export-ModuleMember -Function Invoke-LoggedRemotePowershell