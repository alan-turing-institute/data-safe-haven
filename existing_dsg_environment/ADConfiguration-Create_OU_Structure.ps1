# Create OUs

$domainname = "DOMAIN" # Active Directory Domain Name

New-ADOrganizationalUnit -Name "$domainname Data Servers" -Description "Data Servers"
New-ADOrganizationalUnit -Name "$domainname RDS Session Servers" -Description "RDS Session Servers"
New-ADOrganizationalUnit -Name "$domainname Research Users" -Description "Reseach Users"
New-ADOrganizationalUnit -Name "$domainname Security Groups" -Description "Security Groups"
New-ADOrganizationalUnit -Name "$domainname Service Accounts" -Description "Service Accounts"
New-ADOrganizationalUnit -Name "$domainname Service Servers" -Description "Service Servers"