@{
    IncludeRules = @(
        "PSPlaceOpenBrace",
        "PSPlaceCloseBrace",
        "PSUseConsistentWhitespace",
        "PSUseConsistentIndentation",
        "PSAlignAssignmentStatement",
        "PSUseCorrectCasing"
    )
    Rules = @{
        PSPlaceOpenBrace = @{
            Enable             = $true
            OnSameLine         = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
        }
        PSPlaceCloseBrace = @{
            Enable             = $true
            NewLineAfter       = $false
            IgnoreOneLineBlock = $true
            NoEmptyLineBefore  = $false
        }
        PSUseConsistentIndentation = @{
            Enable              = $false
            Kind                = "space"
            PipelineIndentation = "IncreaseIndentationForFirstPipeline"
            IndentationSize     = 4
        }
        PSUseConsistentWhitespace = @{
            Enable                          = $true
            CheckInnerBrace                 = $true
            CheckOpenBrace                  = $true
            CheckOpenParen                  = $true
            CheckOperator                   = $true
            CheckPipe                       = $true
            CheckPipeForRedundantWhitespace = $true
            CheckSeparator                  = $true
            CheckParameter                  = $true
        }
        PSAlignAssignmentStatement = @{
            Enable         = $true
            CheckHashtable = $true
        }
        PSUseCorrectCasing = @{
            Enable = $true
        }
    }
}