Import-Module Pester -ErrorAction Stop


# Run Pester tests
# ----------------
Invoke-Pester $(Join-Path $PSScriptRoot "pester") -Output Detailed
