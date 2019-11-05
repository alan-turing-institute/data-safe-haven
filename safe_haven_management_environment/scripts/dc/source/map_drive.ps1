param(
  [string]$uri,
  [string]$sasToken
)

$URI= $($uri + $sasToken);


New-Item -Path "c:\" -Name "Scripts" -ItemType "directory"

Invoke-WebRequest -Uri $URI -OutFile C:/Scripts/SHM_DC.zip 
Expand-Archive C:/Scripts/SHM_DC.zip -DestinationPath C:\Scripts\ -Force
Write-Host (Get-ChildItem -Path C:/Scripts/)

