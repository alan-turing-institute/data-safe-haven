param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "DSG fully qualified domain name")]
  [string]$dsgFqdn,
  [Parameter(Position=1, Mandatory = $true, HelpMessage = "SHM fully qualified domain name")]
  [string]$shmFqdn
)

# Set locale
Write-Output "Setting locale"
Set-WinHomeLocation -GeoId 0xf2
Set-TimeZone -Name "GMT Standard Time"
Set-WinSystemLocale en-GB
Set-Culture en-GB
Set-WinUserLanguageList -LanguageList (New-WinUserLanguageList -Language en-GB) -Force

# Set DNS defaults
Write-Output "Setting DNS suffixes"
$suffixes = "$dsgFqdn", "$shmFqdn"
$class = [wmiclass]'Win32_NetworkAdapterConfiguration'
$class.SetDNSSuffixSearchOrder($suffixes)