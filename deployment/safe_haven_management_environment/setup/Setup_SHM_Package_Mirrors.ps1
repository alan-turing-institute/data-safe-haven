param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Which tier of mirrors should be deployed")]
    [ValidateSet("2", "3")]
    [string]$tier
)

Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Compute -ErrorAction Stop
Import-Module Az.Network -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureCompute.psm1 -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureKeyVault -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureNetwork.psm1 -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureResources -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureStorage -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Networking -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Security -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Templates -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmConfig -shmId $shmId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.subscriptionName -ErrorAction Stop


# Ensure that package mirror and networking resource groups exist
# ---------------------------------------------------------------
$null = Deploy-ResourceGroup -Name $config.mirrors.rg -Location $config.location
$null = Deploy-ResourceGroup -Name $config.network.vnet.rg -Location $config.location


# Set up the VNet with subnets for internal and external package mirrors
# ----------------------------------------------------------------------
$mirrorConfig = $config.network.mirrorVnets["tier${tier}"]
$vnetPkgMirrors = Deploy-VirtualNetwork -Name $mirrorConfig.name -ResourceGroupName $config.network.vnet.rg -AddressPrefix $mirrorConfig.cidr -Location $config.location
$subnetExternal = Deploy-Subnet -Name $mirrorConfig.subnets.external.name -VirtualNetwork $vnetPkgMirrors -AddressPrefix $mirrorConfig.subnets.external.cidr
$subnetInternal = Deploy-Subnet -Name $mirrorConfig.subnets.internal.name -VirtualNetwork $vnetPkgMirrors -AddressPrefix $mirrorConfig.subnets.internal.cidr


# Peer mirror VNet to SHM VNet in order to allow it to route via the SHM firewall
# -------------------------------------------------------------------------------
Add-LogMessage -Level Info "Peering repository virtual network to SHM virtual network"
Set-VnetPeering -Vnet1Name $vnetPkgMirrors.Name `
                -Vnet1ResourceGroupName $vnetPkgMirrors.ResourceGroupName `
                -Vnet1SubscriptionName $config.subscriptionName `
                -Vnet2Name $config.network.vnet.name `
                -Vnet2ResourceGroupName $config.network.vnet.rg `
                -Vnet2SubscriptionName $config.subscriptionName


# Attach external subnet to SHM route table
# -----------------------------------------
Add-LogMessage -Level Info "[ ] Attaching external subnet to SHM route table"
$routeTable = Deploy-RouteTable -Name $config.firewall.routeTableName -ResourceGroupName $config.network.vnet.rg -Location $config.location
$vnetPkgMirrors = Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnetPkgMirrors -Name $subnetExternal.Name -AddressPrefix $subnetExternal.AddressPrefix -RouteTable $routeTable | Set-AzVirtualNetwork
if ($?) {
    Add-LogMessage -Level Success "Attached subnet '$($subnetExternal.Name)' to SHM route table."
} else {
    Add-LogMessage -Level Fatal "Failed to attach subnet '$($subnetExternal.Name)' to SHM route table!"
}


# Ensure that external package mirrors NSG exists with correct rules and attach it to the correct subnet
# ------------------------------------------------------------------------------------------------------
$nsgExternal = Deploy-NetworkSecurityGroup -Name $mirrorConfig.subnets.external.nsg.name -ResourceGroupName $config.network.vnet.rg -Location $config.location
# Get list of internal mirrors
$config["mirrorNsgs"] = [ordered]@{
    internalMirrorIps = @($subnetInternal.AddressPrefix)
}
$rule = $nsgExternal.SecurityRules | Where-Object { $_.Name -eq "AllowMirrorSynchronisationOutbound" }
if ($rule) {
    $config["mirrorNsgs"]["internalMirrorIps"] = ($rule.DestinationAddressPrefix + $config["mirrorNsgs"]["internalMirrorIps"]) | Sort | Get-Unique
}
# Expand rules and apply to external subnet
$rules = Get-JsonFromMustacheTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "network_rules" $mirrorConfig.subnets.external.nsg.rules) -Parameters $config -AsHashtable
$null = Set-NetworkSecurityGroupRules -NetworkSecurityGroup $nsgExternal -Rules $rules
$subnetExternal = Set-SubnetNetworkSecurityGroup -Subnet $subnetExternal -NetworkSecurityGroup $nsgExternal


# Ensure that internal package mirrors NSG exists with correct rules and attach it to the correct subnet
# ------------------------------------------------------------------------------------------------------
$nsgInternal = Deploy-NetworkSecurityGroup -Name $mirrorConfig.subnets.internal.nsg.name -ResourceGroupName $config.network.vnet.rg -Location $config.location
$rules = Get-JsonFromMustacheTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "network_rules" $mirrorConfig.subnets.internal.nsg.rules) -Parameters $config -AsHashtable
$null = Set-NetworkSecurityGroupRules -NetworkSecurityGroup $nsgInternal -Rules $rules
$subnetInternal = Set-SubnetNetworkSecurityGroup -Subnet $subnetInternal -NetworkSecurityGroup $nsgInternal


# Get common objects
# ------------------
$bootDiagnosticsAccount = Deploy-StorageAccount -Name $config.storage.bootdiagnostics.accountName -ResourceGroupName $config.storage.bootdiagnostics.rg -Location $config.location
$vmAdminUsername = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.keyVault.secretNames.vmAdminUsername -DefaultValue "shm$($config.id)admin".ToLower() -AsPlaintext


# Resolve the cloud init file, applying an allowlist if needed
# -----------------------------------------------------------
function Resolve-CloudInit {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Type of mirror to set up")]
        $MirrorType,
        [Parameter(Mandatory = $true, HelpMessage = "Whether this is an internal or external mirror")]
        [ValidateSet("Internal", "External")]
        $MirrorDirection,
        [Parameter(Mandatory = $true, HelpMessage = "Path to cloud init file")]
        $CloudInitPath,
        [Parameter(Mandatory = $true, HelpMessage = "Path to package allowlist (if any)")]
        $AllowlistPath
    )

    # Load template cloud-init file
    $cloudInitYaml = Get-Content $CloudInitPath -Raw -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Fatal "Failed to load cloud init file '$CloudInitPath'!"
    }

    # Add public SSH key from the external mirror as an allowed key on the internal
    $externalMirrorPublicKey = ""
    if ($MirrorDirection -eq "Internal") {
        $script = "
        #! /bin/bash
        cat /home/mirrordaemon/.ssh/id_rsa.pub | grep '^ssh'
        "
        $vmNameExternal = "$($MirrorType.ToUpper())-EXTERNAL-MIRROR-TIER-$tier"
        $result = Invoke-RemoteScript -VMName $vmNameExternal -ResourceGroupName $config.mirrors.rg -Shell "UnixShell" -Script $script -SuppressOutput
        Add-LogMessage -Level Success "Fetching ssh key from external package mirror succeeded"
        $externalMirrorPublicKey = [string]($result.Value[0].Message -Split "`n" | Select-String "^ssh")
    }

    # Populate initial package allowlist file defined in cloud init YAML
    $allowlist = Get-Content $AllowlistPath -Raw -ErrorVariable notExists -ErrorAction SilentlyContinue
    if (-Not $notExists) {
        $packagesBefore = "      # PACKAGE_ALLOWLIST"
        $packagesAfter = ""
        foreach ($package in $allowlist -split "`n") {
            $packagesAfter += "      $package`n"
        }
        $cloudInitYaml = $cloudInitYaml.Replace($packagesBefore, $packagesAfter)
    }

    # Expand the template with tier, NTP server and timezone
    $config["repositories"] = @{
        externalMirrorPublicKey = $externalMirrorPublicKey
        tier                    = $tier
    }
    return (Expand-MustacheTemplate -Template $cloudInitYaml -Parameters $config)
}


# Set up a single package mirror
# ------------------------------
function Deploy-PackageMirror {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of virtual machine to deploy")]
        $MirrorType,
        [Parameter(Mandatory = $true, HelpMessage = "Whether this is an internal or external mirror")]
        [ValidateSet("Internal", "External")]
        $MirrorDirection
    )
    # Load cloud-init file
    # --------------------
    $cloudInitPath = Join-Path $PSScriptRoot ".." "cloud_init" "cloud-init-mirror-${mirrorDirection}-${MirrorType}.mustache.yaml".ToLower()
    $fullMirrorType = "${MirrorType}".ToLower().Replace("cran", "r-cran").Replace("pypi", "python-pypi")
    $allowlistPath = Join-Path $PSScriptRoot ".." ".." ".." "environment_configs" "package_lists" "allowlist-full-${fullMirrorType}-tier${tier}.list".ToLower() # do not resolve this path as we have not tested whether it exists yet
    $cloudInitYaml = Resolve-CloudInit -MirrorType $MirrorType -MirrorDirection $MirrorDirection -CloudInitPath $cloudInitPath -AllowlistPath $allowlistPath

    # Construct IP address for this mirror
    # ------------------------------------
    if ($MirrorDirection -eq "Internal") {
        $subnet = $subnetInternal
    } else {
        $subnet = $subnetExternal
    }
    $privateIpAddress = $config.mirrors[$MirrorType]["tier${tier}"][$MirrorDirection].ipAddress

    # Check whether the VM already exists
    # -----------------------------------
    $vmName = $config.mirrors[$MirrorType]["tier${tier}"][$MirrorDirection].vmName
    $adminPasswordSecretName = $config.mirrors[$MirrorType]["tier${tier}"][$MirrorDirection].adminPasswordSecretName
    $null = Get-AzVM -Name $vmName -ResourceGroupName $config.mirrors.rg -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        # Deploy NIC and data disks
        # -------------------------
        $vmNic = Deploy-NetworkInterface -Name "$vmName-NIC" -ResourceGroupName $config.mirrors.rg -Subnet $subnet -PrivateIpAddress $privateIpAddress -Location $config.location
        $dataDisk = Deploy-ManagedDisk -Name "$vmName-DATA-DISK" -SizeGB $config.mirrors[$MirrorType]["tier${tier}"].diskSize -Type $config.mirrors.diskType -ResourceGroupName $config.mirrors.rg -Location $config.location
        $nsg = Get-AzNetworkSecurityGroup | Where-Object { $_.Id -eq $subnet.NetworkSecurityGroup.Id }

        # Deploy the VM with access to the internet for configuration
        # -----------------------------------------------------------
        try {
            # Set temporary NSG rules
            Add-LogMessage -Level Info "Temporarily allowing outbound internet access from $privateIpAddress on ports 80, 443 and 3128"
            Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsg `
                                         -Name "ConfigurationOutboundTemporary" `
                                         -Description "Allow ports 80 (http), 443 (pip) and 3128 (pip) for installing software" `
                                         -Priority 100 `
                                         -Direction Outbound `
                                         -Access Allow `
                                         -Protocol TCP `
                                         -SourceAddressPrefix $privateIpAddress `
                                         -SourcePortRange * `
                                         -DestinationAddressPrefix Internet `
                                         -DestinationPortRange 80, 443, 3128
            Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsg `
                                         -Name "VnetOutboundTemporary" `
                                         -Description "Block connections to the VNet" `
                                         -Priority 150 `
                                         -Direction Outbound `
                                         -Access Deny `
                                         -Protocol * `
                                         -SourceAddressPrefix $privateIpAddress `
                                         -SourcePortRange * `
                                         -DestinationAddressPrefix VirtualNetwork `
                                         -DestinationPortRange *
            # Deploy the VM
            $params = @{
                Name                   = $vmName
                Size                   = $config.mirrors.vmSize
                AdminPassword          = (Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $adminPasswordSecretName -DefaultLength 20)
                AdminUsername          = $vmAdminUsername
                BootDiagnosticsAccount = $bootDiagnosticsAccount
                CloudInitYaml          = $cloudInitYaml
                Location               = $config.location
                NicId                  = $vmNic.Id
                OsDiskType             = $config.mirrors.diskType
                ResourceGroupName      = $config.mirrors.rg
                ImageSku               = "Ubuntu-latest"
                DataDiskIds            = @($dataDisk.Id)
            }
            $null = Deploy-LinuxVirtualMachine @params
        } finally {
            # Remove temporary NSG rules
            Add-LogMessage -Level Info "Disabling outbound internet access from $privateIpAddress and restarting VM: '$vmName'..."
            $null = Remove-AzNetworkSecurityRuleConfig -Name "ConfigurationOutboundTemporary" -NetworkSecurityGroup $nsg
            $null = Remove-AzNetworkSecurityRuleConfig -Name "VnetOutboundTemporary" -NetworkSecurityGroup $nsg
            $null = $nsg | Set-AzNetworkSecurityGroup
            if ($?) {
                Add-LogMessage -Level Success "Configuring VM '$vmName' succeeded"
            } else {
                Add-LogMessage -Level Fatal "Configuring VM '$vmName' failed!"
            }
        }
        # Restart the VM
        Start-VM -Name $vmName -ResourceGroupName $config.mirrors.rg -ForceRestart


        # If we have deployed an internal mirror we need to let the external connect to it
        # --------------------------------------------------------------------------------
        if ($MirrorDirection -eq "Internal") {
            Add-LogMessage -Level Info "Ensuring that '$vmName' can accept connections from the external mirror..."
            # Get public key for internal server
            Add-LogMessage -Level Info "Retrieving public key for '$vmName'..."
            $script = "
            #! /bin/bash
            ssh-keyscan 127.0.0.1 2> /dev/null
            "
            $result = Invoke-RemoteScript -VMName $vmName -ResourceGroupName $config.mirrors.rg -Shell "UnixShell" -Script $script
            $internalFingerprint = $result.Value[0].Message -Split "`n" | Select-String "^127.0.0.1" | ForEach-Object { $_ -replace "127.0.0.1", "$privateIpAddress" }

            # Inform external server about the new internal server
            $externalVmName = $vmName.Replace("INTERNAL", "EXTERNAL")
            Add-LogMessage -Level Info "Uploading '$vmName' public key to '$externalVmName'..."
            $script = "
            #! /bin/bash
            echo 'Update known hosts on the external server to allow connections to the internal server...'
            mkdir -p ~mirrordaemon/.ssh
            echo '$internalFingerprint' >> ~mirrordaemon/.ssh/known_hosts
            ssh-keygen -H -f ~mirrordaemon/.ssh/known_hosts 2>&1
            chown mirrordaemon:mirrordaemon ~mirrordaemon/.ssh/known_hosts
            rm ~mirrordaemon/.ssh/known_hosts.old 2> /dev/null
            cat ~mirrordaemon/.ssh/known_hosts
            ls -alh ~mirrordaemon/.ssh/
            echo 'Update known IP addresses on the external server to schedule pushing to the internal server...'
            echo $privateIpAddress >> ~mirrordaemon/internal_mirror_ip_addresses.txt
            cp ~mirrordaemon/internal_mirror_ip_addresses.txt ~mirrordaemon/internal_mirror_ip_addresses.bak
            cat ~mirrordaemon/internal_mirror_ip_addresses.bak | sort | uniq > ~mirrordaemon/internal_mirror_ip_addresses.txt
            rm -f ~mirrordaemon/internal_mirror_ip_addresses.bak
            cat ~mirrordaemon/internal_mirror_ip_addresses.txt
            ls -alh ~mirrordaemon
            "
            $null = Invoke-RemoteScript -VMName $externalVmName -ResourceGroupName $config.mirrors.rg -Shell "UnixShell" -Script $script
        }
    } else {
        Add-LogMessage -Level InfoSuccess "Virtual machine '$vmName' already exists"
    }
}


# Set up package mirror
# ---------------------
foreach ($mirrorType in ($config.mirrors.Keys | Where-Object { $config.mirrors[$_] -isnot [string] })) {
    foreach ($mirrorDirection in ("External", "Internal")) {
        Deploy-PackageMirror -MirrorType $mirrorType -MirrorDirection $mirrorDirection
    }
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
