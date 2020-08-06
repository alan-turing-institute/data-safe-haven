# Get root directory for configuration files
# ------------------------------------------
function Get-MirrorAddresses {
    param(
        [Parameter(Position = 0,HelpMessage = "CRAN IP address")]
        [string]$cranIp = $null,
        [Parameter(Position = 1,HelpMessage = "PyPi IP address")]
        [string]$pypiIp = $null,
        [Parameter(Position = 2,HelpMessage = "PyPi is a Nexus proxy")]
        [bool]$nexus = $false
    )

    $nexus_port = 8081

    if ($cranIp) {
        $cranUrl = "http://$($cranIp)"
        if ($nexus) {
            $cranUrl = $cranUrl + ":" + $nexus_port + "/repository/cran-proxy"
        }

    } else {
        $cranUrl = "https://cran.r-project.org"
    }

    if ($pypiIp) {
        $pypiUrl = "http://$($pypiIp)"
        if ($nexus) {
            $port = $nexus_port
        } else{
            $port = 3128
        }
        $pypiUrl = $pypiUrl + ":" + $port
    } else {
        $pypiUrl = "https://pypi.org"
    }

    # We want to extract the hostname from PyPI URLs in either of the following forms
    # 1. http://10.20.2.20:3128 => 10.20.2.20
    # 2. https://pypi.org       => pypi.org
    $pypiHost = ""
    if ($pypiUrl -match "https*:\/\/([^:]*)[:0-9]*") { $pypiHost = $Matches[1] }

    if ($nexus) {
        $pypiIndex = $pypiUrl + "/repository/pypi-proxy/pypi"
        $pypiIndexUrl = $pypiUrl + "/repository/pypi-proxy/simple"
    } else {
        $pypiIndex = $pypiUrl
        $pypiIndexUrl = $pypiUrl + "/simple"
    }


    $addresses = [ordered]@{
        cran = [ordered]@{
            url = $cranUrl
        }
        pypi = [ordered]@{
            index = $pypiIndex
            indexUrl = $pypiIndexUrl
            host = $pypiHost
        }
    }
    return $addresses
}
Export-ModuleMember -Function Get-MirrorAddresses
