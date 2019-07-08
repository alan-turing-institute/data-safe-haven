# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in 
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# Fror details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
  $configJson
)

# The cmdkey utility is a command-line (rather than PowerShell) tool. We use Invoke-Expression to allow us to 
# consume the appropriate values from the storage account variables. The value given to the add parameter of the
# cmdkey utility is the host address for the storage account, <storage-account>.file.core.windows.net for Azure 
# Public Regions. $storageAccount.Context.FileEndpoint is used because non-Public Azure regions, such as sovereign 
# clouds or Azure Stack deployments, will have different hosts for Azure file shares (and other storage resources).
Invoke-Expression -Command ("cmdkey /add:dsgtestbartifacts.file.core.windows.net /user:Azure\dsgtestbartifacts /pass:OFy1QJKpPOLVV13RfvlxRelV3wkEg2tH3LQM7CGzEfpLuIyiqSVeunppWt22OSA3AIXHu0PwnxwiwnAZjCd4/A==
net use Z: \\dsgtestbartifacts.file.core.windows.net\scripts /persistent:Yes")

Expand-Archive Z:/dc/SHM_DC.zip -DestinationPath c:\Scripts\

Write-Host (Get-ChildItem -Path c:\Scripts\)

