# Throwing an exception in a remote script means we have to wait 90 minutes for the remote call to time out
# Accordingly we don't validate any parameters or make them mandatory
# In reality, all three parameters are required and both 'Role' and 'Action' will only accept certain values
function Set-ProtocolForRole {
    param(
        [Parameter(HelpMessage = "Name of protocol")]
        $Protocol,
        [Parameter(HelpMessage = "Name of protocol [must be 'Server' or 'Client']")]
        $Role,
        [Parameter(HelpMessage = "Set whether we are enabling or disabling [must be 'Enable' or 'Disable']")]
        $Action
    )
    if ($Action -eq "Enable") {
        $EnabledValue = 1
        $DisabledByDefaultValue = 0
    } elseif ($Action -eq "Disable") {
        $EnabledValue = 0
        $DisabledByDefaultValue = 1
    } else {
        Write-Output " [x] Could not interpret '$Action'. Please use either 'Enable' or 'Disable'."
        return
    }

    # Disable protocol for role
    New-Item "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\$Protocol\$Role" -Force | Out-Null
    New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\$Protocol\$Role" -Name 'Enabled' -Value $EnabledValue -PropertyType 'DWord' -Force | Out-Null
    New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\$Protocol\$Role" -Name 'DisabledByDefault' -Value $DisabledByDefaultValue -PropertyType 'DWord' -Force | Out-Null
    # Check status
    $status = Get-Item "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\$Protocol\$Role"
    if (($status.GetValue("Enabled") -eq $EnabledValue) -and ($status.GetValue("DisabledByDefault") -eq $DisabledByDefaultValue)) {
        Write-Output " [o] '$Protocol' protocol is '${Action}d' for '$Role' role."
    } else {
        Write-Output " [x] Failed to ensure '$Protocol' protocol is '${Action}d' for '$Role' role."
        Write-Output $status
    }
}

function Set-Protocol {
    param(
        [Parameter(HelpMessage = "Name of protocol")]
        $Protocol,
        [Parameter(HelpMessage = "Set whether we are enabling or disabling [must be 'Enable' or 'Disable']")]
        $Action
    )
    Write-Output "Ensuring '$Protocol' is ${Action}..."
    Set-ProtocolForRole -Protocol $Protocol -Role "Client" -Action $Action
    Set-ProtocolForRole -Protocol $Protocol -Role "Server" -Action $Action
}


# Disable all legacy protocols
# ----------------------------
Set-Protocol -Protocol "SSL 2.0" -Action Disable
Set-Protocol -Protocol "SSL 3.0" -Action Disable
Set-Protocol -Protocol "TLS 1.0" -Action Disable
Set-Protocol -Protocol "TLS 1.1" -Action Disable


# Get all 'recommended' ciphers from ciphersuite.info
# ---------------------------------------------------
$response = Invoke-RestMethod -Uri https://ciphersuite.info/api/cs/security/recommended -ErrorAction Stop
$recommended = $response.ciphersuites | ForEach-Object { $_.PSObject.Properties.Name }


# ... however we also need at least one cipher from the 'secure' list since none
# of the 'recommended' ciphers are currently supported by the Microsoft Remote
# Desktop webclient. We choose the three RSA + AES + CBC + SHA256 algorithms.
# ------------------------------------------------------------------------------
$response = Invoke-RestMethod -Uri https://ciphersuite.info/api/cs/security/secure -ErrorAction Stop
# Note that we overwrite gnutls_name in the Values hashtable with the `Name` property for later use
$secure = $response.ciphersuites | ForEach-Object { $_.PSObject.Properties.Value.gnutls_name = $_.PSObject.Properties.Name; $_.PSObject.Properties.Value } `
                                 | Where-Object { $_.kex_algorithm -eq "ECDHE" } `
                                 | Where-Object { $_.auth_algorithm -eq "RSA" } `
                                 | Where-Object { $_.enc_algorithm -like "AES * CBC" } `
                                 | Where-Object { $_.hash_algorithm -eq "SHA256" } `
                                 | ForEach-Object { $_.gnutls_name }

# Construct allowed/disallowed lists
# ----------------------------------
$allowedCiphers = @($secure) + @($recommended)
$disallowedCiphers = Get-TlsCipherSuite | ForEach-Object { $_.Name } | Where-Object { -not $allowedCiphers.Contains($_) }


# Disable all ciphers that are not in the allowed list
# ----------------------------------------------------
Write-Output "Disabling any disallowed ciphersuites..."
foreach ($disallowedCipher in $disallowedCiphers) {
    # Note that running Disable-TlsCipherSuite on eg. TLS_DHE_RSA_WITH_AES_128_CCM will also disable TLS_DHE_RSA_WITH_AES_128_CCM_8
    # We therefore check whether the cipher still exists before disabling it.
    # By disabling before enabling, we ensure that this will not remove any ciphers that we want to keep.
    if (Get-TlsCipherSuite -Name $disallowedCipher) {
        Disable-TlsCipherSuite -Name $disallowedCipher
        if ($?) {
            Write-Output " [o] Disabled '$disallowedCipher' suite."
        } else {
            Write-Output " [x] Failed to ensure '$disallowedCipher' suite is disabled."
        }
    }
}


# Enable all ciphers that are in the allowed list
# -----------------------------------------------
Write-Output "Enabling all allowed ciphersuites..."
foreach ($allowedCipher in $allowedCiphers) {
    if (-not $(Get-TlsCipherSuite | ForEach-Object { $_.Name }).Contains($allowedCipher)) {
        Enable-TlsCipherSuite -Name $allowedCipher
        if ($?) {
            # Check whether this cipher is supported by Windows.
            # If it is not [ie. it has no CipherSuite entry] then immediately disable it.
            if ($((Get-TlsCipherSuite -Name $allowedCipher).CipherSuite) -eq 0) {
                Disable-TlsCipherSuite -Name $allowedCipher
                Write-Output " [x] Windows does not support the '$allowedCipher' suite."
            } else {
                Write-Output " [o] Enabled '$allowedCipher' suite."
            }
        } else {
            Write-Output " [x] Failed to ensure '$allowedCipher' suite is enabled."
        }
    }
}


# List all cipher suites that are still allowed
# ---------------------------------------------
Write-Output "There are $(((Get-TlsCipherSuite) | Measure-Object).Count) allowed cipher suites:"
(Get-TlsCipherSuite) | ForEach-Object { Write-Host "... $($_.Name)" }
