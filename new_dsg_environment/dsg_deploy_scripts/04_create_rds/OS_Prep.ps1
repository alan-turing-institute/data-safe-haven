 Param(
  [Parameter(Mandatory = $true, 
             HelpMessage="Enter Netbios name i.e. DSGROUP2")]
  [ValidateNotNullOrEmpty()]
  [string]$domain,

  [Parameter(Mandatory = $true, 
             HelpMessage="Enter FQDN of the Management Domain i.e. TURINGSAFEHAVEN.AC.UK")]
  [ValidateNotNullOrEmpty()]
  [string]$mgmtdomain
)

Set-WinHomeLocation -GeoId 0xf2
Set-TimeZone -Name "GMT Standard Time"
Set-WinSystemLocale en-GB
Set-Culture en-GB
Set-WinUserLanguageList -LanguageList (New-WinUserLanguageList -Language en-GB) -Force

write-Host -ForegroundColor Cyan "Language Settings Done"

Write-Host -ForegroundColor Green "Updating DNS suffixs"
$suffixes = "$domain.co.uk", $mgmtdomain
$class = [wmiclass]'Win32_NetworkAdapterConfiguration'
$class.SetDNSSuffixSearchOrder($suffixes)

Write-Host -ForegroundColor Green "All done!"