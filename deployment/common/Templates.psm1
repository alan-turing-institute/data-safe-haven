Import-Module $PSScriptRoot/DataStructures -Force -ErrorAction Stop
Import-Module $PSScriptRoot/Logging -Force -ErrorAction Stop


# Expand a mustache template
# Use the terminology from https://mustache.github.io/mustache.5.html
# -------------------------------------------------------------------
function Expand-MustacheTemplate {
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "ByFile", HelpMessage = "Mustache template to be expanded.")]
        [string]$Template,
        [Parameter(Mandatory = $true, ParameterSetName = "ByPath", HelpMessage = "Path to mustache template to be expanded.")]
        [string]$TemplatePath,
        [Parameter(Mandatory = $true, HelpMessage = "Hashtable (can be multi-level) with parameter key-value pairs.")]
        [System.Collections.IDictionary]$Parameters,
        [Parameter(Mandatory = $false, HelpMessage = "Start delimiter.")]
        [string]$StartDelimeter = "{{",
        [Parameter(Mandatory = $false, HelpMessage = "End delimiter.")]
        [string]$EndDelimiter = "}}",
        [Parameter(Mandatory = $false, HelpMessage = "Delimiter to wrap around each element of an array")]
        [string]$ArrayJoiner = $null
    )
    # If we are given a path then we need to extract the content
    if ($TemplatePath) { $Template = Get-Content $TemplatePath -Raw }

    # Get all unique mustache tags
    $tags = ($Template | Select-String -Pattern "$StartDelimeter(.*)$EndDelimiter" -AllMatches).Matches.Value | Get-Unique

    # Replace each mustache tag with a value from parameters if there is one
    foreach ($tag in $tags) {
        $tagKey = $tag.Replace($StartDelimeter, "").Replace($EndDelimiter, "").Trim()
        $value = Get-MultilevelKey -Hashtable $Parameters -Key $tagKey
        if ($null -eq $value) {
            Add-LogMessage -Level Fatal "No value for '$tagKey' found in Parameters hashtable."
        } else {
            if (($value -is [array]) -and $ArrayJoiner) { $value = $value -join "${ArrayJoiner}, ${ArrayJoiner}" }
            $Template = $Template.Replace($tag, $value)
        }
    }
    return $Template
}
Export-ModuleMember -Function Expand-MustacheTemplate


# Get patched JSON from template
# ------------------------------
function Get-JsonFromMustacheTemplate {
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "ByFile", HelpMessage = "Mustache template to be expanded.")]
        [string]$Template,
        [Parameter(Mandatory = $true, ParameterSetName = "ByPath", HelpMessage = "Path to mustache template to be expanded.")]
        [string]$TemplatePath,
        [Parameter(Mandatory = $true, HelpMessage = "Hashtable (can be multi-level) with parameter key-value pairs.")]
        [System.Collections.IDictionary]$Parameters,
        [Parameter(Mandatory = $false, HelpMessage = "Return patched JSON as hashtable.")]
        [switch]$AsHashtable,
        [Parameter(Mandatory = $false, HelpMessage = "Delimiter to wrap around each element of an array")]
        [string]$ArrayJoiner = $null
    )
    if ($Template) {
        $templateJson = Expand-MustacheTemplate -Template $Template -ArrayJoiner $ArrayJoiner -Parameters $Parameters
    } else {
        $templateJson = Expand-MustacheTemplate -TemplatePath $TemplatePath -ArrayJoiner $ArrayJoiner -Parameters $Parameters
    }
    return ($templateJson | ConvertFrom-Json -AsHashtable:$AsHashtable)
}
Export-ModuleMember -Function Get-JsonFromMustacheTemplate
