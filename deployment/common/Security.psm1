# Modified from the [System.Web.Security.Membership]::GeneratePassword() function
# Source : https://github.com/Microsoft/referencesource/blob/master/System.Web/Security/Membership.cs
# Needed because [System.Web.Security.Membership] is not in .NetCore so unavailable in Powershell 6
# Modifications:
# - Remove requirement for special characters (as these cause us problems when embedding in config files in our application)
# - Require at least one character from upper case, lower case and numeric character sets (using a "check and recurse" approach)
# ------------------------------------------------------------------------------------------------------------------------------
function New-Password {
    param(
        [int]$length = 20
    )
    [string]$password = "";
    [int]$index = 0;

    $buf = [System.Byte[]]::CreateInstance([System.Byte],$length);
    $cBuf = [System.Char[]]::CreateInstance([System.Char],$length);

    $cryptoRng = [System.Security.Cryptography.RandomNumberGenerator]::Create();
    $cryptoRng.GetBytes($buf);

    $numericEnd = 10
    $alphaUpperEnd = 36
    $numCharsInSet = 62

    # Convert random bytes into characters from permitted character set (lower alpha, upper alpha, numeric)
    for ([int]$iter = 0; $iter -lt $length; $iter++) {
        [int]$i = [int]($buf[$iter] % $numCharsInSet);
        if ($i -lt $numericEnd) {
            $cBuf[$iter] = [char](([System.Convert]::ToByte([int][char]'0')) + $i);
        }
        elseif ($i -lt $alphaUpperEnd) {
            $cBuf[$iter] = [char](([System.Convert]::ToByte([int][char]'A')) + $i - $numericEnd);
        }
        else {
            $cBuf[$iter] = [char](([System.Convert]::ToByte([int][char]'a')) + $i - $alphaUpperEnd);
        }
    }
    $password = -join $cBuf;

    # Require at least one of each character class
    $numNumeric = 0;
    $numAlphaUpper = 0;
    $numAlphaLower = 0;
    for ([int]$iter = 0; $iter -lt $length; $iter++) {
        [int]$i = [int]($buf[$iter] % $numCharsInSet);
        if ($i -lt $numericEnd) {
            $numNumeric++;
        }
        elseif ($i -lt $alphaUpperEnd) {
            $numAlphaUpper++;
        }
        else {
            $numAlphaLower++;
        }
    }
    if (($numNumeric -eq 0) -or ($numAlphaUpper -eq 0) -or ($numAlphaLower -eq 0)) {
        $password = New-Password ($length);
    }
    return $password;
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
        [string]$VaultName = "",
        [string]$SecretName = "",
        [string]$DefaultValue = "",
        [string]$DefaultLength = 20
    )
    if (-not $VaultName) {
        Add-LogMessage -Level Fatal "Vault name must not be empty."
    }
    if (-not $SecretName) {
        Add-LogMessage -Level Fatal "Secret name must not be empty."
    }
    # Create a new secret if one does not exist in the key vault
    if (-not $(Get-AzKeyVaultSecret -VaultName $VaultName -Name $SecretName)) {
        # Generate a new password if there is no default
        if ($DefaultValue -eq "") {
            $DefaultValue = $(New-Password -length $DefaultLength)
        }
        # Store the password in the keyvault
        $_ = Set-AzKeyVaultSecret -VaultName $VaultName -Name $SecretName -SecretValue (ConvertTo-SecureString $DefaultValue -AsPlainText -Force)
        if (-not $?) {
            Add-LogMessage -Level Fatal "Failed to create '$SecretName' in key vault '$VaultName'"
        }
    }
    # Retrieve the secret from the key vault and return its value
    $secret = Get-AzKeyVaultSecret -VaultName $VaultName -Name $SecretName
    return $secret.SecretValueText
}
Export-ModuleMember -Function Resolve-KeyVaultSecret
