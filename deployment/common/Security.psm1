Import-Module $PSScriptRoot/Logging -ErrorAction Stop

# Purge a secret from the keyvault
# --------------------------------
function Get-SslCipherSuites {
    # Start with 'recommended' ciphers from ciphersuite.info
    $httpResponse = Invoke-RestMethod -Uri https://ciphersuite.info/api/cs/security/recommended -ErrorAction Stop
    $recommended = $httpResponse.ciphersuites

    # ... however we also need at least one cipher from the 'secure' list since none of the 'recommended' ciphers are supported by TLS 1.2
    # We take the ones recommended by SSL Labs (https://github.com/ssllabs/research/wiki/SSL-and-TLS-Deployment-Best-Practices)
    $response = Invoke-RestMethod -Uri https://ciphersuite.info/api/cs/security/secure -ErrorAction Stop
    $ssllabsRecommended = @(
        "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256",
        "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384",
        "TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA",
        "TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA",
        "TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256",
        "TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA384",
        "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256",
        "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384",
        "TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA",
        "TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA",
        "TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256",
        "TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384",
        "TLS_DHE_RSA_WITH_AES_128_GCM_SHA256",
        "TLS_DHE_RSA_WITH_AES_256_GCM_SHA384",
        "TLS_DHE_RSA_WITH_AES_128_CBC_SHA",
        "TLS_DHE_RSA_WITH_AES_256_CBC_SHA",
        "TLS_DHE_RSA_WITH_AES_128_CBC_SHA256",
        "TLS_DHE_RSA_WITH_AES_256_CBC_SHA25"
    )
    $secure = $response.ciphersuites | Where-Object { $ssllabsRecommended.Contains($_.PSObject.Properties.Name) }

    # Construct a list of names in both OpenSSL and TLS format
    $allowedCiphers = @($secure) + @($recommended)
    return @{
        openssl = @($allowedCiphers | ForEach-Object { $_.PSObject.Properties.Value.openssl_name } | Where-Object { $_ })
        tls     = @($allowedCiphers | ForEach-Object { $_.PSObject.Properties.Name } | Where-Object { $_ })
    }
}
Export-ModuleMember -Function Get-SslCipherSuites


# Generate a random alphanumeric password
# This gives a verifiably flat distribution across the characters in question
# We introduce bias by the password requirements which increase the proportion of digits
# --------------------------------------------------------------------------------------
function New-Password {
    param(
        [int]$Length = 20
    )
    # Construct allowed character set
    $alphaNumeric = [char[]](1..127) -match "[0-9A-Za-z]" -join ""
    $rangeSize = $alphaNumeric.Length - 1

    # Initialise common parameters
    $cryptoRng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $fourByteArray = [System.Byte[]]::CreateInstance([System.Byte], 4)
    $maxUint = [uint32]::MaxValue
    $ceiling = [uint32]($maxUint - ($maxUint % $rangeSize)) # highest UInt that is evenly divisible by rangeSize

    # Convert random bytes into characters from permitted character set
    $password = ""
    foreach ($i in 1..$Length) {
        # This should give a smoother distribution across the 0..<n characters> space than the previous method which used 'byte % <n characters>' which inherently favours lower numbers
        while ($true) {
            $cryptoRng.GetBytes($fourByteArray)
            $randomUint = [BitConverter]::ToUInt32($fourByteArray, 0)
            # Restrict to only values in the range that rangeSize divides evenly into
            if ($randomUint -lt $ceiling) {
                $password += $alphaNumeric[$randomUint % $rangeSize]
                break
            }
        }
    }

    # Require at least one of each character class
    if (-not (($password -cmatch "[a-z]+") -and ($password -cmatch "[A-Z]+") -and ($password -cmatch "[0-9]+"))) {
        $password = New-Password -Length $Length
    }
    return $password
}
Export-ModuleMember -Function New-Password


# Create a string of random letters
# Note that this is not cryptographically secure but does give a verifiably flat distribution across lower-case letters
# ---------------------------------------------------------------------------------------------------------------------
function New-RandomLetters {
    param(
        [int]$Length = 20,
        [int]$Seed = 0,
        [string]$SeedPhrase = $null
    )
    if ($SeedPhrase -ne $null) {
        $Seed = [bigint](($SeedPhrase).ToCharArray() | % { [string][int]$_ } | Join-String) % [int32]::MaxValue
    }
    return ( -join ((97..122) | Get-Random -SetSeed $Seed -Count $Length | % { [char]$_ }))

}
Export-ModuleMember -Function New-RandomLetters


# Ensure that a password is in the keyvault
# -----------------------------------------
function Resolve-KeyVaultSecret {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of secret")]
        [ValidateNotNullOrEmpty()]
        [string]$SecretName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of key vault this secret belongs to")]
        [ValidateNotNullOrEmpty()]
        [string]$VaultName,
        [Parameter(Mandatory = $false, HelpMessage = "Default value for this secret")]
        [string]$DefaultValue,
        [Parameter(Mandatory = $false, HelpMessage = "Default number of random characters to be used when initialising this secret")]
        [string]$DefaultLength,
        [Parameter(Mandatory = $false, HelpMessage = "Overwrite any existing secret with this name")]
        [switch]$ForceOverwrite,
        [Parameter(Mandatory = $false, HelpMessage = "Retrieve secret as plaintext instead of as a secure string")]
        [switch]$AsPlaintext
    )
    # Create a new secret if one does not exist in the key vault or if we are forcing an overwrite
    if ($ForceOverwrite -or (-not (Get-AzKeyVaultSecret -Name $SecretName -VaultName $VaultName))) {
        # If no default is provided then we cannot generate a secret
        if ((-not $DefaultValue) -and (-not $DefaultLength)) {
            Add-LogMessage -Level Fatal "Secret '$SecretName does not exist and no default value or length was provided!"
        }
        # If both defaults are provided then we do not know which to use
        if ($DefaultValue -and $DefaultLength) {
            Add-LogMessage -Level Fatal "Both a default value and a default length were provided. Please only use one of these options!"
        }
        # Generate a new password if there is no default value
        if (-not $DefaultValue) {
            $DefaultValue = $(New-Password -Length $DefaultLength)
        }
        # Store the password in the keyvault
        try {
            $null = Undo-AzKeyVaultSecretRemoval -Name $SecretName -VaultName $VaultName -ErrorAction SilentlyContinue # if the key has been soft-deleted we need to restore it before doing anything else
            Start-Sleep 10
            $null = Set-AzKeyVaultSecret -Name $SecretName -VaultName $VaultName -SecretValue (ConvertTo-SecureString $DefaultValue -AsPlainText -Force) -ErrorAction Stop
        } catch [Microsoft.Azure.KeyVault.Models.KeyVaultErrorException] {
            Add-LogMessage -Level Fatal "Failed to create '$SecretName' in key vault '$VaultName'" -Exception $_.Exception
        }
    }
    # Retrieve the secret from the key vault and return its value
    $secret = Get-AzKeyVaultSecret -Name $SecretName -VaultName $VaultName
    if ($AsPlaintext) { return $secret.SecretValue | ConvertFrom-SecureString -AsPlainText }
    return $secret.SecretValue
}
Export-ModuleMember -Function Resolve-KeyVaultSecret


# Purge a secret from the keyvault
# --------------------------------
function Remove-AndPurgeKeyVaultSecret {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of secret")]
        [ValidateNotNullOrEmpty()]
        [string]$SecretName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of key vault this secret belongs to")]
        [ValidateNotNullOrEmpty()]
        [string]$VaultName
    )
    Remove-AzKeyVaultSecret -VaultName $VaultName -Name $SecretName -Force -ErrorAction Stop
    # Wait up to five minutes for the secret to show up as purgeable
    for ($i = 0; $i -lt 30; $i++) {
        if (Get-AzKeyVaultSecret -VaultName $VaultName -Name $SecretName -InRemovedState) {
            Remove-AzKeyVaultSecret -VaultName $VaultName -Name $SecretName -InRemovedState -Force -ErrorAction Stop
            break
        }
        Start-Sleep -Seconds 10
    }
}
Export-ModuleMember -Function Remove-AndPurgeKeyVaultSecret
