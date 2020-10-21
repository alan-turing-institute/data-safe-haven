Import-Module $PSScriptRoot/../../deployment/common/DataStructures -Force -ErrorAction Stop


# Redefine Write-Host to suppress output from log message functions
function global:Write-Host() {}


# Test ConvertTo-SortedHashtable
Describe "Test ConvertTo-SortedHashtable" {
    It "Returns True if ordered hashtable is correctly sorted" {
        $unsorted = [ordered]@{
            b = "B"
            a = [ordered]@{
                d = "D"
                c = 17
            }
        }
        $sorted = ConvertTo-SortedHashtable -Sortable $unsorted
        $sorted[0][0] | Should -Be 17
        $sorted[0][1] | Should -Be "D"
        $sorted[1] | Should -Be "B"
    }
}


# Test Copy-HashtableOverrides
Describe "Test Copy-HashtableOverrides" {
    It "Returns True overrides are applied to selected keys while leaving others untouched" {
        $target = [ordered]@{
            a = [ordered]@{
                c = 17
                d = "D"
            }
            b = "B"
        }
        $overrides = [ordered]@{ a = [ordered]@{ d = "16" } }
        $null = Copy-HashtableOverrides -Source $overrides -Target $target
        $target["a"]["c"] | Should -Be 17
        $target["a"]["d"] | Should -Be "16"
        $target["b"] | Should -Be "B"
    }
}


# Test Find-AllMatchingKeys
Describe "Test Find-AllMatchingKeys" {
    It "Returns True if all matching keys are found" {
        $target = [ordered]@{
            a = [ordered]@{
                c = 17
                d = 1
            }
            b = [ordered]@{
                d = "3"
            }
            d = "2"
        }
        Find-AllMatchingKeys -Hashtable $target -Key "d" | Should -Be @(1, "3", "2")
    }
}


# Test Limit-StringLength
Describe "Test Limit-StringLength MaximumLength" {
    It "Returns True if string length is correctly limited" {
        "abcdefghijklm" | Limit-StringLength -Silent -MaximumLength 6 | Should -Be "abcdef"
    }
}
Describe "Test Limit-StringLength FailureIsFatal" {
    It "Should throw an exception since the string is too long" {
        { "abcdefghijklm" | Limit-StringLength -FailureIsFatal -MaximumLength 6 } | Should -Throw "'abcdefghijklm' has length 13 but must not exceed 6!"
    }
}
