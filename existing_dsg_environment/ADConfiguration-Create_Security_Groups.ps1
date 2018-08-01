# Create security groups, update DOMAIN to the NetBios name of the domain
$domain = "DOMAIN" # Active Directory Domain Name

# Server administrators
New-ADGroup     -Name "SG $domain Server Administrators" -GroupScope Global -Description "SG $domain Server Administrators" -GroupCategory Security -Path "OU=$domain Security Groups,DC=$domain,DC=CO,DC=UK"
Add-ADGroupMember "SG $domain Server Administrators" "atiadmin" #Update domain name

# Research Users

New-ADGroup     -Name "SG $domain Research Users" -GroupScope Global -Description "SG $domain Research Users" -GroupCategory Security -Path "OU=$domain Security Groups,DC=$domain,DC=CO,DC=UK"
Add-ADGroupMember "SG $domain Research Users" "ACCOUNTNAME" # Account used for testing environment