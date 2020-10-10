# Throwing an exception in a remote script means we have to wait 90 minutes for the remote call to time out
# Accordingly we don't validate any parameters or make them mandatory
# In reality, all three parameters are required and both 'Role' and 'Toggle' will only accept certain values
function Set-ProtocolForRole {
    param(
        [Parameter(HelpMessage = "Name of protocol")]
        $Protocol,
        [Parameter(HelpMessage = "Name of protocol [must be 'Server' or 'Client']")]
        $Role,
        [Parameter(HelpMessage = "Set whether we are enabling or disabling [must be 'Enabled' or 'Disabled']")]
        $Toggle
    )
    if ($Toggle -eq "Enabled") {
        $EnabledValue = 1
        $DisabledByDefaultValue = 0
    } elseif ($Toggle -eq "Disabled") {
        $EnabledValue = 0
        $DisabledByDefaultValue = 1
    } else {
        Write-Output " [x] Could not interpret '$Toggle'. Please use either 'Enabled' or 'Disabled'."
        return
    }

    # Disable protocol for role
    New-Item "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\$Protocol\$Role" -Force | Out-Null
    New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\$Protocol\$Role" -Name 'Enabled' -Value $EnabledValue -PropertyType 'DWord' -Force | Out-Null
    New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\$Protocol\$Role" -Name 'DisabledByDefault' -Value $DisabledByDefaultValue -PropertyType 'DWord' -Force | Out-Null
    # Check status
    $status = Get-Item "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\$Protocol\$Role"
    if (($status.GetValue("Enabled") -eq $EnabledValue) -and ($status.GetValue("DisabledByDefault") -eq $DisabledByDefaultValue)) {
        Write-Output " [o] '$Protocol' protocol is $Toggle for '$Role' role."
    } else {
        Write-Output " [x] Failed to ensure '$Protocol' protocol is $Toggle for '$Role' role."
        Write-Output $status
    }
}

function Set-Protocol {
    param(
        [Parameter(HelpMessage = "Name of protocol")]
        $Protocol,
        [Parameter(HelpMessage = "Set whether we are enabling or disabling [must be 'Enabled' or 'Disabled']")]
        $Toggle
    )
    Write-Output "Ensuring '$Protocol' is ${Toggle}..."
    Set-ProtocolForRole -Protocol $Protocol -Role "Client" -Toggle $Toggle
    Set-ProtocolForRole -Protocol $Protocol -Role "Server" -Toggle $Toggle
}


# Disable all legacy protocols
# ----------------------------
Set-Protocol -Protocol "SSL 2.0" -Toggle Disabled
Set-Protocol -Protocol "SSL 3.0" -Toggle Disabled
Set-Protocol -Protocol "TLS 1.0" -Toggle Disabled
Set-Protocol -Protocol "TLS 1.1" -Toggle Disabled


# Explicitly enable TLS 1.2
# -------------------------
Set-Protocol -Protocol "TLS 1.2" -Toggle Enabled


# Disable 'weak' ciphers using no encryption or weak encryption (RC4 or 3DES)
# ---------------------------------------------------------------------------
$weakCipherSuites = @(Get-TlsCipherSuite -Name "WITH_NULL" | ForEach-Object { $_.Name }) `
                  + @(Get-TlsCipherSuite -Name "WITH_RC4" | ForEach-Object { $_.Name }) `
                  + @(Get-TlsCipherSuite -Name "WITH_3DES" | ForEach-Object { $_.Name })


# Disable the following ciphers which are 'secure' but not 'recommended'
# ----------------------------------------------------------------------
# SHA1 is a deprecated hash function
$weakCipherSuites += @(Get-TlsCipherSuite -Name "SHA" | ForEach-Object { $_.Name } | Where-Object { $_ -like "*SHA" })
# PSK (pre-shared key) is a less secure key exchange method than DHE (Diffie-Hellman ephemeral)
$weakCipherSuites += @(Get-TlsCipherSuite -Name "TLS_PSK" | ForEach-Object { $_.Name })
# Plain RSA is potentially subject to the ROBOT attack (https://robotattack.org/)
$weakCipherSuites += @(Get-TlsCipherSuite -Name "TLS_RSA" | ForEach-Object { $_.Name })
# Plain AES without key exchange/authentication is still secure but disfavoured
$weakCipherSuites += @(Get-TlsCipherSuite -Name "TLS_AES" | ForEach-Object { $_.Name })

# Disable requested cipher suites
# -------------------------------
Write-Output "Disabling weak TLS cipher suites..."
foreach ($cipherSuite in ($weakCipherSuites | Sort-Object | Get-Unique)) {
    if (Get-TlsCipherSuite -Name $cipherSuite) {
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

# List all cipher suites that are still allowed
# At the time of writing this is the following:
# ... TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384 (recommended)
# ... TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256 (recommended)
# ... TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384 (recommended)
# ... TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256 (recommended)
# ... TLS_DHE_RSA_WITH_AES_256_GCM_SHA384 (recommended)
# ... TLS_DHE_RSA_WITH_AES_128_GCM_SHA256 (recommended)
# ... TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256 (secure)
# ... TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA384 (secure)
# ... TLS_DHE_DSS_WITH_AES_128_CBC_SHA256 (secure)
# ... TLS_DHE_DSS_WITH_AES_256_CBC_SHA256 (secure)
# ... TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256 (secure)
# ... TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384 (secure)
# Note that GCM is preferred over CBC but some browsers do not support it yet
# ---------------------------------------------------------------------------
Write-Output "Allowed cipher suites are:"
[System.Object[]](Get-TlsCipherSuite) | ForEach-Object { Write-Host "... $($_.Name)" }
