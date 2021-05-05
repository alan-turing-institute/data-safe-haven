# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [Parameter(HelpMessage = "SRE ID")]
    $sreId,
    [Parameter(HelpMessage = "Comma separated list of CIDR ranges to block external DNS resolution for.")]
    $blockedCidrsCommaSeparatedList,
    [Parameter(Mandatory = $false, HelpMessage = "Comma separated list of CIDR ranges within the blocked ranges to exceptionally allow default DNS resolution rules for.")]
    $exceptionCidrsCommaSeparatedList = $null
)


# Generate DNS Client Subnet name from CIDR
# -----------------------------------------
function Get-DnsClientSubnetNameFromCidr {
    param(
        [Parameter(HelpMessage = "SRE prefix")]
        [string]$srePrefix,
        [Parameter(HelpMessage = "CIDR")]
        [string]$cidr
    )
    return "$srePrefix-$($cidr.Replace('/','_'))"
}


# Ensure that a DNS client subnet exists
# --------------------------------------
function Set-DnsClientSubnets {
    param(
        [Parameter(HelpMessage = "CIDR")]
        [string]$cidr,
        [Parameter(HelpMessage = "Subnet name")]
        [string]$subnetName
    )
    $subnet = Get-DnsServerClientSubnet -Name $subnetName -ErrorAction SilentlyContinue
    if ($subnet) {
        Write-Output " [o] '$subnetName' DNS Client Subnet for CIDR '$cidr' already exists."
    } else {
        try {
            $subnet = Add-DnsServerClientSubnet -Name $subnetName -IPv4Subnet $cidr
            Write-Output " [o] Successfully created '$subnetName' DNS Client Subnet for CIDR '$cidr'"
        } catch {
            Write-Output " [x] Failed to create '$subnetName' DNS Client Subnet for CIDR '$cidr'"
            Write-Output $_.Exception
        }
    }
}


# Ensure that a DNS server resolution policy exists
# -------------------------------------------------
function Set-DnsQueryResolutionPolicy {
    param(
        [Parameter(HelpMessage = "CIDR")]
        [string]$cidr,
        [Parameter(HelpMessage = "Subnet name")]
        [string]$subnetName,
        [Parameter(HelpMessage = "Recursion policy")]
        [string]$recursionScopeName
    )
    $recursionType = $recursionScopeName
    if ($recursionType -eq ".") { $recursionType = "RecursionAllowed" }
    $policyName = "${subnetName}-${recursionType}"
    try {
        $null = Add-DnsServerQueryResolutionPolicy -Name $policyName -Action ALLOW -ClientSubnet "EQ,$subnetName" -ApplyOnRecursion -RecursionScope $recursionScopeName
        Write-Output " [o] Successfully created policy '$policyName' to apply '$recursionScopeName' for DNS Client Subnet '$subnetName' (CIDR: '$cidr')"
    } catch {
        Write-Output " [x] Failed to create policy to '$policyName' apply '$recursionScopeName' for DNS Client Subnet '$subnetName' (CIDR: '$cidr')"
        Write-Output $_.Exception
    }
}


# Set name prefix for DNS client subnets and DNS resolution policies
$srePrefix = "sre-${sreId}"


# Create configurations containing CIDR and corresponding name stem
# -----------------------------------------------------------------
if ($blockedCidrsCommaSeparatedList) {
    $blockedConfigs = @($blockedCidrsCommaSeparatedList.Split(",") | ForEach-Object { @{ Cidr = $_; Name = Get-DnsClientSubnetNameFromCidr -srePrefix $srePrefix -cidr $_ } })
} else {
    $blockedConfigs = @()
}
if ($exceptionCidrsCommaSeparatedList) {
    $exceptionConfigs = @($exceptionCidrsCommaSeparatedList.Split(",") | ForEach-Object { @{ Cidr = $_; Name = Get-DnsClientSubnetNameFromCidr -srePrefix $srePrefix -cidr $_ } })
} else {
    $exceptionConfigs = @()
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


# Ensure DNS client subnets exist for exception CIDR ranges
# ---------------------------------------------------------
Write-Output "`nCreating DNS client subnets for exception CIDR ranges (these will not be blocked)..."
if ($exceptionConfigs) {
    $exceptionConfigs | ForEach-Object { Set-DnsClientSubnets -cidr $_.cidr -subnetName $_.Name }
} else {
    Write-Output " [o] No exception CIDR ranges specifed."
}


# Ensure DNS client subnets exist for blocked CIDR ranges
# -------------------------------------------------------
Write-Output "`nCreating DNS client subnets for blocked CIDR ranges..."
if ($blockedConfigs) {
    $blockedConfigs | ForEach-Object { Set-DnsClientSubnets -cidr $_.cidr -subnetName $_.Name }
} else {
    Write-Output " [o] No blocked CIDR ranges specifed."
}


# Ensure blocked recursion scope exists
# -------------------------------------
$blockedRecursionScopeName = "RecursionBlocked"
$blockedRecursionScope = (Get-DnsServerRecursionScope | Where-Object { $_.Name -eq $blockedRecursionScopeName })
if (-not $blockedRecursionScope) {
    Add-DnsServerRecursionScope -Name $blockedRecursionScopeName -EnableRecursion $false
} else {
    Set-DnsServerRecursionScope -Name $blockedRecursionScopeName -EnableRecursion $false
}


# Create DNS resolution policies for exception IP ranges
# ------------------------------------------------------
# Assign all queries for exception CIDRs subnets to default ('.') recursion scope.
# We must set policies for exception CIDR subnets first to ensure they take precedence as we
# cannot set processing order to be greater than the total number of resolution policies.
Write-Output "`nCreating DNS resolution policies for exception CIDR ranges (these will not be blocked)..."
if ($exceptionConfigs) {
    $exceptionConfigs | ForEach-Object { Set-DnsQueryResolutionPolicy -cidr $_.cidr -subnetName $_.Name -recursionScopeName "." }
} else {
    Write-Output " [o] No exception CIDR ranges specifed."
}


# Create DNS resolution policies for blocked IP ranges
# ----------------------------------------------------
# Assign all queries for blocked CIDRs subnets to blocked recursion scope.
Write-Output "`nCreating DNS resolution policies for blocked CIDR ranges..."
if ($blockedConfigs) {
    $blockedConfigs | ForEach-Object { Set-DnsQueryResolutionPolicy -cidr $_.cidr -subnetName $_.Name -recursionScopeName $blockedRecursionScopeName }
} else {
    Write-Output " [o] No blocked CIDR ranges specifed."
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
