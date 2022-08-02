# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [Parameter(HelpMessage = "Comma separated list of FQDNs that are always allowed.")]
    [string]$AllowedFqdnsCommaSeparatedList,
    [Parameter(HelpMessage = "Comma separated list of CIDR ranges to block external DNS resolution for.")]
    [string]$RestrictedCidrsCommaSeparatedList,
    [Parameter(HelpMessage = "SRE ID")]
    [string]$SreId,
    [Parameter(Mandatory = $false, HelpMessage = "Comma separated list of CIDR ranges to allow default DNS resolution rules for.")]
    [string]$UnrestrictedCidrsCommaSeparatedList = $null
)


# Generate DNS client subnet name from CIDR
# -----------------------------------------
function Get-DnsClientSubnetNameFromCidr {
    param(
        [Parameter(HelpMessage = "SRE prefix")]
        [string]$SrePrefix,
        [Parameter(HelpMessage = "CIDR")]
        [string]$Cidr
    )
    return "$SrePrefix-$($Cidr.Replace('/','_'))"
}


# Ensure that a DNS client subnet exists
# --------------------------------------
function Set-DnsClientSubnets {
    param(
        [Parameter(HelpMessage = "CIDR")]
        [string]$Cidr,
        [Parameter(HelpMessage = "Subnet name")]
        [string]$SubnetName
    )
    $subnet = Get-DnsServerClientSubnet -Name $SubnetName -ErrorAction SilentlyContinue
    if ($subnet) {
        Write-Output " [o] DNS client subnet '$SubnetName' for CIDR '$Cidr' already exists."
    } else {
        try {
            $subnet = Add-DnsServerClientSubnet -Name $SubnetName -IPv4Subnet $Cidr
            Write-Output " [o] Successfully created DNS client subnet '$SubnetName' for CIDR '$Cidr'"
        } catch {
            Write-Output " [x] Failed to create DNS client subnet '$SubnetName' for CIDR '$Cidr'"
            Write-Output $_.Exception
        }
    }
}


# Ensure that a DNS server resolution policy exists
# -------------------------------------------------
function Set-DnsQueryResolutionPolicy {
    param(
        [Parameter(HelpMessage = "Comma-separated list of allowed FQDNs")]
        [string]$AllowedFqdns,
        [Parameter(HelpMessage = "Recursion policy")]
        [bool]$RestrictRecursion,
        [Parameter(HelpMessage = "Subnet name")]
        [string]$SubnetName
    )
    # If we are restricting access than attach to the scope with recursion disabled
    if ($RestrictRecursion) {
        $recursionType = "RecursionRestricted"
        $recursionScopeName = "RecursionBlocked"
        # Ensure blocked recursion scope exists
        $recursionScope = (Get-DnsServerRecursionScope | Where-Object { $_.Name -eq $recursionScopeName })
        if (-not $recursionScope) {
            Add-DnsServerRecursionScope -Name $recursionScopeName -EnableRecursion $false
        } else {
            Set-DnsServerRecursionScope -Name $recursionScopeName -EnableRecursion $false
        }
    } else {
        $recursionType = "RecursionAllowed"
        $recursionScopeName = "."
    }
    try {
        # Always allow recursion for approved FQDNs
        $null = Add-DnsServerQueryResolutionPolicy -Name "${subnetName}-ApprovedFqdns-DnsRecursionAllowed" -Action ALLOW -ClientSubnet "EQ,$SubnetName" -Condition "AND" -FQDN "EQ,$AllowedFqdns" -ApplyOnRecursion -RecursionScope "."
        Write-Output " [o] Set DNS 'RecursionAllowed' for approved FQDNs on client subnet '$SubnetName'"
        # For non-approved FQDNs allow or forbid based on the '$RestrictRecursion' argumenet
        $null = Add-DnsServerQueryResolutionPolicy -Name "${subnetName}-OtherFqdns-Dns${recursionType}" -Action ALLOW -ClientSubnet "EQ,$SubnetName" -Condition "AND" -FQDN "NE,$AllowedFqdns" -ApplyOnRecursion -RecursionScope $recursionScopeName
        Write-Output " [o] Set DNS '$recursionType' for other FQDNs on client subnet '$SubnetName'"
    } catch {
        Write-Output " [x] Failed to apply DNS policies to client subnet '$SubnetName'"
        Write-Output $_.Exception
    }
}


# Set name prefix for DNS client subnets and DNS resolution policies
$srePrefix = "sre-${sreId}"


# Create configurations containing CIDR and corresponding name stem
# -----------------------------------------------------------------
if ($RestrictedCidrsCommaSeparatedList) {
    $restrictedSubnets = @($RestrictedCidrsCommaSeparatedList.Split(",") | ForEach-Object { @{ Cidr = $_; Name = Get-DnsClientSubnetNameFromCidr -SrePrefix $srePrefix -Cidr $_ } })
} else {
    $restrictedSubnets = @()
}
if ($UnrestrictedCidrsCommaSeparatedList) {
    $unrestrictedSubnets = @($UnrestrictedCidrsCommaSeparatedList.Split(",") | ForEach-Object { @{ Cidr = $_; Name = Get-DnsClientSubnetNameFromCidr -SrePrefix $srePrefix -Cidr $_ } })
} else {
    $unrestrictedSubnets = @()
}


# Remove pre-existing DNS query resolution policies for SRE
# ---------------------------------------------------------
Write-Output "`nDeleting pre-existing DNS resolution policies for SRE '$sreId'..."
$existingPolicies = Get-DnsServerQueryResolutionPolicy | Where-Object { $_.Name -like "$srePrefix-*" }
if ($existingPolicies) {
    foreach ($existingPolicy in $existingPolicies) {
        try {
            Remove-DnsServerQueryResolutionPolicy -Name $existingPolicy.Name -Force
            Write-Output " [o] Successfully deleted policy '$($existingPolicy.Name)'"
        } catch {
            Write-Output " [x] Failed to delete policy '$($existingPolicy.Name)'"
            Write-Output $_.Exception
        }
    }
} else {
    Write-Output " [o] No pre-existing DNS resolution policies found."
}


# Remove pre-existing DNS client subnets for SRE
# ----------------------------------------------
Write-Output "`nDeleting pre-existing DNS client subnets for SRE '$sreId'..."
$existingSubnets = Get-DnsServerClientSubnet | Where-Object { $_.Name -like "$srePrefix-*" }
if ($existingSubnets) {
    foreach ($existingSubnet in $existingSubnets) {
        try {
            Remove-DnsServerClientSubnet -Name $existingSubnet.Name -Force
            Write-Output " [o] Successfully deleted subnet '$($existingSubnet.Name)'"
        } catch {
            Write-Output " [x] Failed to delete subnet '$($existingSubnet.Name)'"
            Write-Output $_.Exception
        }
    }
} else {
    Write-Output " [o] No pre-existing DNS client subnets found."
}


# Ensure DNS client subnets exist for unrestricted CIDR ranges
# ------------------------------------------------------------
Write-Output "`nCreating DNS client subnets for unrestricted CIDR ranges (these will not be blocked)..."
if ($unrestrictedSubnets) {
    $unrestrictedSubnets | ForEach-Object { Set-DnsClientSubnets -Cidr $_.cidr -SubnetName $_.Name }
} else {
    Write-Output " [o] No exception CIDR ranges specifed."
}


# Ensure DNS client subnets exist for restricted CIDR ranges
# ----------------------------------------------------------
Write-Output "`nCreating DNS client subnets for restricted CIDR ranges..."
if ($restrictedSubnets) {
    $restrictedSubnets | ForEach-Object { Set-DnsClientSubnets -Cidr $_.cidr -SubnetName $_.Name }
} else {
    Write-Output " [o] No blocked CIDR ranges specifed."
}


# Create DNS resolution policies for exception IP ranges
# ------------------------------------------------------
# Assign all queries for exception CIDRs subnets to default ('.') recursion scope.
# We must set policies for exception CIDR subnets first to ensure they take precedence as we
# cannot set processing order to be greater than the total number of resolution policies.
Write-Output "`nCreating DNS resolution policies for unrestricted CIDR ranges (these will not be blocked)..."
if ($unrestrictedSubnets) {
    $unrestrictedSubnets | ForEach-Object { Set-DnsQueryResolutionPolicy -SubnetName $_.Name -RestrictRecursion $false -AllowedFqdns $AllowedFqdnsCommaSeparatedList }
} else {
    Write-Output " [o] No unrestricted CIDR ranges specifed."
}


# Create DNS resolution policies for restricted IP ranges
# ----------------------------------------------------
# Assign all queries for restricted CIDRs subnets to restricted recursion scope.
Write-Output "`nCreating DNS resolution policies for restricted CIDR ranges..."
if ($restrictedSubnets) {
    $restrictedSubnets | ForEach-Object { Set-DnsQueryResolutionPolicy -SubnetName $_.Name -RestrictRecursion $true -AllowedFqdns $AllowedFqdnsCommaSeparatedList }
} else {
    Write-Output " [o] No restricted CIDR ranges specifed."
}


# Clear DNS cache to avoid midleading tests
# -----------------------------------------
# If a domain has previously been queried and is in the cache, it will be
# returned without recursion to external DNS servers
Write-Output "`nClearing DNS cache..."
try {
    $null = Clear-DnsServerCache -Force
    Write-Output " [o] Successfully cleared DNS cache."
} catch {
    Write-Output " [x] Failed to clear DNS cache."
    Write-Output $_.Exception
}
