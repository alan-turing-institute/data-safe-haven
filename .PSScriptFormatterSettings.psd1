@{
    IncludeRules = @("PSPlaceOpenBrace", "PSUseConsistentIndentation")
    Rules = @{
        PSPlaceOpenBrace = @{
            Enable     = $true
            OnSameLine = $true
        }
        PSUseConsistentIndentation = @{
            Enable = $true
        }
    }
}