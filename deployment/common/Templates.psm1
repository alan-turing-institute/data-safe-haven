Import-Module $PSScriptRoot/DataStructures -ErrorAction Stop -Force
Import-Module $PSScriptRoot/Logging -ErrorAction Stop


# Expand a mustache template
# Use the terminology from https://mustache.github.io/mustache.5.html
# -------------------------------------------------------------------
function Expand-MustacheTemplate {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Mustache template to be expanded.")]
        [string]$Template,
        [Parameter(Mandatory = $true, HelpMessage = "Hashtable (can be multi-level) with parameter key-value pairs.")]
        [System.Collections.IDictionary]$Parameters,
        [Parameter(Mandatory = $false, HelpMessage = "Start delimiter.")]
        [string]$StartDelimeter = "{{",
        [Parameter(Mandatory = $false, HelpMessage = "End delimiter.")]
        [string]$EndDelimiter = "}}"
    )
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
function Get-PatchedJsonFromTemplate {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Path to JSON template file to be patched and returned.")]
        $TemplateJsonFilePath,
        [Parameter(Mandatory = $true, HelpMessage = "Hashtable (can be multi-level) with parameter key-value pairs.")]
        $Parameters,
        [Parameter(Mandatory = $false, HelpMessage = "Return patched JSON as hashtable.")]
        [switch]$AsHashtable
    )
    $templateJson = Expand-MustacheTemplate -Template (Get-Content $TemplateJsonFilePath -Raw) -Parameters $Parameters
    return ($templateJson | ConvertFrom-Json -AsHashtable:$AsHashtable)
}
Export-ModuleMember -Function Get-PatchedJsonFromTemplate
