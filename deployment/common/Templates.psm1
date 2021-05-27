Import-Module Poshstache -Global -ErrorAction Stop # Note that we need -Global as Poshstache uses `Get-Module` to check where it is isntalled
Import-Module $PSScriptRoot/DataStructures -ErrorAction Stop
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
        [System.Collections.IDictionary]$Parameters
    )
    # If we are given a path then we need to extract the content
    if ($TemplatePath) { $Template = Get-Content $TemplatePath -Raw }

    # Define the delimiters
    $MustacheOpen = "{"
    $MustacheClose = "}"
    $StartDelimiter = "${MustacheOpen}${MustacheOpen}"
    $EndDelimiter = "${MustacheClose}${MustacheClose}"

    # Get all unique mustache tags
    $tags = ($Template | Select-String -Pattern "$StartDelimiter[^${MustacheOpen}${MustacheClose}]*$EndDelimiter" -AllMatches).Matches.Value | `
        Where-Object { $_ -and ($_ -ne "{{.}}") } | `
        ForEach-Object { $_.Replace("#", "").Replace("/", "").Replace("?", "").Replace("^", "").Replace("&", "") } | `
        Get-Unique

    # As '.' is not an allowed character in standard Mustache syntax, we replace these with '_' in both the template and the parameter table
    $PoshstacheParameters = @{}
    foreach ($tag in $tags) {
        $tagKey = $tag.Replace($StartDelimiter, "").Replace($EndDelimiter, "").Trim()
        $normalisedTagKey = $tagKey.Replace(".", "_")
        $Template = $Template.Replace($tagKey, $normalisedTagKey)
        $PoshstacheParameters[$normalisedTagKey] = Get-MultilevelKey -Hashtable $Parameters -Key $tagKey
    }

    # Use Poshstache to expand the template
    return ConvertTo-PoshstacheTemplate -InputString $Template -ParametersObject (ConvertTo-Json $PoshstacheParameters)
}
Export-ModuleMember -Function Expand-MustacheTemplate


# Expand a cloud-init file by inserting any referenced resources
# --------------------------------------------------------------
function Expand-CloudInitResources {
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "ByFile", HelpMessage = "Cloud-init template to be expanded.")]
        [string]$Template,
        [Parameter(Mandatory = $true, ParameterSetName = "ByPath", HelpMessage = "Path to cloud-init template to be expanded.")]
        [string]$TemplatePath,
        [Parameter(Mandatory = $true, HelpMessage = "Path to resource files.")]
        [string]$ResourcePath
    )
    # If we are given a path then we need to extract the content
    if ($TemplatePath) { $Template = Get-Content $TemplatePath -Raw }

    # Insert resources into the cloud-init template
    foreach ($resource in (Get-ChildItem $ResourcePath)) {
        $indent = $Template -split "`n" | Where-Object { $_ -match "{{$($resource.Name)}}" } | ForEach-Object { $_.Split("{")[0] } | Select-Object -First 1
        $indentedContent = (Get-Content $resource.FullName -Raw) -split "`n" | ForEach-Object { "${indent}$_" } | Join-String -Separator "`n"
        $Template = $Template.Replace("${indent}{{$($resource.Name)}}", $indentedContent)
    }
    return $Template
}
Export-ModuleMember -Function Expand-CloudInitResources


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
