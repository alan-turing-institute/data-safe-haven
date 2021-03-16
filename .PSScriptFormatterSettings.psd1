@{
    IncludeRules = @(
        "PSAlignAssignmentStatement",
        "PSPlaceCloseBrace",
        "PSPlaceOpenBrace",
        "PSUseConsistentIndentation",
        "PSUseConsistentWhitespace",
        "PSUseCorrectCasing"
    )
    Rules = @{
        PSAlignAssignmentStatement = @{
            Enable         = $true
            CheckHashtable = $true
        }
        PSPlaceCloseBrace = @{
            Enable             = $true
            NewLineAfter       = $false
            IgnoreOneLineBlock = $true
            NoEmptyLineBefore  = $false
        }
        PSPlaceOpenBrace = @{
            Enable             = $true
            OnSameLine         = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
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
        PSUseCorrectCasing = @{
            Enable = $true
        }
    }
}