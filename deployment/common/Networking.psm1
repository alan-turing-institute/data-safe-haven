Import-Module Az.Network -ErrorAction Stop
Import-Module $PSScriptRoot/Logging -ErrorAction Stop


# Add a VM to a domain
# --------------------
function Add-WindowsVMtoDomain {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of VM to domain join")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Resource group for VM to domain join")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Domain name to join")]
        [string]$DomainName,
        [Parameter(Mandatory = $true, HelpMessage = "Username for domain joining account")]
        [string]$DomainJoinUsername,
        [Parameter(Mandatory = $true, HelpMessage = "Password for domain joining account")]
        [System.Security.SecureString]$DomainJoinPassword,
        [Parameter(Mandatory = $true, HelpMessage = "The full distinguished name for the OU to add this VM to")]
        [string]$OUPath,
        [Parameter(Mandatory = $false, HelpMessage = "Force restart of VM if already running")]
        [switch]$ForceRestart
    )
    Add-LogMessage -Level Info "[ ] Attempting to join VM '$Name' to domain '$DomainName'"
    $domainJoinCredentials = New-Object System.Management.Automation.PSCredential("${DomainName}\${DomainJoinUsername}", $DomainJoinPassword)
    $null = Set-AzVMADDomainExtension -VMName $Name -ResourceGroupName $ResourceGroupName -DomainName $DomainName -Credential $domainJoinCredentials -JoinOption 3 -TypeHandlerVersion 1.3 -OUPath $OUPath -Restart:$ForceRestart
    if ($?) {
        Add-LogMessage -Level Success "Joined VM '$Name' to domain '$DomainName'"
    } else {
        Add-LogMessage -Level Fatal "Failed to join VM '$Name' to domain '$DomainName'!"
    }
}
Export-ModuleMember -Function Add-WindowsVMtoDomain


# Convert an IP address into a decimal integer
# --------------------------------------------
function Convert-CidrToIpAddressRange {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Input range in CIDR notation")]
        [string]$IpRangeCidr,
        [Parameter(Mandatory = $false, HelpMessage = "Return results as decimal values instead of IP address strings")]
        [switch]$AsDecimal = $false
    )
    # Split the CIDR range into the IP address prefix and the CIDR suffix
    $ipAddressPrefx, $cidrSuffix = $IpRangeCidr.Split("/")

    # Convert the IP prefix and CIDR suffix to decimal
    [uint32]$ipPrefixDecimal = Convert-IpAddressToDecimal -IpAddress $ipAddressPrefx
    [uint32]$cidrMaskDecimal = Convert-CidrSuffixToDecimalMask -Cidr $cidrSuffix

    # Get the starting and ending IP addresses
    $ipStartDecimal = $ipPrefixDecimal -band $cidrMaskDecimal
    $ipEndDecimal = $ipPrefixDecimal -bor (-bnot $cidrMaskDecimal)

    # Return as decimals or IP addresses
    if ($AsDecimal) {
        return @($ipStartDecimal, $ipEndDecimal)
    }
    return @(
        (Convert-DecimalToIpAddress -IpDecimal $ipStartDecimal),
        (Convert-DecimalToIpAddress -IpDecimal $ipEndDecimal)
    )
}
Export-ModuleMember -Function Convert-CidrToIpAddressRange


# Convert an IP address into a decimal integer
# --------------------------------------------
function Convert-CidrSuffixToDecimalMask {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Input CIDR")]
        [uint32]$CidrSuffix
    )
    # Construct the CIDR mask as a series of '1's followed by enough '0's to pad the length to 32
    # Now these numbers can be used one-by-one to construct a 32-bit integer
    [uint32]$decimalMask = 0
    @(1) * $CidrSuffix + @(0) * (32 - $CidrSuffix) | ForEach-Object { $decimalMask = ($decimalMask -shl 1) + $_ }
    return $decimalMask
}
Export-ModuleMember -Function Convert-CidrToDecimalMask


# Convert a decimal integer into an IP address
# --------------------------------------------
function Convert-DecimalToIpAddress {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Input decimal value")]
        [string]$IpDecimal
    )
    return [System.Net.IPAddress]::parse($IpDecimal).IPAddressToString
}
Export-ModuleMember -Function Convert-DecimalToIpAddress


# Convert an IP address into a decimal integer
# --------------------------------------------
function Convert-IpAddressToDecimal {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Input IP address")]
        [string]$IpAddress
    )
    $IpOctets = Convert-IpAddressToOctets -IpAddress $IpAddress
    return [uint32]($($IpOctets[0] -shl 24) + $($IpOctets[1] -shl 16) + $($IpOctets[2] -shl 8) + $IpOctets[3])
}
Export-ModuleMember -Function Convert-IpAddressToDecimal


# Convert an IP address into a set of octets
# ------------------------------------------
function Convert-IpAddressToOctets {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Input IP address")]
        [string]$IpAddress
    )
    $nSeparators = ($IpAddress.ToCharArray() | Where-Object { $_ -eq "." } | Measure-Object).Count
    if ($nSeparators -ne 3) {
        Add-LogMessage -Level Fatal "Expected three dot-separators but '$IpAddress' has $nSeparators!"
    }
    return @($IpAddress.Split(".") | ForEach-Object { [uint32]$_ })
}
Export-ModuleMember -Function Convert-IpAddressToOctets


# Convert a set of IP octets into an IP address
# ---------------------------------------------
function Convert-OctetsToIpAddress {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Input IP octets")]
        [uint32[]]$IpOctets
    )
    if ($IpOctets.Count -ne 4) {
        Add-LogMessage -Level Fatal "Expected four octets but '$IpOctets' has $($IpOctets.Count)!"
    }
    return $IpOctets -Join "."
}
Export-ModuleMember -Function Convert-OctetsToIpAddress


# Get next available IP address in range
# --------------------------------------
function Get-NextAvailableIpInRange {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Input range in CIDR notation")]
        [string]$IpRangeCidr,
        [Parameter(Mandatory = $false, HelpMessage = "Offset to apply before returning an IP address")]
        [int]$Offset,
        [Parameter(Mandatory = $false, HelpMessage = "Virtual network to check availability against")]
        [Microsoft.Azure.Commands.Network.Models.PSVirtualNetwork]$VirtualNetwork
    )
    # Get the start and end IP decimals for this CIDR range
    $ipStart, $ipEnd = Convert-CidrToIpAddressRange -IpRangeCidr $IpRangeCidr -AsDecimal

    # Return the full range or filter as required
    $ipAddresses = $ipStart..$ipEnd | ForEach-Object { Convert-DecimalToIpAddress -IpDecimal $_ } | Select-Object -Skip $Offset
    if ($VirtualNetwork) {
        $ipAddress = $ipAddresses | Where-Object { (Test-AzPrivateIPAddressAvailability -VirtualNetwork $VirtualNetwork -IPAddress $_).Available } | Select-Object -First 1
    } else {
        $ipAddress = $ipAddresses | Select-Object -First 1
    }
    if (-not $ipAddress) {
        Add-LogMessage -Level Fatal "There are no free IP addresses in '$IpRangeCidr' after applying the offset '$Offset'!"
    }
    return $ipAddress
}
Export-ModuleMember -Function Get-NextAvailableIpInRange


# Set Network Security Group Rules
# --------------------------------
function Set-NetworkSecurityGroupRules {
    param(
        [parameter(Mandatory = $true, HelpMessage = "Network Security Group to set rules for")]
        [Microsoft.Azure.Commands.Network.Models.PSNetworkSecurityGroup]$NetworkSecurityGroup,
        [parameter(Mandatory = $true, HelpMessage = "Rules to set for Network Security Group")]
        [Object[]]$Rules
    )
    Add-LogMessage -Level Info "[ ] Setting $($Rules.Count) rules for Network Security Group '$($NetworkSecurityGroup.Name)'"
    try {
        $existingRules = @(Get-AzNetworkSecurityRuleConfig -NetworkSecurityGroup $NetworkSecurityGroup)
        foreach ($existingRule in $existingRules) {
            $NetworkSecurityGroup = Remove-AzNetworkSecurityRuleConfig -Name $existingRule.Name -NetworkSecurityGroup $NetworkSecurityGroup
        }
    } catch {
        Add-LogMessage -Level Fatal "Error removing existing rules. Network Security Group '$($NetworkSecurityGroup.Name)' left unchanged." -Exception $_.Exception
    }
    try {
        foreach ($rule in $Rules) {
            $NetworkSecurityGroup = Add-AzNetworkSecurityRuleConfig -NetworkSecurityGroup $NetworkSecurityGroup @rule
        }
    } catch {
        Add-LogMessage -Level Fatal "Error adding provided rules. Network Security Group '$($NetworkSecurityGroup.Name)' left unchanged." -Exception $_.Exception
    }
    $NetworkSecurityGroup = Set-AzNetworkSecurityGroup -NetworkSecurityGroup $NetworkSecurityGroup
    $updatedRules = @(Get-AzNetworkSecurityRuleConfig -NetworkSecurityGroup $NetworkSecurityGroup)
    foreach ($updatedRule in $updatedRules) {
        $sourceAddressText = ($updatedRule.SourceAddressPrefix -eq "*") ? "any source" : $updatedRule.SourceAddressPrefix
        $destinationAddressText = ($updatedRule.DestinationAddressPrefix -eq "*") ? "any destination" : $updatedRule.DestinationAddressPrefix
        $destinationPortText = ($updatedRule.DestinationPortRange -eq "*") ? "any port" : "ports $($updatedRule.DestinationPortRange)"
        Add-LogMessage -Level Success "Set $($updatedRule.Name) rule to $($updatedRule.Access) connections from $sourceAddressText to $destinationPortText on $destinationAddressText."
    }
    return $NetworkSecurityGroup
}
Export-ModuleMember -Function Set-NetworkSecurityGroupRules


# Update subnet and IP address for a VM
# -------------------------------------
function Update-VMIpAddress {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Azure VM object", ParameterSetName = "ByObject")]
        [Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine]$VM,
        [Parameter(Mandatory = $true, HelpMessage = "VM name", ParameterSetName = "ByName")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "VM resource group", ParameterSetName = "ByName")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Subnet to join")]
        [Microsoft.Azure.Commands.Network.Models.PSChildResource]$Subnet,
        [Parameter(Mandatory = $true, HelpMessage = "IP address to switch to")]
        [string]$IpAddress
    )
    # Get VM if not provided
    if (-not $VM) {
        $VM = Get-AzVM -Name $Name -ResourceGroup $ResourceGroupName
    }
    $networkCard = Get-AzNetworkInterface | Where-Object { $_.VirtualMachine.Id -eq $VM.Id }
    if ($networkCard.Count -ne 1) { Add-LogMessage -Level Fatal "Found $($networkCard.Count) network cards for $VMName!" }
    if ($networkCard.IpConfigurations[0].PrivateIpAddress -eq $IpAddress) {
        Add-LogMessage -Level InfoSuccess "IP address for '$($VM.Name)' is already set to '$IpAddress'"
    } else {
        Add-LogMessage -Level Info "Updating subnet and IP address for '$($VM.Name)'..."
        Stop-VM -VM $VM
        $networkCard.IpConfigurations[0].Subnet.Id = $Subnet.Id
        $networkCard.IpConfigurations[0].PrivateIpAddress = $IpAddress
        $null = $networkCard | Set-AzNetworkInterface
        # Validate changes
        $networkCard = Get-AzNetworkInterface | Where-Object { $_.VirtualMachine.Id -eq $VM.Id }
        if ($networkCard.IpConfigurations[0].Subnet.Id -eq $Subnet.Id) {
            Add-LogMessage -Level Info "Set '$($VM.Name)' subnet to '$($Subnet.Name)'"
        } else {
            Add-LogMessage -Level Fatal "Failed to change subnet to '$($Subnet.Name)'!"
        }
        if ($networkCard.IpConfigurations[0].PrivateIpAddress -eq $IpAddress) {
            Add-LogMessage -Level Info "Set '$($VM.Name)' IP address to '$IpAddress'"
        } else {
            Add-LogMessage -Level Fatal "Failed to change IP address to '$IpAddress'!"
        }
        Start-VM -VM $VM
    }
}
Export-ModuleMember -Function Update-VMIpAddress
