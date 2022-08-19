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


# Create resource group if it does not exist
# ------------------------------------------
function Deploy-ResourceGroup {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy")]
        $Name,
        [Parameter(Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
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
        Add-LogMessage -Level InfoSuccess "Resource group '$Name' already exists"
    }
    return $resourceGroup
}
Export-ModuleMember -Function Deploy-ResourceGroup


# Attach an RBAC role to a principal
# ----------------------------------
function Deploy-RoleAssignment {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "ID of object that the role will be granted to")]
        [string]$ObjectId,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group containing the resource to apply the role over")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of role to be assigned")]
        [string]$RoleDefinitionName,
        [Parameter(Mandatory = $false, HelpMessage = "Type of resource to apply the role over")]
        [string]$ResourceType,
        [Parameter(Mandatory = $false, HelpMessage = "Name of resource account to apply the role over")]
        [string]$ResourceName
    )
    # Validate arguments
    if ([boolean]$ResourceType -ne [boolean]$ResourceName) {
        Add-LogMessage -Level Fatal "Failed to create role assignment, both or neither of ResourceType and ResourceName must be declared."
    }

    # Check if assignment exists
    Add-LogMessage -Level Info "Ensuring that role assignment for $ObjectId as $RoleDefinitionName over $($ResourceType ? $ResourceName : $ResourceGroupName) exists..."
    if ($ResourceType) {
        $Assignment = Get-AzRoleAssignment -ObjectId $ObjectId `
                                           -RoleDefinitionName $RoleDefinitionName `
                                           -ResourceGroupName $ResourceGroupName `
                                           -ResourceName $ResourceName `
                                           -ResourceType $ResourceType `
                                           -ErrorAction SilentlyContinue
    } else {
        $Assignment = Get-AzRoleAssignment -ObjectId $ObjectId `
                                           -RoleDefinitionName $RoleDefinitionName `
                                           -ResourceGroupName $ResourceGroupName `
                                           -ErrorAction SilentlyContinue
    }
    if ($Assignment) {
        Add-LogMessage -Level InfoSuccess "Role assignment already exists"
    } else {
        try {
            Add-LogMessage -Level Info "[ ] Creating role assignment"
            if ($ResourceType) {
                $Assignment = New-AzRoleAssignment -ObjectId $ObjectId `
                                                   -RoleDefinitionName $RoleDefinitionName `
                                                   -ResourceGroupName $ResourceGroupName `
                                                   -ResourceName $ResourceName `
                                                   -ResourceType $ResourceType `
                                                   -ErrorAction Stop
            } else {
                $Assignment = New-AzRoleAssignment -ObjectId $ObjectId `
                                                   -RoleDefinitionName $RoleDefinitionName `
                                                   -ResourceGroupName $ResourceGroupName `
                                                   -ErrorAction Stop
            }
            Add-LogMessage -Level Success "Successfully created role assignment"
        } catch {
            Add-LogMessage -Level Fatal "Failed to create role assignment" -Exception $_.Exception
        }
    }
    return $Assignment
}
Export-ModuleMember -Function Deploy-RoleAssignment


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


# Get the resource ID for a named resource
# ----------------------------------------
function Get-ResourcesInGroup {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Resource group to check for resources")]
        [string]$ResourceGroupName
    )
    return Get-AzResource | Where-Object { $_.ResourceGroupName -eq $ResourceGroupName }
}
Export-ModuleMember -Function Get-ResourcesInGroup


# Remove resource groups and the resources they contain
# -----------------------------------------------------
function Remove-AllResourceGroups {
    param(
        [Parameter(Mandatory = $false, HelpMessage = "Maximum number of iterations to attempt")]
        [int]$MaxAttempts = 10,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to remove")]
        [string[]]$ResourceGroupNames
    )
    for ($i = 0; $i -lt $MaxAttempts; $i++) {
        $ResourceGroups = Get-AzResourceGroup | Where-Object { $ResourceGroupNames.Contains($_.ResourceGroupName) }
        if (-not $ResourceGroups.Count) { return }
        Add-LogMessage -Level Info "Found $($ResourceGroups.Count) resource group(s) to remove..."
        # Schedule removal of existing resource groups
        $ResourceGroups | ForEach-Object { Remove-ResourceGroup -Name $_.ResourceGroupName -NoWait }
        $InitialNames = $ResourceGroups | ForEach-Object { $_.ResourceGroupName }
        # Wait for a minute and then check for current resource groups
        Start-Sleep 60
        $ResourceGroups = Get-AzResourceGroup | Where-Object { $ResourceGroupNames.Contains($_.ResourceGroupName) }
        # Output any successfully removed resource groups
        $FinalNames = $ResourceGroups | ForEach-Object { $_.ResourceGroupName }
        $InitialNames | Where-Object { -not $FinalNames.Contains($_) } | ForEach-Object {
            Add-LogMessage -Level Success "Removed resource group $_"
        }
    }
    Add-LogMessage -Level Fatal "Failed to remove all requested resource groups!"
}
Export-ModuleMember -Function Remove-AllResourceGroups


# Remove a resource group if it exists
# ------------------------------------
function Remove-ResourceGroup {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to remove")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Do not wait for the removal to complete")]
        [switch]$NoWait
    )
    $ResourceGroup = Get-AzResourceGroup -ResourceGroupName $Name
    Add-LogMessage -Level Info "Attempting to remove resource group '$Name'..."
    if ($NoWait.IsPresent) {
        if ($ResourceGroup.ResourceId) {
            $null = Remove-AzResourceGroup -ResourceId $ResourceGroup.ResourceId -Force -Confirm:$False -AsJob -ErrorAction SilentlyContinue
            $null = Get-AzResource | Where-Object { $_.ResourceGroupName -eq $Name } | Remove-AzResource -AsJob -ErrorAction SilentlyContinue
        }
    } else {
        try {
            $null = Remove-AzResourceGroup -ResourceId $ResourceGroup.ResourceId -Force -Confirm:$False -ErrorAction Stop
            Add-LogMessage -Level Success "Resource group removal succeeded"
        } catch {
            Add-LogMessage -Level Fatal "Resource group removal failed" -Exception $_.Exception
        }
    }
}
Export-ModuleMember -Function Remove-ResourceGroup
