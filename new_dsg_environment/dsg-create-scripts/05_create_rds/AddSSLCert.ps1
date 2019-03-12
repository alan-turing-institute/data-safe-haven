Param(
  [Parameter(Mandatory = $true, 
             HelpMessage="Enter PFX for SSL cert")]
  [ValidateNotNullOrEmpty()]
  [string]$sslpassword,

    [Parameter(Mandatory = $true, 
             HelpMessage="Enter PFX for SSL cert")]
  [ValidateNotNullOrEmpty()]
  [string]$domain,

  [Parameter(Mandatory = $true, 
             HelpMessage="Enter the location and filename for the PFX file i.e c:\temp\sslcert.pfx")]
  [ValidateNotNullOrEmpty()]
  [string]$certpathname
)

#Add SSL certificate to environment
$password = ConvertTo-SecureString -String $sslpassword -AsPlainText -Force 
Set-RDCertificate -Role RDPublishing -ImportPath $certpathname  -Password $password -ConnectionBroker rds.$domain.co.uk -Force
Set-RDCertificate -Role RDRedirector -ImportPath $certpathname -Password $password -ConnectionBroker rds.$domain.co.uk -Force
Set-RDCertificate -Role RDWebAccess -ImportPath $certpathname -Password $password -ConnectionBroker rds.$domain.co.uk -Force
Set-RDCertificate -Role RDGateway -ImportPath $certpathname  -Password $password -ConnectionBroker rds.$domain.co.uk -Force

