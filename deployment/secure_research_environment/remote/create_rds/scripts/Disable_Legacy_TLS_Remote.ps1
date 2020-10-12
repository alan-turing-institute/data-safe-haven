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


# Explicitly enable TLS 1.2
# -------------------------
Set-Protocol -Protocol "TLS 1.2" -Action Enable


# Get all 'recommended' and 'secure' ciphers from ciphersuite.info
# Note that we need 'secure' since none of the 'recommended' ciphers are currently supported by Microsoft Remote Desktop
# ----------------------------------------------------------------------------------------------------------------------
$response = Invoke-RestMethod -Uri https://ciphersuite.info/api/cs/security/recommended
$recommended = $response.ciphersuites | ForEach-Object { Get-Member -InputObject $_ -MemberType NoteProperty } | Select-Object -Property Name | ForEach-Object { $_.Name }
$response = Invoke-RestMethod -Uri https://ciphersuite.info/api/cs/security/secure
$secure = $response.ciphersuites | ForEach-Object { Get-Member -InputObject $_ -MemberType NoteProperty } | Select-Object -Property Name | ForEach-Object { $_.Name }
$allowedCiphers = @($recommended) + @($secure)


# Disable all ciphers that are not in the allowed list
# ----------------------------------------------------
foreach ($cipherSuite in $(Get-TlsCipherSuite | ForEach-Object { $_.Name })) {
    if ($cipherSuite -notin $allowedCiphers) {
        Disable-TlsCipherSuite -Name $cipherSuite
        if ($?) {
            Write-Output " [o] Disabled '$cipherSuite' suite."
        } else {
            Write-Output " [x] Failed to ensure '$cipherSuite' suite is disabled."
        }
    }
}


# Enable all ciphers that are in the allowed list
# -----------------------------------------------
foreach ($cipherSuite in $allowedCiphers) {
    if ($cipherSuite -notin $(Get-TlsCipherSuite | ForEach-Object { $_.Name })) {
        Enable-TlsCipherSuite -Name $cipherSuite
        if ($?) {
            Write-Output " [o] Enabled '$cipherSuite' suite."
        } else {
            Write-Output " [x] Failed to ensure '$cipherSuite' suite is enabled."
        }
    }
}


# List all cipher suites that are still allowed
# ---------------------------------------------
Write-Output "Allowed cipher suites are:"
(Get-TlsCipherSuite) | ForEach-Object { Write-Host "... $($_.Name)" }



