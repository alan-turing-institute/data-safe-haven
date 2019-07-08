param(
  [string]$uri,
  [string]$sasToken
)

$URI= $($uri + $sasToken);

Invoke-WebRequest -Uri $URI -OutFile C:/Scripts/SHM_DC.zip
Expand-Archive C:/Scripts/SHM_DC.zip -DestinationPath C:\Scripts\
# Write-Host (Get-ChildItem -Path C:/Scripts/)

