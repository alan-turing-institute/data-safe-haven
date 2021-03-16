# Get IP addresses for package mirrors/repositories
# -------------------------------------------------
function Get-MirrorIPs {
    param(
        [Parameter(HelpMessage = "SRE configuration")]
        $config
    )
    if (@(0, 1).Contains([int]$config.sre.tier)) {
        # For tiers 0 and 1, return null. Get-MirrorAddresses will then return
        # the appropriate settings to use pypi.org and cran.r-project.org
        # directly.
        $pypiIp = $null
        $cranIp = $null
    } else {
        # Nexus is not (currently) supported for tier 3, so fall back to tier 3
        # mirror if tier=3 and nexus=true
        if ($config.sre.nexus -and ([int]$config.sre.tier -eq 2)) {
            $pypiIp = $config.shm.repository.nexus.ipAddress
            $cranIp = $config.shm.repository.nexus.ipAddress
        } else {
            $pypiIp = $config.shm.mirrors.pypi["tier$($config.sre.tier)"].internal.ipAddress
            $cranIp = $config.shm.mirrors.cran["tier$($config.sre.tier)"].internal.ipAddress
        }
    }

    $IPs = [ordered]@{
        pypi = $pypiIp
        cran = $cranIp
    }
    return $IPs
}
Export-ModuleMember -Function Get-MirrorIPs


# Get URLs for package mirrors/repositories
# -----------------------------------------
function Get-MirrorAddresses {
    param(
        [Parameter(HelpMessage = "CRAN IP address")]
        [string]$cranIp = $null,
        [Parameter(HelpMessage = "PyPI IP address")]
        [string]$pypiIp = $null,
        [Parameter(HelpMessage = "PyPI is a Nexus proxy")]
        [bool]$nexus = $false
    )

    $nexus_port = 80

    if ($cranIp) {
        $cranUrl = "http://${cranIp}"
        if ($nexus) {
            $cranUrl = "${cranUrl}:${nexus_port}/repository/cran-proxy"
        }
    } else {
        $cranUrl = "https://cran.r-project.org"
    }

    if ($pypiIp) {
        $pypiUrl = "http://${pypiIp}:$($nexus ? $nexus_port : 3128)"
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
            index    = $pypiIndex
            indexUrl = $pypiIndexUrl
            host     = $pypiHost
        }
    }
    return $addresses
}
Export-ModuleMember -Function Get-MirrorAddresses
