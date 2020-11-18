param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Position = 1, Mandatory = $true, HelpMessage = "Which tier of mirrors should be deployed")]
    [ValidateSet("2", "3")]
    [string]$tier
)

Import-Module Az -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureStorage -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Security -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmFullConfig $shmId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.subscriptionName


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


# Set up the NSG for external package mirrors
# -------------------------------------------
$nsgExternal = Deploy-NetworkSecurityGroup -Name $mirrorConfig.subnets.external.nsg.name -ResourceGroupName $config.network.vnet.rg -Location $config.location
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsgExternal `
                             -Name "IgnoreInboundRulesBelowHere" `
                             -Description "Deny all other inbound" `
                             -Priority 3000 `
                             -Direction Inbound `
                             -Access Deny `
                             -Protocol * `
                             -SourceAddressPrefix * `
                             -SourcePortRange * `
                             -DestinationAddressPrefix * `
                             -DestinationPortRange *
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsgExternal `
                             -Name "UpdateFromInternet" `
                             -Description "Allow ports 443 (https) and 873 (unencrypted rsync) for updating mirrors" `
                             -Priority 300 `
                             -Direction Outbound `
                             -Access Allow `
                             -Protocol TCP `
                             -SourceAddressPrefix $subnetExternal.AddressPrefix `
                             -SourcePortRange * `
                             -DestinationAddressPrefix Internet `
                             -DestinationPortRange 443, 873
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsgExternal `
                             -Name "IgnoreOutboundRulesBelowHere" `
                             -Description "Deny all other outbound" `
                             -Priority 3000 `
                             -Direction Outbound `
                             -Access Deny `
                             -Protocol * `
                             -SourceAddressPrefix * `
                             -SourcePortRange * `
                             -DestinationAddressPrefix * `
                             -DestinationPortRange *
# Create or update external mirror rule
$destinationAddressPrefix = @($subnetInternal.AddressPrefix)
$rule = $nsgExternal.SecurityRules | Where-Object { $_.Name -eq "RsyncToInternal" }
if ($rule) {
    $destinationAddressPrefix = ($rule.DestinationAddressPrefix + $destinationAddressPrefix) | Sort | Get-Unique
}
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsgExternal -VerboseLogging `
                             -Name "RsyncToInternal" `
                             -Description "Allow ports 22 and 873 for rsync" `
                             -Priority 400 `
                             -Direction Outbound `
                             -Access Allow `
                             -Protocol TCP `
                             -SourceAddressPrefix $subnetExternal.AddressPrefix `
                             -SourcePortRange * `
                             -DestinationAddressPrefix $destinationAddressPrefix `
                             -DestinationPortRange 22, 873
$subnetExternal = Set-SubnetNetworkSecurityGroup -Subnet $subnetExternal -NetworkSecurityGroup $nsgExternal -VirtualNetwork $vnetPkgMirrors
if ($?) {
    Add-LogMessage -Level Success "Configuring NSG '$($mirrorConfig.subnets.external.nsg.name)' succeeded"
} else {
    Add-LogMessage -Level Fatal "Configuring NSG '$($mirrorConfig.subnets.external.nsg.name)' failed!"
}


# Set up the NSG for internal package mirrors
# -------------------------------------------
$nsgInternal = Deploy-NetworkSecurityGroup -Name $mirrorConfig.subnets.internal.nsg.name -ResourceGroupName $config.network.vnet.rg -Location $config.location
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsgInternal `
                             -Name "RsyncFromExternal" `
                             -Description "Allow ports 22 and 873 for rsync" `
                             -Priority 200 `
                             -Direction Inbound `
                             -Access Allow `
                             -Protocol TCP `
                             -SourceAddressPrefix $subnetExternal.AddressPrefix `
                             -SourcePortRange * `
                             -DestinationAddressPrefix * `
                             -DestinationPortRange 22, 873
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsgInternal `
                             -Name "MirrorRequestsFromVMs" `
                             -Description "Allow ports 80 (http), 443 (pip) and 3128 (pip) for webservices" `
                             -Priority 300 `
                             -Direction Inbound `
                             -Access Allow `
                             -Protocol TCP `
                             -SourceAddressPrefix VirtualNetwork `
                             -SourcePortRange * `
                             -DestinationAddressPrefix * `
                             -DestinationPortRange 80, 443, 3128
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsgInternal `
                             -Name "IgnoreInboundRulesBelowHere" `
                             -Description "Deny all other inbound" `
                             -Priority 3000 `
                             -Direction Inbound `
                             -Access Deny `
                             -Protocol * `
                             -SourceAddressPrefix * `
                             -SourcePortRange * `
                             -DestinationAddressPrefix * `
                             -DestinationPortRange *
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsgInternal `
                             -Name "IgnoreOutboundRulesBelowHere" `
                             -Description "Deny all other outbound" `
                             -Priority 3000 `
                             -Direction Outbound `
                             -Access Deny `
                             -Protocol * `
                             -SourceAddressPrefix * `
                             -SourcePortRange * `
                             -DestinationAddressPrefix * `
                             -DestinationPortRange *
$subnetInternal = Set-SubnetNetworkSecurityGroup -Subnet $subnetInternal -NetworkSecurityGroup $nsgInternal -VirtualNetwork $vnetPkgMirrors
if ($?) {
    Add-LogMessage -Level Success "Configuring NSG '$($config.network.mirrorVnets.subnets.internal.nsg.name)' succeeded"
} else {
    Add-LogMessage -Level Fatal "Configuring NSG '$($config.network.mirrorVnets.subnets.internal.nsg.name)' failed!"
}


# Get common objects
# ------------------
$bootDiagnosticsAccount = Deploy-StorageAccount -Name $config.storage.bootdiagnostics.accountName -ResourceGroupName $config.storage.bootdiagnostics.rg -Location $config.location
$vmAdminUsername = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.keyVault.secretNames.vmAdminUsername -DefaultValue "shm$($config.id)admin".ToLower()


# Resolve the cloud init file, applying a whitelist if needed
# -----------------------------------------------------------
function Resolve-CloudInit {
    param(
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Type of mirror to set up")]
        $MirrorType,
        [Parameter(Position = 1, Mandatory = $true, HelpMessage = "Whether this is an internal or external mirror")]
        [ValidateSet("Internal", "External")]
        $MirrorDirection,
        [Parameter(Position = 2, Mandatory = $true, HelpMessage = "Path to cloud init file")]
        $CloudInitPath,
        [Parameter(Position = 3, Mandatory = $true, HelpMessage = "Path to package whitelist (if any)")]
        $WhitelistPath
    )

    # Load template cloud-init file
    $cloudInitYaml = Get-Content $CloudInitPath -Raw -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Fatal "Failed to load cloud init file '$CloudInitPath'!"
    }

    # Add public SSH key from the external mirror as an allowed key on the internal
    if ($MirrorDirection -eq "Internal") {
        $script = "
        #! /bin/bash
        cat /home/mirrordaemon/.ssh/id_rsa.pub | grep '^ssh'
        "
        $vmNameExternal = "$($MirrorType.ToUpper())-EXTERNAL-MIRROR-TIER-$tier"
        $result = Invoke-RemoteScript -VMName $vmNameExternal -ResourceGroupName $config.mirrors.rg -Shell "UnixShell" -Script $script
        Add-LogMessage -Level Success "Fetching ssh key from external package mirror succeeded"
        $externalMirrorPublicKey = $result.Value[0].Message -split "\n" | Select-String "^ssh"
        $cloudInitYaml = $cloudInitYaml.Replace("<external-mirror-public-key>", $externalMirrorPublicKey)
    }

    # Populate initial package whitelist file defined in cloud init YAML
    $whiteList = Get-Content $WhitelistPath -Raw -ErrorVariable notExists -ErrorAction SilentlyContinue
    if (-Not $notExists) {
        $packagesBefore = "      # PACKAGE_WHITELIST"
        $packagesAfter = ""
        foreach ($package in $whitelist -split "`n") {
            $packagesAfter += "      $package`n"
        }
        $cloudInitYaml = $cloudInitYaml.Replace($packagesBefore, $packagesAfter)
    }

    # Set the tier, NTP server and timezone
    $cloudInitYaml = $cloudInitYaml.
        Replace("<ntp-server>", $config.time.ntp.poolFqdn).
        Replace("<tier>", "$tier").
        Replace("<timezone>", $config.time.timezone.linux)
    return $cloudInitYaml
}


# Set up a single package mirror
# ------------------------------
function Deploy-PackageMirror {
    param(
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Name of virtual machine to deploy")]
        $MirrorType,
        [Parameter(Position = 1, Mandatory = $true, HelpMessage = "Whether this is an internal or external mirror")]
        [ValidateSet("Internal", "External")]
        $MirrorDirection
    )
    # Load cloud-init file
    # --------------------
    $cloudInitPath = Join-Path $PSScriptRoot ".." "cloud_init" "cloud-init-mirror-${mirrorDirection}-${MirrorType}.yaml".ToLower()
    $fullMirrorType = "${MirrorType}".ToLower().Replace("cran", "r-cran").Replace("pypi", "python-pypi")
    $whitelistPath = Join-Path $PSScriptRoot ".." ".." ".." "environment_configs" "package_lists" "whitelist-full-${fullMirrorType}-tier${tier}.list".ToLower() # do not resolve this path as we have not tested whether it exists yet
    $cloudInitYaml = Resolve-CloudInit -MirrorType $MirrorType -MirrorDirection $MirrorDirection -CloudInitPath $cloudInitPath -WhitelistPath $whitelistPath

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
        $vmNic = Deploy-VirtualMachineNIC -Name "$vmName-NIC" -ResourceGroupName $config.mirrors.rg -Subnet $subnet -PrivateIpAddress $privateIpAddress -Location $config.location
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
                ImageSku               = "18.04-LTS"
                DataDiskIds            = @($dataDisk.Id)
            }
            $null = Deploy-UbuntuVirtualMachine @params
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
        Enable-AzVM -Name $vmName -ResourceGroupName $config.mirrors.rg

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
            Write-Output $result.Value
            $internalFingerprint = $result.Value[0].Message -split "\n" | Select-String "^127.0.0.1" | ForEach-Object { $_ -replace "127.0.0.1", "$privateIpAddress" }

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
            $result = Invoke-RemoteScript -VMName $externalVmName -ResourceGroupName $config.mirrors.rg -Shell "UnixShell" -Script $script
            Write-Output $result.Value
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
$null = Set-AzContext -Context $originalContext
