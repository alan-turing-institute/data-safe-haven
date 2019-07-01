param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "SSL certificate signed by Certificate Authority (in .pem ASCII format, inclding CA cert chain)")]
  [string]$cert,
  [Parameter(Position=1, Mandatory = $true, HelpMessage = "Filename to use when writing SSL certificate to disk")]
  [string]$certFilename,
  [Parameter(Position=2, Mandatory = $true, HelpMessage = "Remote folder to write SSL certificate to")]
  [string]$remoteDirectory
)

# Split certificate content back into lines
$certLines = $cert.Split('|')

Write-Output $certLines.Length

# Write certificate to file
$certDir = New-Item -ItemType Directory -Path $remoteDirectory -Force
$certPath = (Join-Path $certDir $certFilename)
if(Test-Path $certPath) {
  Remove-Item -Path $certPath -Force 
}
$certLines | ForEach-Object { Add-Content $_ -Path $certPath -Force }

Write-Output "Certificate written to $certPath"
