Import-Module $PSScriptRoot/Logging.psm1

# Generate a random alphanumeric password
# ---------------------------------------
function New-Password {
    param(
        [int]$Length = 20
    )
    # Construct allowed character set
    $alphaNumeric = [char[]](1..127) -match "[0-9A-Za-z]" -join ""
    $rangeSize = $alphaNumeric.Length -1

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
# ---------------------------------
function New-RandomLetters {
    param(
        [int]$Length = 20,
        [int]$Seed = 0,
        [string]$SeedPhrase = $null
    )
    if ($SeedPhrase -ne $null) {
        $Seed = [bigint](($SeedPhrase).ToCharArray() | % { [string][int]$_ } | Join-String) % [int32]::MaxValue
    }
    return (-join ((97..122) | Get-Random -SetSeed $Seed -Count $Length | % {[char]$_}))

}
Export-ModuleMember -Function New-RandomLetters


# Ensure that a password is in the keyvault
# -----------------------------------------
function Resolve-KeyVaultSecret {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of secret")]
        [string]$SecretName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of key vault this secret belongs to")]
        [string]$VaultName,
        [Parameter(Mandatory = $false, HelpMessage = "Default value for this secret")]
        [string]$DefaultValue,
        [Parameter(Mandatory = $false, HelpMessage = "Default number of random characters to be used when initialising this secret")]
        [string]$DefaultLength
    )
    # Create a new secret if one does not exist in the key vault
    if (-not $(Get-AzKeyVaultSecret -VaultName $VaultName -Name $SecretName)) {
        # If no default is provided then we cannot generate a secret
        if ((-Not $DefaultValue) -And (-Not $DefaultLength)) {
            Add-LogMessage -Level Fatal "Secret '$SecretName does not exist and no default value or length was provided!"
        }
        # If both defaults are provided then we do not know which to use
        if ($DefaultValue -And $DefaultLength) {
            Add-LogMessage -Level Fatal "Both a default value and a default length were provided. Please only use one of these options!"
        }
        # Generate a new password if there is no default value
        if (-Not $DefaultValue) {
            $DefaultValue = $(New-Password -length $DefaultLength)
        }
        # Store the password in the keyvault
        $null = Set-AzKeyVaultSecret -VaultName $VaultName -Name $SecretName -SecretValue (ConvertTo-SecureString $DefaultValue -AsPlainText -Force)
    }
    # Retrieve the secret from the key vault and return its value
    $secret = Get-AzKeyVaultSecret -VaultName $VaultName -Name $SecretName
    return $secret.SecretValueText
}
Export-ModuleMember -Function Resolve-KeyVaultSecret
