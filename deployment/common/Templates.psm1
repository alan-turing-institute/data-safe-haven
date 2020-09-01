Import-Module $PSScriptRoot/Logging -ErrorAction Stop

# Get patched JSON from template
# ------------------------------
function Get-PatchedJsonFromTemplate {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Path to JSON template file to be patched and returned.")]
        $TemplateJsonFilePath,
        [Parameter(Mandatory = $true, HelpMessage = "Multi-level hashtable with parameter key-value pairs.")]
        $Parameters,
        [Parameter(Mandatory = $false, HelpMessage = "Retrun patched JSON as hashtable.")]
        [switch]$AsHashtable
    )
    
    # Get all mustache placeholders
    $startDelimeter = "{{"
    $endDelimiter = "}}"
    $regexPattern = "$startDelimeter(.*)$endDelimiter"
    $templateJson = Get-Content $TemplateJsonFilePath -Raw
    $placeholders = ($templateJson | Select-String -Pattern $regexPattern -AllMatches).Matches.Value | Get-Unique
    foreach ($placeholder in $placeholders) {
        $node = $Parameters
        $multiLevelKey = $placeholder.Replace($startDelimeter,"").Replace($endDelimiter,"")
        foreach ($level in $multiLevelKey.Split(".")) {
            $node = $node.$level
        }
        if(-not $node) {
            Add-LogMessage -Level Fatal "No value for '$multiLevelKey' found in Parameters hashtable."
        } else {
            $templateJson = $templateJson.Replace($placeholder, $node)
        }
    }
    return ($templateJson | ConvertFrom-Json -AsHashtable:$AsHashtable)
}
Export-ModuleMember -Function Get-PatchedJsonFromTemplate