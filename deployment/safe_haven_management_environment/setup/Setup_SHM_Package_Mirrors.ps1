param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
  [string]$shmId,
  [Parameter(Position=1, Mandatory = $true, HelpMessage = "Which tier of mirrors should be deployed")]
  [ValidateSet("2", "3")]
  [string]$tier,
  [Parameter(Position=2, Mandatory = $false, HelpMessage = "If multiple sets of internal mirrors are needed at the same tier, use this string to distinguish them")]
  [string]$internalMirrorName = "Internal"
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
$_ = Set-AzContext -SubscriptionId $config.subscriptionName


# Ensure that package mirror and networking resource groups exist
# ---------------------------------------------------------------
$_ = Deploy-ResourceGroup -Name $config.mirrors.rg -Location $config.location
$_ = Deploy-ResourceGroup -Name $config.network.vnet.rg -Location $config.location


# Common variable names
# ---------------------
$nsgExternalName = "NSG_SHM_$($config.id)_EXTERNAL_PACKAGE_MIRRORS_TIER${tier}".ToUpper()
$nsgInternalName = "NSG_SHM_$($config.id)_INTERNAL_PACKAGE_MIRRORS_TIER${tier}".ToUpper()
$subnetExternalName = "ExternalPackageMirrorsTier${tier}Subnet"
$subnetInternalName = "${internalMirrorName}PackageMirrorsTier${tier}Subnet"
$vnetIpTriplet = "10.20.$tier"
$vnetName = "VNET_SHM_$($config.id)_PACKAGE_MIRRORS_TIER${tier}".ToUpper()


# Set up the VNet with subnets for internal and external package mirrors
# ----------------------------------------------------------------------
$vnetPkgMirrors = Deploy-VirtualNetwork -Name $vnetName -ResourceGroupName $config.network.vnet.rg -AddressPrefix "$vnetIpTriplet.0/24" -Location $config.location
# External subnet
$subnetExternal = Deploy-Subnet -Name $subnetExternalName -VirtualNetwork $vnetPkgMirrors -AddressPrefix "$vnetIpTriplet.0/28"
# Internal subnet
$existingSubnetIpRanges = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnetPkgMirrors | % { $_.AddressPrefix }
$nextAvailableIpRange = (0..240).Where({$_ % 16 -eq 0}) | % { "$vnetIpTriplet.$_/28" } | Where { $_ -notin $existingSubnetIpRanges } | Select-Object -First 1
$subnetInternal = Deploy-Subnet -Name $subnetInternalName -VirtualNetwork $vnetPkgMirrors -AddressPrefix $nextAvailableIpRange


# Set up the NSG for external package mirrors
# -------------------------------------------
$nsgExternal = Deploy-NetworkSecurityGroup -Name $nsgExternalName -ResourceGroupName $config.network.vnet.rg -Location $config.location
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsgExternal `
                             -Name "IgnoreInboundRulesBelowHere" `
                             -Description "Deny all other inbound" `
                             -Priority 3000 `
                             -Direction Inbound -Access Deny -Protocol * `
                             -SourceAddressPrefix * -SourcePortRange * `
                             -DestinationAddressPrefix * -DestinationPortRange *
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsgExternal `
                             -Name "UpdateFromInternet" `
                             -Description "Allow ports 443 (https) and 873 (unencrypted rsync) for updating mirrors" `
                             -Priority 300 `
                             -Direction Outbound -Access Allow -Protocol TCP `
                             -SourceAddressPrefix $subnetExternal.AddressPrefix -SourcePortRange * `
                             -DestinationAddressPrefix Internet -DestinationPortRange 443,873
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsgExternal `
                             -Name "IgnoreOutboundRulesBelowHere" `
                             -Description "Deny all other outbound" `
                             -Priority 3000 `
                             -Direction Outbound -Access Deny -Protocol * `
                             -SourceAddressPrefix * -SourcePortRange * `
                             -DestinationAddressPrefix * -DestinationPortRange *
# Create or update external mirror rule
$destinationAddressPrefix = @($subnetInternal.AddressPrefix)
$rule = $nsgExternal.SecurityRules | Where-Object { $_.Name -eq "RsyncToInternal" }
if ($rule) {
    $destinationAddressPrefix = ($rule.DestinationAddressPrefix + $destinationAddressPrefix) | Sort | Unique #| % { [string]$_ }
}
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsgExternal -VerboseLogging `
                             -Name "RsyncToInternal" `
                             -Description "Allow ports 22 and 873 for rsync" `
                             -Priority 400 `
                             -Direction Outbound -Access Allow -Protocol TCP `
                             -SourceAddressPrefix $subnetExternal.AddressPrefix -SourcePortRange * `
                             -DestinationAddressPrefix $destinationAddressPrefix -DestinationPortRange 22,873
$vnetPkgMirrors = Set-AzVirtualNetworkSubnetConfig -Name $subnetExternal.Name -VirtualNetwork $vnetPkgMirrors -AddressPrefix $subnetExternal.AddressPrefix -NetworkSecurityGroup $nsgExternal | Set-AzVirtualNetwork
$subnetExternal = Get-AzSubnet -Name $subnetExternal.Name -VirtualNetwork $vnetPkgMirrors
if ($?) {
    Add-LogMessage -Level Success "Configuring NSG '$nsgExternalName' succeeded"
} else {
    Add-LogMessage -Level Fatal "Configuring NSG '$nsgExternalName' failed!"
}


# Set up the NSG for internal package mirrors
# -------------------------------------------
$nsgInternal = Deploy-NetworkSecurityGroup -Name $nsgInternalName -ResourceGroupName $config.network.vnet.rg -Location $config.location
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsgInternal `
                             -Name "RsyncFromExternal" `
                             -Description "Allow ports 22 and 873 for rsync" `
                             -Priority 200 `
                             -Direction Inbound -Access Allow -Protocol TCP `
                             -SourceAddressPrefix $subnetExternal.AddressPrefix -SourcePortRange * `
                             -DestinationAddressPrefix * -DestinationPortRange 22,873
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsgInternal `
                             -Name "MirrorRequestsFromVMs" `
                             -Description "Allow ports 80 (http), 443 (pip) and 3128 (pip) for webservices" `
                             -Priority 300 `
                             -Direction Inbound -Access Allow -Protocol TCP `
                             -SourceAddressPrefix VirtualNetwork -SourcePortRange * `
                             -DestinationAddressPrefix * -DestinationPortRange 80,443,3128
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsgInternal `
                             -Name "IgnoreInboundRulesBelowHere" `
                             -Description "Deny all other inbound" `
                             -Priority 3000 `
                             -Direction Inbound -Access Deny -Protocol * `
                             -SourceAddressPrefix * -SourcePortRange * `
                             -DestinationAddressPrefix * -DestinationPortRange *
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsgInternal `
                             -Name "IgnoreOutboundRulesBelowHere" `
                             -Description "Deny all other outbound" `
                             -Priority 3000 `
                             -Direction Outbound -Access Deny -Protocol * `
                             -SourceAddressPrefix * -SourcePortRange * `
                             -DestinationAddressPrefix * -DestinationPortRange *
$vnetPkgMirrors = Set-AzVirtualNetworkSubnetConfig -Name $subnetInternal.Name -VirtualNetwork $vnetPkgMirrors -AddressPrefix $subnetInternal.AddressPrefix -NetworkSecurityGroup $nsgInternal | Set-AzVirtualNetwork
$subnetInternal = Get-AzSubnet -Name $subnetInternal.Name -VirtualNetwork $vnetPkgMirrors
if ($?) {
    Add-LogMessage -Level Success "Configuring NSG '$nsgInternalName' succeeded"
} else {
    Add-LogMessage -Level Fatal "Configuring NSG '$nsgInternalName' failed!"
}

# Get common objects
# ------------------
$bootDiagnosticsAccount = Deploy-StorageAccount -Name $config.storage.bootdiagnostics.accountName -ResourceGroupName $config.storage.bootdiagnostics.rg -Location $config.location
$adminUsername = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.vmAdminUsername


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

        $externalPublicSshKey = $result.Value[0].Message -split "\n" | Select-String "^ssh"
        $cloudInitYaml = $cloudInitYaml.Replace("EXTERNAL_PUBLIC_SSH_KEY", $externalPublicSshKey)
    }


    # PyPI
    if ($MirrorType.ToLower() -eq "pypi") {
        $whiteList = Get-Content $WhitelistPath -Raw -ErrorVariable notExists -ErrorAction SilentlyContinue
        if (-Not $notExists) {
            $packagesBefore = "      # PACKAGE_WHITELIST"
            $packagesAfter  = ""
            foreach ($package in $whitelist -split "`n") {
                $packagesAfter += "      $package`n"
            }
            $cloudInitYaml = $cloudInitYaml.Replace($packagesBefore, $packagesAfter).Replace("; IF_WHITELIST_ENABLED ", "")
        }
    }

    # CRAN
    if ($MirrorType.ToLower() -eq "cran") {
        $whiteList = Get-Content $WhitelistPath -Raw -ErrorVariable notExists -ErrorAction SilentlyContinue
        if (-Not $notExists) {
            $packagesBefore = "      # PACKAGE_WHITELIST"
            $packagesAfter  = ""
            foreach ($package in $whitelist -split "`n") {
                $packagesAfter += "      $package`n"
            }
            $cloudInitYaml = $cloudInitYaml.Replace($packagesBefore, $packagesAfter).Replace("# IF_WHITELIST_ENABLED ", "")
        }
    }

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
    $cloudInitPath = Join-Path $PSScriptRoot ".." "cloud_init" "cloud-init-mirror-$($($mirrorDirection).ToLower())-$($($MirrorType).ToLower()).yaml"
    $whitelistPath = Join-Path $PSScriptRoot ".." ".." ".." "environment_configs" "package_lists" "tier$($tier)_$($($MirrorType).ToLower())_whitelist.list"
    $cloudInitYaml = Resolve-CloudInit -MirrorType $MirrorType -MirrorDirection $MirrorDirection -CloudInitPath $cloudInitPath -WhitelistPath $whitelistPath

    # Construct IP address for this mirror
    # ------------------------------------
    if ($MirrorDirection -eq "Internal") {
        $subnet = $subnetInternal
    } else {
        $subnet = $subnetExternal
    }
    $ipOctets = $subnet.AddressPrefix.Split("/")[0].Split(".")
    $ipOctets[3] = [int]$ipOctets[3] + [int]$config.mirrors[$($MirrorType).ToLower()].ipOffset
    $privateIpAddress = $ipOctets -join "."

    # Check whether the VM already exists
    # -----------------------------------
    $vmName = "$MirrorType-$MirrorDirection-MIRROR-TIER-$tier".ToUpper()
    $adminPasswordSecretName = ("shm-" + "$($config.id)".ToLower() + "-package-mirror-" + "$MirrorType".ToLower() + "-" + "$MirrorDirection".ToLower() + "-tier-$tier-admin-password")
    $_ = Get-AzVM -Name $vmName -ResourceGroupName $config.mirrors.rg -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        # Deploy NIC and data disks
        # -------------------------
        $vmNic = Deploy-VirtualMachineNIC -Name "$vmName-NIC" -ResourceGroupName $config.mirrors.rg -Subnet $subnet -PrivateIpAddress $privateIpAddress -Location $config.location
        $dataDisk = Deploy-ManagedDisk -Name "$vmName-DATA-DISK" -SizeGB $config.mirrors.pypi.diskSize["tier$tier"] -Type $config.mirrors.diskType -ResourceGroupName $config.mirrors.rg -Location $config.location
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
                                        -Direction Outbound -Access Allow -Protocol TCP `
                                        -SourceAddressPrefix $privateIpAddress -SourcePortRange * `
                                        -DestinationAddressPrefix Internet -DestinationPortRange 80,443,3128
            Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsg `
                                        -Name "VnetOutboundTemporary" `
                                        -Description "Block connections to the VNet" `
                                        -Priority 150 `
                                        -Direction Outbound -Access Deny -Protocol * `
                                        -SourceAddressPrefix $privateIpAddress -SourcePortRange * `
                                        -DestinationAddressPrefix VirtualNetwork -DestinationPortRange *

            # Deploy the VM
            $params = @{
                Name = $vmName
                Size = $config.mirrors.vmSize
                OsDiskType = $config.mirrors.diskType
                AdminUsername = $adminUsername
                AdminPassword = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $adminPasswordSecretName
                CloudInitYaml = $cloudInitYaml
                NicId = $vmNic.Id
                ResourceGroupName = $config.mirrors.rg
                BootDiagnosticsAccount = $bootDiagnosticsAccount
                Location = $config.location
                DataDiskIds = @($dataDisk.Id)
            }
            $_ = Deploy-UbuntuVirtualMachine @params

            # Poll VM to see whether it has finished running
            Add-LogMessage -Level Info "Waiting for cloud-init provisioning to finish (this will take 5+ minutes)..."
            $statuses = (Get-AzVM -Name $vmName -ResourceGroupName $config.mirrors.rg -Status).Statuses.Code
            $progress = 0
            while (-not ($statuses.Contains("PowerState/stopped") -and $statuses.Contains("ProvisioningState/succeeded"))) {
                $statuses = (Get-AzVM -Name $vmName -ResourceGroupName $config.mirrors.rg -Status).Statuses.Code
                $progress += 1
                Write-Progress -Activity "Deployment status" -Status "$($statuses[0]) $($statuses[1])" -PercentComplete $progress
                Start-Sleep 10
            }
        } finally {
            # Remove temporary NSG rules
            Add-LogMessage -Level Info "Disabling outbound internet access from $privateIpAddress and restarting VM: '$vmName'..."
            $_ = Remove-AzNetworkSecurityRuleConfig -Name "ConfigurationOutboundTemporary" -NetworkSecurityGroup $nsg
            $_ = Remove-AzNetworkSecurityRuleConfig -Name "VnetOutboundTemporary" -NetworkSecurityGroup $nsg
            $_ = $nsg | Set-AzNetworkSecurityGroup
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
            # Get public key for internal server
            $script = "
            #! /bin/bash
            ssh-keyscan 127.0.0.1 2> /dev/null
            "
            $result = Invoke-RemoteScript -VMName $VMName -ResourceGroupName $config.mirrors.rg -Shell "UnixShell" -Script $script
            Write-Output $result.Value
            $internalFingerprint = $result.Value[0].Message -split "\n" | Select-String "^127.0.0.1" | % { $_ -replace "127.0.0.1", "$privateIpAddress" }

            # Inform external server about the new internal server
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
            $result = Invoke-RemoteScript -VMName $vmName.Replace("INTERNAL", "EXTERNAL") -ResourceGroupName $config.mirrors.rg -Shell "UnixShell" -Script $script
            Write-Output $result.Value
        }
    } else {
        Add-LogMessage -Level InfoSuccess "Virtual machine '$vmName' already exists"
    }
}


# Set up package mirror
# ---------------------
foreach ($mirrorType in ("PyPI", "CRAN")) {
    foreach ($mirrorDirection in ("External", "Internal")) {
        Deploy-PackageMirror -MirrorType $mirrorType -MirrorDirection $mirrorDirection
    }
}


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext
