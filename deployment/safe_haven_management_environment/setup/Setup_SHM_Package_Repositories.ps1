param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId
)

Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Network -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureCompute -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureKeyVault -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureNetwork -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureResources -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureStorage -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Templates -Force -ErrorAction Stop


# Resolve the cloud init file, applying an allowlist if needed
# -----------------------------------------------------------
function Resolve-CloudInit {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of cloud-init template file")]
        [string]$CloudInitTemplateName,
        [Parameter(Mandatory = $false, HelpMessage = "Hashtable containing template parameters")]
        [System.Collections.IDictionary]$TemplateParameters
    )
    try {
        # Load template cloud-init file
        $CloudInitBasePath = Join-Path $PSScriptRoot ".." "cloud_init" -Resolve
        $CloudInitPath = Join-Path $CloudInitBasePath $CloudInitTemplateName -Resolve
        $CloudInitTemplate = Get-Content $CloudInitPath -Raw -ErrorAction Stop
        # Expand the template
        $CloudInitTemplate = Expand-CloudInitResources -Template $CloudInitTemplate -ResourcePath (Join-Path $CloudInitBasePath "resources")
        $CloudInitTemplate = Expand-CloudInitResources -Template $CloudInitTemplate -ResourcePath (Join-Path ".." ".." ".." "environment_configs" "package_lists")
        $CloudInitTemplate = Expand-MustacheTemplate -Template $CloudInitTemplate -Parameters $TemplateParameters
        return $CloudInitTemplate
    } catch {
        Add-LogMessage -Level Fatal "Failed to load cloud init file '$CloudInitPath'!" -Exception $_.Exception
    }
}


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmConfig -shmId $shmId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.subscriptionName -ErrorAction Stop



# Ensure that repository resource group exists
# --------------------------------------------
$null = Deploy-ResourceGroup -Name $config.repositories.rg -Location $config.location


# Get common objects
# ------------------
$bootDiagnosticsAccount = Deploy-StorageAccount -Name $config.storage.bootdiagnostics.accountName -ResourceGroupName $config.storage.bootdiagnostics.rg -Location $config.location
$vmAdminUsername = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.keyVault.secretNames.vmAdminUsername -DefaultValue "shm$($config.id)admin".ToLower() -AsPlaintext


# Iterate over tiers deploying requested package repositories in each case
# ------------------------------------------------------------------------
foreach ($tier in @("tier2", "tier3")) {
    # Get the virtual network for this tier and peer it to the SHM VNet
    $vnetConfig = $config.network["vnetRepositories${tier}"]
    $vnetRepository = Get-VirtualNetwork -Name $vnetConfig.name -ResourceGroupName $vnetConfig.rg
    Set-VnetPeering -Vnet1Name $vnetRepository.Name `
                    -Vnet1ResourceGroupName $vnetRepository.ResourceGroupName `
                    -Vnet1SubscriptionName $config.subscriptionName `
                    -Vnet2Name $config.network.vnet.name `
                    -Vnet2ResourceGroupName $config.network.vnet.rg `
                    -Vnet2SubscriptionName $config.subscriptionName

    # Deploy proxy servers if requested
    if ($config.repositories[$tier].proxies) {
        Add-LogMessage -Level Info "Deploying $tier package proxy server"
        $proxiesSubnet = Get-Subnet -Name $vnetConfig.subnets.proxies.name -VirtualNetworkName $vnetConfig.name -ResourceGroupName $vnetConfig.rg
        $vmConfig = $config.repositories[$tier].proxies.many
        # Construct the cloud-init file
        $config["temporary"] = @{
            adminPassword = $nexusAppAdminPassword
            tier          = [int]$tier.Replace("tier", "")
        }
        $cloudInitFileName = "cloud-init-package-proxy.mustache.yaml".ToLower()
        $CloudInitYaml = Resolve-CloudInit -CloudInitTemplateName $cloudInitFileName `
                                           -TemplateParameters $config
        # Deploy the VM
        $params = @{
            AdminPassword          = (Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $vmConfig.adminPasswordSecretName -DefaultLength 20)
            AdminUsername          = $vmAdminUsername
            BootDiagnosticsAccount = $bootDiagnosticsAccount
            CloudInitYaml          = $CloudInitYaml
            ImageSku               = "Ubuntu-latest"
            Location               = $config.location
            Name                   = $vmConfig.vmName
            OsDiskSizeGb           = $vmConfig.disks.os.sizeGb
            OsDiskType             = $vmConfig.disks.os.type
            PrivateIpAddress       = $vmConfig.ipAddress
            ResourceGroupName      = $config.repositories.rg
            Size                   = $vmConfig.vmSize
            Subnet                 = $proxiesSubnet
        }
        $null = Deploy-LinuxVirtualMachine @params | Start-VM -ForceRestart
    }

    # Deploy external mirrors if requested (this must come before the internal ones are deployed)
    if ($config.repositories[$tier].mirrorsExternal) {
        Add-LogMessage -Level Info "Deploying $tier external package mirrors"
        $mirrorsExternalSubnet = Get-Subnet -Name $vnetConfig.subnets.mirrorsExternal.name -VirtualNetworkName $vnetConfig.name -ResourceGroupName $vnetConfig.rg
        foreach ($SourceRepositoryName in $config.repositories[$tier].mirrorsExternal.Keys) {
            $vmConfig = $config.repositories[$tier].mirrorsExternal[$SourceRepositoryName]
            # Construct the cloud-init file
            $cloudInitFileName = "cloud-init-package-mirror-external-${SourceRepositoryName}.mustache.yaml".ToLower()
            $config["temporary"] = @{
                tier = $Tier
            }
            $CloudInitYaml = Resolve-CloudInit -CloudInitTemplateName $cloudInitFileName `
                                               -TemplateParameters $config
            # Deploy the data disk
            $dataDisk = Deploy-ManagedDisk -Name "$($vmConfig.vmName)-DATA-DISK" -SizeGB $vmConfig.disks.data.sizeGb -Type $vmConfig.disks.data.type -ResourceGroupName $config.repositories.rg -Location $config.location
            # Deploy the VM
            $params = @{
                AdminPassword          = (Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $vmConfig.adminPasswordSecretName -DefaultLength 20)
                AdminUsername          = $vmAdminUsername
                BootDiagnosticsAccount = $bootDiagnosticsAccount
                CloudInitYaml          = $CloudInitYaml
                DataDiskIds            = @($dataDisk.Id)
                ImageSku               = "Ubuntu-latest"
                Location               = $config.location
                Name                   = $vmConfig.vmName
                OsDiskSizeGb           = $vmConfig.disks.os.sizeGb
                OsDiskType             = $vmConfig.disks.os.type
                PrivateIpAddress       = $vmConfig.ipAddress
                ResourceGroupName      = $config.repositories.rg
                Size                   = $vmConfig.vmSize
                Subnet                 = $mirrorsExternalSubnet
            }
            $null = Deploy-LinuxVirtualMachine @params | Start-VM -ForceRestart
            # Extract the public key and save it for later use
            try {
                Add-LogMessage -Level Info "Extracting public SSH key to allow connections to internal mirrors"
                $result = Invoke-RemoteScript -VMName $vmConfig.vmName -ResourceGroupName $config.repositories.rg -Shell "UnixShell" -Script "cat /home/mirrordaemon/.ssh/id_rsa.pub | grep '^ssh'" -SuppressOutput
                $PublicKey = [string]($result.Value[0].Message -Split "`n" | Select-String "^ssh")
                $config.repositories[$tier].mirrorsInternal[$SourceRepositoryName]["externalMirrorPublicKey"] = $PublicKey
                Add-LogMessage -Level Success "Extracting public SSH key succeeded"
            } catch {
                Add-LogMessage -Level Fatal "Could not extract SSH public key" -Exception $_.Exception
            }
        }
    }

    # Deploy internal mirrors if requested (this must come after the external ones are deployed)
    if ($config.repositories[$tier].mirrorsInternal) {
        Add-LogMessage -Level Info "Deploying $tier internal package mirrors"
        $mirrorsInternalSubnet = Get-Subnet -Name $vnetConfig.subnets.mirrorsInternal.name -VirtualNetworkName $vnetConfig.name -ResourceGroupName $vnetConfig.rg
        foreach ($SourceRepositoryName in $config.repositories[$tier].mirrorsInternal.Keys) {
            $vmConfig = $config.repositories[$tier].mirrorsInternal[$SourceRepositoryName]
            # Construct the cloud-init file
            $config["temporary"] = @{
                externalMirrorPublicKey = $vmConfig["externalMirrorPublicKey"]
                tier                    = $Tier
            }
            $cloudInitFileName = "cloud-init-package-mirror-internal-${SourceRepositoryName}.mustache.yaml".ToLower()
            $CloudInitYaml = Resolve-CloudInit -CloudInitTemplateName $cloudInitFileName `
                                               -TemplateParameters $config
            # Deploy the data disk
            $dataDisk = Deploy-ManagedDisk -Name "$($vmConfig.vmName)-DATA-DISK" -SizeGB $vmConfig.disks.data.sizeGb -Type $vmConfig.disks.data.type -ResourceGroupName $config.repositories.rg -Location $config.location
            try {
                # Set temporary NSG rules to allow package installation during deployment
                Add-LogMessage -Level Info "Temporarily allowing outbound internet access from $privateIpAddress on ports 80, 443 and 3128 during deployment"
                $mirrorsInternalNsg = Get-AzNetworkSecurityGroup | Where-Object { $_.Id -eq $mirrorsInternalSubnet.NetworkSecurityGroup.Id }
                Add-NetworkSecurityGroupRule -Access Allow `
                                             -Description "Allow ports 80 (http), 443 (pip) and 3128 (pip) for installing software" `
                                             -DestinationAddressPrefix Internet `
                                             -DestinationPortRange @(80, 443, 3128) `
                                             -Direction Outbound `
                                             -Name "ConfigurationOutboundTemporary" `
                                             -NetworkSecurityGroup $mirrorsInternalNsg `
                                             -Priority 100 `
                                             -Protocol TCP `
                                             -SourceAddressPrefix $vmConfig.ipAddress `
                                             -SourcePortRange *
                # Deploy the VM
                $params = @{
                    AdminPassword          = (Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $vmConfig.adminPasswordSecretName -DefaultLength 20)
                    AdminUsername          = $vmAdminUsername
                    BootDiagnosticsAccount = $bootDiagnosticsAccount
                    CloudInitYaml          = $CloudInitYaml
                    DataDiskIds            = @($dataDisk.Id)
                    ImageSku               = "Ubuntu-latest"
                    Location               = $config.location
                    Name                   = $vmConfig.vmName
                    OsDiskSizeGb           = $vmConfig.disks.os.sizeGb
                    OsDiskType             = $vmConfig.disks.os.type
                    PrivateIpAddress       = $vmConfig.ipAddress
                    ResourceGroupName      = $config.repositories.rg
                    Size                   = $vmConfig.vmSize
                    Subnet                 = $mirrorsInternalSubnet
                }
                $null = Deploy-LinuxVirtualMachine @params | Start-VM -ForceRestart
            } finally {
                # Remove temporary NSG rules
                Add-LogMessage -Level Info "Disabling outbound internet access from $privateIpAddress..."
                $null = Remove-AzNetworkSecurityRuleConfig -Name "ConfigurationOutboundTemporary" -NetworkSecurityGroup $mirrorsInternalNsg
                $null = $mirrorsInternalNsg | Set-AzNetworkSecurityGroup
            }
            # Ensure that the fingerprint for this VM is registered with the corresponding external mirror
            Add-LogMessage -Level Info "Retrieving fingerprint for '$($vmConfig.vmName)'..."
            $result = Invoke-RemoteScript -VMName $vmConfig.vmName -ResourceGroupName $config.repositories.rg -Shell "UnixShell" -Script "ssh-keyscan 127.0.0.1 2> /dev/null"
            $internalFingerprint = $result.Value[0].Message -Split "`n" | Select-String "^127.0.0.1" | ForEach-Object { $_ -replace "127.0.0.1", $vmConfig.ipAddress }
            $externalVmName = $vmConfig.vmName.Replace("INTERNAL", "EXTERNAL")
            Add-LogMessage -Level Info "Registering fingerprint and IP address for '$($vmConfig.vmName)' with '$externalVmName'..."
            $null = Invoke-RemoteScript -VMName $externalVmName -ResourceGroupName $config.repositories.rg -Shell "UnixShell" -Script "/home/mirrordaemon/update_known_internal_mirrors.sh '$internalFingerprint' '$($vmConfig.ipAddress)'"
        }
    }
}

# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
