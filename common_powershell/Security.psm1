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


# Ensure that a password is in the keyvault
# -----------------------------------------
function EnsureKeyvaultSecret {
    param(
        [string]$keyvaultName = "",
        [string]$secretName = "",
        [string]$defaultValue = "",
        [string]$length = 20
    )
    # Attempt to retrieve secret
    $secret = (Get-AzKeyVaultSecret -VaultName $keyvaultName -Name $secretName).SecretValueText;

    # Store default value in keyvault, then retrieve it
    if ($secret -eq $null) {
        # Generate a new password if there is no default
        if ($defaultValue -eq "") {
            $defaultValue = $(New-Password -length $length)
        }
        # Store the password in the keyvault
        $secretValue = (ConvertTo-SecureString $defaultValue -AsPlainText -Force);
        Set-AzKeyVaultSecret -VaultName $keyvaultName -Name $secretName -SecretValue $secretValue;
        $secret = (Get-AzKeyVaultSecret -VaultName $keyvaultName -Name $secretName).SecretValueText;
    }
    return $secret
}
Export-ModuleMember -Function EnsureKeyvaultSecret
