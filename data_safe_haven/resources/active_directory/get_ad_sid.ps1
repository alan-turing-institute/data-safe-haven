$DomainControllerSID = $(Get-ADComputer -Filter * | ForEach-Object { $_.SID.Value } | Select-Object -First 1)
Write-Output "$($DomainControllerSID.Substring(0, $DomainControllerSID.Length - 5))"
