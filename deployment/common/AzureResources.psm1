Import-Module Az.Resources -ErrorAction Stop
Import-Module $PSScriptRoot/Logging -ErrorAction Stop


# Deploy an ARM template and log the output
# -----------------------------------------
function Deploy-ArmTemplate {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        [ValidateNotNullOrEmpty()]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Template parameters")]
        [ValidateNotNullOrEmpty()]
        [System.Collections.Hashtable]$TemplateParameters,
        [Parameter(Mandatory = $true, HelpMessage = "Path to template file")]
        [ValidateNotNullOrEmpty()]
        [string]$TemplatePath
    )
    $templateName = Split-Path -Path "$TemplatePath" -LeafBase
    # Note we must use inline parameters rather than -TemplateParameterObject in order to support securestring
    # Furthermore, using -SkipTemplateParameterPrompt will cause inline parameters to fail
    New-AzResourceGroupDeployment -DeploymentDebugLogLevel ResponseContent `
                                  -ErrorVariable templateErrors `
                                  -Name $templateName `
                                  -ResourceGroupName $ResourceGroupName `
                                  -TemplateFile $TemplatePath `
                                  -Verbose `
                                  @TemplateParameters
    $result = $?
    Add-DeploymentLogMessages -ResourceGroupName $ResourceGroupName -DeploymentName $templateName -ErrorDetails $templateErrors
    if ($result) {
        Add-LogMessage -Level Success "Template deployment '$templateName' succeeded"
    } else {
        Add-LogMessage -Level Fatal "Template deployment '$templateName' failed!"
    }
}
Export-ModuleMember -Function Deploy-ArmTemplate


# Get the resource ID for a named resource
# ----------------------------------------
function Get-ResourceGroupName {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Resource to obtain ID for")]
        [System.Object]$ResourceName
    )
    return Get-AzResource | Where-Object { $_.Name -eq $ResourceName } | ForEach-Object { $_.ResourceGroupName } | Select-Object -First 1
}
Export-ModuleMember -Function Get-ResourceGroupName


# Attach an RBAC role to a principal
# ----------------------------------
function Deploy-RoleAssignment {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "ID of object that the role will be assigned to")]
        [string]$ObjectId,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group containing the storage account")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of role to be assigned")]
        [string]$RoleDefinitionName,
        [Parameter(Mandatory = $true, HelpMessage = "Type of resource to apply the role to")]
        [string]$ResourceType,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource account to apply the role to")]
        [string]$ResourceName
    )
    # Check if assignment exists
    Add-LogMessage -Level Info "Ensuring that role assignment(s) for blob backup exist..."
    $Assignment = Get-AzRoleAssignment -ObjectId $ObjectId `
                                       -RoleDefinitionName $RoleDefinitionName `
                                       -ResourceGroupName $ResourceGroupName `
                                       -ResourceName $ResourceName `
                                       -ResourceType $ResourceType `
                                       -ErrorAction SilentlyContinue
    if ($Assignment) {
        Add-LogMessage -Level InfoSuccess "Role assignment(s) already exist"
    } else {
        try {
            Add-LogMessage -Level Info "[ ] Creating role assignment(s) for blob backup"
            $Assignment = New-AzRoleAssignment -ObjectId $ObjectId `
                                               -RoleDefinitionName $RoleDefinitionName `
                                               -ResourceGroupName $ResourceGroupName `
                                               -ResourceName $ResourceName `
                                               -ResourceType $ResourceType `
                                               -ErrorAction Stop
            Add-LogMessage -Level Success "Successfully created role assignment(s)"
        } catch {
            Add-LogMessage -Level Fatal "Failed to create role assignment(s)" -Exception $_.Exception
        }
    }
    return $Assignment
}
Export-ModuleMember -Function Deploy-RoleAssignment


# Get the resource ID for a named resource
# ----------------------------------------
function Get-ResourceId {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Resource to obtain ID for")]
        [System.Object]$ResourceName
    )
    return Get-AzResource | Where-Object { $_.Name -eq $ResourceName } | ForEach-Object { $_.ResourceId } | Select-Object -First 1
}
Export-ModuleMember -Function Get-ResourceId