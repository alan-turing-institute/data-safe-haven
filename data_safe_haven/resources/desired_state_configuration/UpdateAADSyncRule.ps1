Import-Module -Name "C:\Program Files\Microsoft Azure AD Sync\Bin\ADSync" -Force -ErrorAction Stop

# Create a new rule that is a copy of the default rule
$defaultRule = Get-ADSyncRule | Where-Object { $_.Name -eq "Out to AAD - User Join" }
$newRule = New-ADSyncRule  `
           -Name 'Out to AAD - User Join' `
           -Description $defaultRule.Description `
           -Direction 'Outbound' `
           -Precedence $defaultRule.Precedence `
           -PrecedenceAfter $defaultRule.PrecedenceAfter `
           -PrecedenceBefore $defaultRule.PrecedenceBefore `
           -SourceObjectType $defaultRule.SourceObjectType `
           -TargetObjectType $defaultRule.TargetObjectType `
           -Connector $defaultRule.Connector `
           -LinkType $defaultRule.LinkType `
           -SoftDeleteExpiryInterval $defaultRule.SoftDeleteExpiryInterval `
           -ImmutableTag '' `
           -EnablePasswordSync

# Copy all flow mappings except the usage location one
foreach ($flow in ($defaultRule.AttributeFlowMappings | Where-Object { $_.Destination -ne "usageLocation" })) {
    $params = @{
        Destination    = $flow.Destination
        FlowType       = $flow.FlowType
        ValueMergeType = $flow.ValueMergeType
    }
    if ($flow.Source) { $params["Source"] = $flow.Source }
    if ($flow.Expression) { $params["Expression"] = $flow.Expression }
    $null = Add-ADSyncAttributeFlowMapping -SynchronizationRule $newRule @params
}

# Set the usage location flow mapping manually
$null = Add-ADSyncAttributeFlowMapping -SynchronizationRule $newRule -Source @('c') -Destination 'usageLocation' -FlowType 'Direct' -ValueMergeType 'Update'

# Add appropriate scope and join conditions
$newRule.JoinFilter = $defaultRule.JoinFilter
$newRule.ScopeFilter = $defaultRule.ScopeFilter

# Remove the old rule and add the new one
$null = Remove-ADSyncRule -SynchronizationRule $defaultRule
Add-ADSyncRule -SynchronizationRule $newRule
