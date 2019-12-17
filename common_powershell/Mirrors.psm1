# Get root directory for configuration files
# ------------------------------------------
function Get-MirrorAddresses {
    param(
        [Parameter(Position = 0,HelpMessage = "CRAN IP address")]
        [string]$cranIp = $null,
        [Parameter(Position = 1,HelpMessage = "PyPI IP address")]
        [string]$pypiIp = $null
    )
    # if($config.dsg.mirrors.cran.ip) {
    if ($cranIp) {
        $cranUrl = "http://$($cranIp)"
    } else {
        $cranUrl = "https://cran.r-project.org"
    }
    # if($config.dsg.mirrors.pypi.ip) {
    if ($pypiIp) {
        $pypiUrl = "http://$($pypiIp):3128"
    } else {
        $pypiUrl = "https://pypi.org"
    }
    # We want to extract the hostname from PyPI URLs in either of the following forms
    # 1. http://10.20.2.20:3128 => 10.20.2.20
    # 2. https://pypi.org       => pypi.org
    $pypiHost = ""
    if ($pypiUrl -match "https*:\/\/([^:]*)[:0-9]*") { $pypiHost = $Matches[1] }
    $addresses = [ordered]@{
        cran = [ordered]@{
            url = $cranUrl
        }
        pypi = [ordered]@{
            url = $pypiUrl
            host = $pypiHost
        }
    }
    return $addresses
}
Export-ModuleMember -Function Get-MirrorAddresses
