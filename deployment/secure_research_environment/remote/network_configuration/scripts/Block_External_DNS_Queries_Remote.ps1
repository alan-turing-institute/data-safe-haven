# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [Parameter(HelpMessage = "SRE ID")]
    $sreId,
    [Parameter(HelpMessage = "SRE Virtual Network Index")]
    $sreVirtualNetworkIndex,
    [Parameter(HelpMessage = "Comma separated list of CIDR ranges to block external DNS resolution for.")]
    $blockedCidrsList,
    [Parameter(HelpMessage = "Comma separated list of CIDR ranges within the blocked ranges to exceptionally allow default DNS resolution rules for.")]
    $exceptionCidrsList
)

# Set name prefix for DNS Client Subnets and DNS Resocultion Policies
$srePrefix = "sre-$sreId"

# Generate DNS Client Subnet name from CIDR
# -----------------------------------------
function Get-DnsClientSubnetNameFromCidr {
    param(
        $cidr
    )
    return "$srePrefix-$($cidr.Replace('/','_'))"
}

# Create configurations containing CIDR and corresponding Name stem
# -----------------------------------------------------------------
if ($blockedCidrsList) {
    $blockedConfigs = @($blockedCidrsList.Split(",") | ForEach-Object { @{ Cidr=$_; Name=Get-DnsClientSubnetNameFromCidr -cidr $_} })
} else {
    $blockedConfigs = @()
}
if ($exceptionCidrsList) {
    $exceptionConfigs = @($exceptionCidrsList.Split(",") | ForEach-Object { @{ Cidr=$_; Name=Get-DnsClientSubnetNameFromCidr -cidr $_} })
} else {
    $exceptionConfigs = @()
}


# Remove pre-existing DNS Query Resolution Policies for SRE
# ---------------------------------------------------------
Write-Output "`nDeleting pre-existing DNS resolution policies for SRE '$sreId'..."
$existingPolicies = Get-DnsServerQueryResolutionPolicy | Where-Object { $_.Name -like "$srePrefix-*" }
if ($existingPolicies) {
    foreach ($existingPolicy in $existingPolicies) {
        try {
            Write-Output " [ ] Deleting policy '$($existingPolicy.Name)'"
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


# Remove pre-existing DNS Client Subnets for SRE
# ----------------------------------------------
Write-Output "`nDeleting pre-existing DNS client subnets for SRE '$sreId'..."
$existingSubnets = Get-DnsServerClientSubnet | Where-Object { $_.Name -like "$srePrefix-*" }
if ($existingSubnets) {
    foreach ($existingSubnet in $existingSubnets) {
        try {
            Write-Output " [ ] Deleting subnet '$($existingSubnet.Name)'"
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


# Ensure DNS Client Subnets exist for exception CIDR ranges
# ---------------------------------------------------------
Write-Output "`nCreating DNS client subnets for exception CIDR ranges (these will not be blocked)..."
if ($exceptionConfigs) {
    foreach ($config in $exceptionConfigs) {
        $cidr = $config.cidr
        $subnetName = $config.Name
        Write-Output " [ ] Creating '$subnetName' DNS Client Subnet for CIDR '$cidr'"
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
} else {
    Write-Output " [o] No exception CIDR ranges specifed."
}


# Ensure DNS Client Subnets exist for blocked CIDR ranges
# -------------------------------------------------------
Write-Output "`nCreating DNS client subnets for blocked CIDR ranges..."
if ($blockedConfigs) {
    foreach ($config in $blockedConfigs) {
        $cidr = $config.cidr
        $subnetName = $config.Name
        Write-Output " [ ] Creating '$subnetName' DNS Client Subnet for CIDR '$cidr'"
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
} else {
    Write-Output " [o] No blocked CIDR ranges specifed."
}


# Create DNS resolution policies for exception IP ranges
# ------------------------------------------------------
# Assign all queries for exception CIDRs subnets to default ('.') recursion scope.
# We must set policies for exception CIDR subnets first to ensure they take precedence as we 
# cannot set processing order to be greater than the total number of resolution policies.
$defaultRecursionScopeName = "."
Write-Output "`nCreating DNS resolution policies for exception CIDR ranges (these will not be blocked)..."
if ($exceptionConfigs) {
    foreach ($config in $exceptionConfigs) {
        $subnetName = $config.Name
        $policyName = "$subnetName-default-recursion"
        $recursionScopeName = $defaultRecursionScopeName
        try {
            $policy = Add-DnsServerQueryResolutionPolicy -Name $policyName -Action ALLOW -ClientSubnet  "EQ,$subnetName" -ApplyOnRecursion -RecursionScope $recursionScopeName
            Write-Output " [o] Successfully created policy '$policyName' to apply '$recursionScopeName' for DNS Client Subnet '$subnetName' (CIDR: '$cidr')"
        } catch {
            Write-Output " [x] Failed to create policy to '$policyName' apply '$recursionScopeName' for DNS Client Subnet '$subnetName' (CIDR: '$cidr')"
            Write-Output $_.Exception
        }
    }
} else {
    Write-Output " [o] No exception CIDR ranges specifed."
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
# Assign all queries for blocked CIDRs subnets to blocked recursion scope.
Write-Output "`nCreating DNS resolution policies for blocked CIDR ranges..."
if ($blockedConfigs) {
    foreach ($config in $blockedConfigs) {
        $subnetName = $config.Name
        $policyName = "$subnetName-recursion-blocked"
        $recursionScopeName = $blockedRecursionScopeName
        try {
            $null = Add-DnsServerQueryResolutionPolicy -Name $policyName -Action ALLOW -ClientSubnet  "EQ,$subnetName" -ApplyOnRecursion -RecursionScope $recursionScopeName
            Write-Output " [o] Successfully created policy '$policyName' to apply '$recursionScopeName' for DNS Client Subnet '$subnetName' (CIDR: '$cidr')"
        } catch {
            Write-Output " [x] Failed to create policy '$policyName' to apply '$recursionScopeName' for DNS Client Subnet '$subnetName' (CIDR: '$cidr')"
            Write-Output $_.Exception
        }
    }
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
