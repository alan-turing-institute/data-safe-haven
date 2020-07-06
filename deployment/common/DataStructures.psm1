# Convert a nested, sortable object into a sorted hashtable
# ---------------------------------------------------------
function ConvertTo-SortedHashtable {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Nested object to be sorted")]
        [AllowNull()][AllowEmptyString()]
        $Sortable
    )
    $hasKeysValues = [bool](($Sortable.PSobject.Properties.name -match "Keys") -and ($Sortable.PSobject.Properties.name -match "Values"))
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
        if ($sourcePair.Value -isnot [Hashtable]) {
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


# Truncate string at a given length
# ---------------------------------
function Limit-StringLength {
    param(
        [Parameter(Mandatory = $True, ValueFromPipeline = $True)]
        [string]$InputString,
        [Parameter(Position = 0, Mandatory = $True)]
        [int]$MaximumLength,
        [Parameter(Mandatory=$false)]
        [Switch]$FailureIsFatal,
        [Parameter(Mandatory=$false)]
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