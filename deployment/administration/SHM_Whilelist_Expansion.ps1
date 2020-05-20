param(
	[Parameter(Mandatory = $true, HelpMessage = "Name of whitelist to use")]
	[string]$whitelistName
)

$PackageList = Get-Content (Join-Path $PSScriptRoot '..' '..' 'environment_configs' 'package_lists' $WhitelistName)

function Get-Versions {
	# $Version = Invoke-RestMethod -URI https://...
	# $Version.versions | ForEach-Object {$_.number}
	# https://docs.microsoft.com/en-us/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands?view=powershell-7
	param(
		[Parameter(Position = 0, Mandatory = $true, HelpMessage = "Name of network security group rule to deploy")]
		$Name
		)
		$response = Invoke-RestMethod -URI https://libraries.io/api/PYPI/${Name}?api_key=<redacted>
		return $response.versions | ForEach-Object {$_.number}
	}

function Get-Dependencies {
	# $Version = Invoke-RestMethod -URI https://...
	# $Version.versions | ForEach-Object {$_.number}
	# https://docs.microsoft.com/en-us/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands?view=powershell-7
	param(
		[Parameter(Mandatory = $true, HelpMessage = "Name of network security group rule to deploy")]
		$Platform,
		[Parameter(Mandatory = $true, HelpMessage = "Name of network security group rule to deploy")]
		$Name,
		[Parameter(Mandatory = $true, HelpMessage = "Name of network security group rule to deploy")]
		$Version
		)
		$response = Invoke-RestMethod -URI https://libraries.io/api/${Platform}/${Name}/${Version}/dependencies?api_key=<redacted>
		return $response.dependencies | ForEach-Object {$_.name}
	}

foreach ($Package in $PackageList[0..2]) {
	$Versions = Get-Versions $Package
	foreach ($Version in $Versions) {
		Get-Dependencies -Platform pypi -Name $Package -Version $Version
	}
}
