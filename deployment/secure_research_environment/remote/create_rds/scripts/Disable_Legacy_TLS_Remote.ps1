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