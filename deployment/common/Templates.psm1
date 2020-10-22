Import-Module $PSScriptRoot/DataStructures -ErrorAction Stop -Force
Import-Module $PSScriptRoot/Logging -ErrorAction Stop


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
        [string]$EndDelimiter = "}}"
    )
    # If we are given a path then we need to extract the content
    if ($TemplatePath) { $Template = Get-Content $TemplatePath -Raw }

    # Get all unique mustache tags
    $tags = ($Template | Select-String -Pattern "$StartDelimeter(.*)$EndDelimiter" -AllMatches).Matches.Value | Get-Unique

    # Replace each mustache tag with a value from parameters if there is one
    foreach ($tag in $tags) {
        $tagKey = $tag.Replace($StartDelimeter, "").Replace($EndDelimiter, "").Trim()
        $value = Find-MultilevelKey -Hashtable $Parameters -Key $tagKey
        if ($null -eq $value) {
            Add-LogMessage -Level Fatal "No value for '$tagKey' found in Parameters hashtable."
        } else {
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
        [switch]$AsHashtable
    )
    if ($Template) {
        $templateJson = Expand-MustacheTemplate -Template $Template -Parameters $Parameters
    } else {
        $templateJson = Expand-MustacheTemplate -TemplatePath $TemplatePath -Parameters $Parameters
    }
    return ($templateJson | ConvertFrom-Json -AsHashtable:$AsHashtable)
}
Export-ModuleMember -Function Get-JsonFromMustacheTemplate
