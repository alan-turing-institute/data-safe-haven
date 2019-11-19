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