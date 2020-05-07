param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Specify a machine name to turn into an image. Ensure that the build script has completely finished before running this")]
    [string]$vmName
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../common/Security.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmFullConfig $shmId
$originalContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.dsvmImage.subscription


# Construct build VM parameters
# -----------------------------
$buildVmAdminUsername = Resolve-KeyVaultSecret -VaultName $config.dsvmImage.keyVault.name -SecretName $config.keyVault.secretNames.buildImageAdminUsername -defaultValue "dsvmbuildadmin"


# Setup image resource group if it does not already exist
# -------------------------------------------------------
$_ = Deploy-ResourceGroup -Name $config.dsvmImage.images.rg -Location $config.dsvmImage.location


# Look for this VM in the appropriate resource group
# --------------------------------------------------
$vm = Get-AzVM -Name $vmName -ResourceGroupName $config.dsvmImage.build.rg -ErrorVariable notExists -ErrorAction SilentlyContinue
if ($notExists) {
    Add-LogMessage -Level Error "Could not find a machine called '$vmName' in resource group $($config.dsvmImage.build.rg)"
    Add-LogMessage -Level Info "Available machines are:"
    foreach ($vm in Get-AzVM -ResourceGroupName $config.dsvmImage.build.rg) {
        Add-LogMessage -Level Info "  $($vm.Name)"
    }
    throw "Could not find a machine called '$vmName'!"
}


# Ensure that the VM is running
# -----------------------------
Enable-AzVM -Name $vmName -ResourceGroupName $config.dsvmImage.build.rg


# Deprovision the VM over SSH
# ---------------------------
Add-LogMessage -Level Info "Deprovisioning VM: $($vm.Name)..."
$publicIp = (Get-AzPublicIpAddress -ResourceGroupName $config.dsvmImage.build.rg | Where-Object { $_.Id -Like "*$($vm.Name)-NIC-PIP" }).IpAddress
Add-LogMessage -Level Info "... preparing to send deprovisioning command over SSH to: $publicIp..."
Add-LogMessage -Level Info "... the password for this account is in the '$($config.keyVault.secretNames.buildImageAdminPassword)' secret in the '$($config.dsvmImage.keyVault.Name)' key vault"
ssh -t ${buildVmAdminUsername}@${publicIp} 'sudo /installation/deprovision_vm.sh | sudo tee /installation/deprovision.log'


# Poll VM to see whether it has finished running
# ----------------------------------------------
Add-LogMessage -Level Info "Waiting for deprovisioning to finish..."
$progress = 0
$statuses = (Get-AzVM -Name $vm.Name -ResourceGroupName $config.dsvmImage.build.rg -Status).Statuses.Code
while (-Not $statuses.Contains("ProvisioningState/succeeded")) {
    $statuses = (Get-AzVM -Name $vm.Name -ResourceGroupName $config.dsvmImage.build.rg -Status).Statuses.Code
    $progress = [math]::min(100, $progress + 1)
    Write-Progress -Activity "Deprovisioning status" -Status "$($statuses[0]) $($statuses[1])" -PercentComplete $progress
    Start-Sleep 10
}


# Deallocate and generalize. Commands in Powershell are different from the Azure CLI https://docs.microsoft.com/en-us/azure/virtual-machines/windows/tutorial-custom-images
# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Add-LogMessage -Level Info "Deallocating and generalising VM: '$($vm.Name)'. This can take up to 20 minutes..."
$_ = Stop-AzVM -ResourceGroupName $config.dsvmImage.build.rg -Name $vm.Name -Force
Add-LogMessage -Level Info "VM is stopped"
$_ = Set-AzVM -ResourceGroupName $config.dsvmImage.build.rg -Name $vm.Name -Generalized
Add-LogMessage -Level Info "VM is generalized"


# Create an image from the deallocated VM
# ---------------------------------------
$imageName = "Image$($vm.Name -replace 'Candidate', '')"
$vm = Get-AzVM -Name $vm.Name -ResourceGroupName $config.dsvmImage.build.rg
$imageConfig = New-AzImageConfig -Location $config.dsvmImage.location -SourceVirtualMachineId $vm.ID
$_ = New-AzImage -Image $imageConfig -ImageName $imageName -ResourceGroupName $config.dsvmImage.images.rg

# If the image has been successfully created then remove build artifacts
$image = Get-AzResource -ResourceType Microsoft.Compute/images -Name $imageName
if ($image) {
    Add-LogMessage -Level Info "Removing residual artifacts of the build process from $($config.dsvmImage.build.rg)..."
    Add-LogMessage -Level Info "... virtual machine: $vmName"
    $_ = Remove-AzVM -Name $vmName -ResourceGroupName $config.dsvmImage.build.rg -Force
    Add-LogMessage -Level Info "... hard disk: $vmName-OS-DISK"
    $_ = Remove-AzDisk -DiskName $vmName-OS-DISK -ResourceGroupName $config.dsvmImage.build.rg -Force
    Add-LogMessage -Level Info "... network card: $vmName-NIC"
    $_ = Remove-AzNetworkInterface -Name $vmName-NIC -ResourceGroupName $config.dsvmImage.build.rg -Force
    Add-LogMessage -Level Info "... public IP address: $vmName-NIC-PIP"
    $_ = Remove-AzPublicIpAddress -Name $vmName-NIC-PIP -ResourceGroupName $config.dsvmImage.build.rg -Force
} else {
    Add-LogMessage -Level Fatal "Image '$imageName' could not be found!"
}
Add-LogMessage -Level Info "Finished creating image $imageName"


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext
