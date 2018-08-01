# Configure ADDS to create new forest

$domainnetbiosname = "DOMAIN" # Active Directory Domain Name

$domainname = "$domainnetbiosname.co.uk"
$databasepath = "E:\NTDS"
$domainmode = "7" # Server 2016
$forestmode = "7" # Server 2016
$sysvolpath = "E:\SYSVOL"

Install-ADDSForest  -DomainName $domainname `
                    -SafeModeAdministratorPassword (Read-Host -Prompt "DSRM Password:" -AsSecureString) `
                    -DatabasePath $databasepath `
                    -DomainMode $domainmode `
                    -DomainNetBIOSName $domainnetbiosname `
                    -ForestMode $forestmode `
                    -SYSVOLPath $sysvolpath