# Throwing an exception in a remote script means we have to wait 90 minutes for the remote call to time out
# Therefore we don't validate any parameters or make them mandatory
# Both Protocol and Role are required and Role must be one of Server or Client
function Disable-ProtocolForRole {
    param(
        [Parameter(HelpMessage = "Name of protocol")]
        $Protocol,
        [Parameter(HelpMessage = "Name of protocol")]
        $Role
    )
    # Disable protocol for role
    New-Item "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\$Protocol\$Role" -Force | Out-Null 
    New-ItemProperty -path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\$Protocol\$Role" -name 'Enabled' -value '0' -PropertyType 'DWord' -Force | Out-Null 
    New-ItemProperty -path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\$Protocol\$Role" -name 'DisabledByDefault' -value 1 -PropertyType 'DWord' -Force | Out-Null 
    # Check status
    $status = Get-Item "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\$Protocol\$Role"
    if((-not $status.GetValue("Enabled")) -and $status.GetValue("DisabledByDefault")) {
        Write-Output " [o] '$Protocol' protocol is disabled for '$Role' role."
    } else {
        Write-Output " [x] Failed to ensure '$Protocol' protocol is disabled for '$Role' role."
        Write-Output $status
    }
}

function Disable-Protocol {
    param(
        [Parameter(HelpMessage = "Name of protocol")]
        $Protocol
    )
    Write-Output "Ensuring '$Protocol' is disabled..."
    Disable-ProtocolForRole -Protocol $Protocol -Role "Client"
    Disable-ProtocolForRole -Protocol $Protocol -Role "Server"
}


# Disable all legacy protocols
Disable-Protocol -Protocol "SSL 2.0"
Disable-Protocol -Protocol "SSL 3.0"
Disable-Protocol -Protocol "TLS 1.0"
Disable-Protocol -Protocol "TLS 1.1"

# Disable weak cipher suites
Write-Output "Ensuring weak TLS cipher suites are disabled..."
# The following list of weak cipher suites are the ones listed as supported
# on a Windows Server 2019 VM deployed on Azure on 09 July 2020 and *not*
# listed in the table of preferred secure cipher suites at
# https://www.acunetix.com/blog/articles/tls-ssl-cipher-hardening/
# NOTE: We exclude known weak suites, rather than restrict ourselved to
# known strong suites, as additional stronger suites may be introduced 
# over time (e.g. with the rollout of general availability support for
# TLS 3.0).
$weakCipherSuites = @(
    "TLS_AES_256_GCM_SHA384",
    "TLS_AES_128_GCM_SHA256",
    "TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA384",
    "TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256",
    "TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA",
    "TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA",
    "TLS_RSA_WITH_NULL_SHA256",
    "TLS_RSA_WITH_NULL_SHA",
    "TLS_PSK_WITH_AES_256_GCM_SHA384",
    "TLS_PSK_WITH_AES_128_GCM_SHA256",
    "TLS_PSK_WITH_AES_256_CBC_SHA384",
    "TLS_PSK_WITH_AES_128_CBC_SHA256",
    "TLS_PSK_WITH_NULL_SHA384",
    "TLS_PSK_WITH_NULL_SHA256",
    "TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384",
    "TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256",
    "TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA",
    "TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA",
    "TLS_RSA_WITH_AES_256_GCM_SHA384",
    "TLS_RSA_WITH_AES_128_GCM_SHA256",
    "TLS_RSA_WITH_AES_256_CBC_SHA256",
    "TLS_RSA_WITH_AES_128_CBC_SHA256",
    "TLS_RSA_WITH_AES_256_CBC_SHA",
    "TLS_RSA_WITH_AES_128_CBC_SHA",
    "TLS_RSA_WITH_3DES_EDE_CBC_SHA"
)
foreach ($cipherSuite in $WeakCipherSuites) {
    if(Get-TlsCipherSuite -Name $cipherSuite) {
        Disable-TlsCipherSuite -Name $cipherSuite
        if ($?) {
            Write-Output " [o] Disabled '$cipherSuite' suite."
        } else {
            Write-Output " [x] Failed to ensure '$cipherSuite' suite is disabled."
        }
    } else {
        Write-Output " [o] '$cipherSuite' suite already disabled."
    }
}