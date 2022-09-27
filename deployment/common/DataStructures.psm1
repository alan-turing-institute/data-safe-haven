Import-Module $PSScriptRoot/Logging -ErrorAction Stop


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


# Convert a file into a Base-64, GZipped string
# ---------------------------------------------
function ConvertTo-Base64GZip {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Path to file to be converted", ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )
    $xrdpCustomLogo = Get-Content $Path -Raw -AsByteStream
    $outputStream = New-Object IO.MemoryStream
    $gzipStream = New-Object System.IO.Compression.GZipStream($outputStream, [Io.Compression.CompressionMode]::Compress)
    $gzipStream.Write($xrdpCustomLogo, 0, $xrdpCustomLogo.Length)
    $gzipStream.Close()
    $output = [Convert]::ToBase64String($outputStream.ToArray())
    $outputStream.Close()
    return $output
}
Export-ModuleMember -Function ConvertTo-Base64GZip


# Convert an object to a Base-64 string
# -------------------------------------
function ConvertTo-Base64 {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "String to be converted to Base-64", ValueFromPipeline = $true)]
        [AllowEmptyString()]
        [string]$InputString
    )
    return [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($InputString))
}
Export-ModuleMember -Function ConvertTo-Base64


# Convert a nested, sortable object into a sorted hashtable
# ---------------------------------------------------------
function ConvertTo-SortedHashtable {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Nested object to be sorted", ValueFromPipeline = $true)]
        [AllowNull()][AllowEmptyString()]
        $Sortable
    )
    $hasKeysValues = [bool](($Sortable.PSObject.Properties.name -match "Keys") -and ($Sortable.PSObject.Properties.name -match "Values"))
    if ($hasKeysValues) {
        $OutputHashtable = [ordered]@{}
        $Sortable.GetEnumerator() | Sort-Object -Property "Name" | ForEach-Object { $OutputHashtable.Add($_.Key, $(ConvertTo-SortedHashtable -Sortable $_.Value)) }
        return $OutputHashtable
    } else {
        return $Sortable
    }
}
Export-ModuleMember -Function ConvertTo-SortedHashtable


# Overwrite the contents of one hash table with that of another
# -------------------------------------------------------------
function Copy-HashtableOverrides {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Source hashtable")]
        $Source,
        [Parameter(Mandatory = $true, HelpMessage = "Target hashtable to override")]
        $Target
    )
    foreach ($sourcePair in $Source.GetEnumerator()) {
        # If we hit a leaf then override the target with the source value
        if ($sourcePair.Value -isnot [System.Collections.IDictionary]) {
            $Target[$sourcePair.Key] = $sourcePair.Value
            continue
        }
        # If the target already contains this key then continue recursively
        if ($Target.Contains($sourcePair.Key)) {
            Copy-HashtableOverrides $sourcePair.Value $Target[$sourcePair.Key]
        # Otherwise create a new key in the target with value taken from the source
        } else {
            $Target[$sourcePair.Key] = $sourcePair.Value
        }
    }
}
Export-ModuleMember -Function Copy-HashtableOverrides


# Retrieve values of all keys matching the given pattern
# ------------------------------------------------------
function Find-AllMatchingKeys {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Input hashtable")]
        [System.Collections.IDictionary]$Hashtable,
        [Parameter(Mandatory = $true, HelpMessage = "Key to look for")]
        [String]$Key
    )
    $output = @()
    foreach ($entryPair in $Hashtable.GetEnumerator()) {
        # If we hit a matching key then add its value to the output array
        if ($entryPair.Key -like "$Key") {
            $output += $entryPair.Value
        }
        # If we find a hashtable then walk that hashtable too
        elseif ($entryPair.Value -is [System.Collections.IDictionary]) {
            $output += Find-AllMatchingKeys -Hashtable $entryPair.Value -Key $Key
        }
    }
    return $output
}
Export-ModuleMember -Function Find-AllMatchingKeys


# Retrieve value for a (possibly) multilevel key
# ----------------------------------------------
function Get-MultilevelKey {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Input hashtable")]
        [System.Collections.IDictionary]$Hashtable,
        [Parameter(Mandatory = $true, HelpMessage = "Key to look for")]
        [String]$Key
    )
    if ($Hashtable.Contains($Key)) {
        return $Hashtable[$Key]
    } elseif ($Key.Contains(".")) {
        $keyPrefix = $Key.Split(".")[0]
        if ($Hashtable.Contains($keyPrefix)) {
            $keySuffix = $Key.Split(".") | Select-Object -Skip 1 | Join-String -Separator "."
            return Get-MultilevelKey -Hashtable $Hashtable[$keyPrefix] -Key $keySuffix
        }
    }
    return $null
}
Export-ModuleMember -Function Get-MultilevelKey


# Truncate string at a given length
# ---------------------------------
function Limit-StringLength {
    param(
        [Parameter(Mandatory = $True, ValueFromPipeline = $True)]
        [string]$InputString,
        [Parameter(Mandatory = $True)]
        [int]$MaximumLength,
        [Parameter(Mandatory = $false)]
        [Switch]$FailureIsFatal,
        [Parameter(Mandatory = $false)]
        [Switch]$Silent
    )
    if ($InputString.Length -le $MaximumLength) {
        return $InputString
    }
    if ($FailureIsFatal) {
        Add-LogMessage -Level Fatal "'$InputString' has length $($InputString.Length) but must not exceed $MaximumLength!"
    }
    if (-Not $Silent) {
        Add-LogMessage -Level Warning "Truncating '$InputString' to length $MaximumLength!"
    }
    return $InputString[0..($MaximumLength - 1)] -join ""
}
Export-ModuleMember -Function Limit-StringLength


# Retrieve value for a (possibly) multilevel key
# ----------------------------------------------
function Wait-For {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Number of seconds to wait for")]
        [int]$Seconds,
        [Parameter(Mandatory = $true, HelpMessage = "Thing that we are waiting for")]
        [string]$Target
    )
    1..$Seconds | ForEach-Object { Write-Progress -Activity "Waiting $Seconds seconds for $Target..." -Status "$_ seconds elapsed" -PercentComplete (100 * $_ / $Seconds); Start-Sleep 1 }
}
Export-ModuleMember -Function Wait-For
