Import-Module $PSScriptRoot/Logging.psm1

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
        [Parameter(Mandatory = $true, HelpMessage = "Name of secret")]
        [ValidateNotNullOrEmpty()]
        [string]$SecretName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of key vault this secret belongs to")]
        [ValidateNotNullOrEmpty()]
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
        try {
            $null = Set-AzKeyVaultSecret -VaultName $VaultName -Name $SecretName -SecretValue (ConvertTo-SecureString $DefaultValue -AsPlainText -Force) -ErrorAction Stop -ErrorVariable error
        } catch [Microsoft.Azure.KeyVault.Models.KeyVaultErrorException] {
            Add-LogMessage -Level Fatal "Failed to create '$SecretName' in key vault '$VaultName'"
        }
    }
    # Retrieve the secret from the key vault and return its value
    $secret = Get-AzKeyVaultSecret -VaultName $VaultName -Name $SecretName
    return $secret.SecretValueText
}
Export-ModuleMember -Function Resolve-KeyVaultSecret
