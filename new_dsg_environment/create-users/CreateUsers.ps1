Import-Csv .\UserCreate.csv | foreach-object { 
$userprinicpalname = $_.SamAccountName + "@sptest.local" #Change to required SPN for domain
New-ADUser  -SamAccountName $_.SamAccountName `
            -UserPrincipalName $userprinicpalname `
            -Name $_.displayname `
            -DisplayName $_.DisplayName `
            -GivenName $_.cn `
            -SurName $_.sn `
            -Department $_.Department `
            -Description $_.Description `
            -Path $_.Path `
            -AccountPassword (ConvertTo-SecureString $_.Password -AsPlainText -force) `
            -Enabled $True `
            -PasswordNeverExpires $False `
            -PassThru
             }