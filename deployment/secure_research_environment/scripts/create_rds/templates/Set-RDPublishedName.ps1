[CmdletBinding()]
Param(
   [Parameter(Mandatory=$True,HelpMessage="Specifies the FQDN that clients will use when connecting to the deployment.",Position=1)]
   [string]$ClientAccessName,
   [Parameter(Mandatory=$False,HelpMessage="Specifies the RD Connection Broker server for the deployment.",Position=2)]
   [string]$ConnectionBroker="localhost"
)

$CurrentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
If (($CurrentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) -eq $false)
{
    $ArgumentList = "-noprofile -noexit -file `"{0}`" -ClientAccessName $ClientAccessName -ConnectionBroker $ConnectionBroker"
    Start-Process powershell.exe -Verb RunAs -ArgumentList ($ArgumentList -f ($MyInvocation.MyCommand.Definition))
    Exit
}

Function Get-RDMSDeployStringProperty ([string]$PropertyName, [string]$BrokerName)
{
    $ret = iwmi -Class "Win32_RDMSDeploymentSettings" -Namespace "root\CIMV2\rdms" -Name "GetStringProperty" `
        -ArgumentList @($PropertyName) -ComputerName $BrokerName `
        -Authentication PacketPrivacy -ErrorAction Stop
    Return $ret.Value
}

Try
{
    If ((Get-RDMSDeployStringProperty "DatabaseConnectionString" $ConnectionBroker) -eq $null) {$BrokerInHAMode = $False} Else {$BrokerInHAMode = $True}
}
Catch [System.Management.ManagementException]
{
    If ($Error[0].Exception.ErrorCode -eq "InvalidNamespace")
    {
        If ($ConnectionBroker -eq "localhost")
        {
            Write-Host "`n Set-RDPublishedName Failed.`n`n The local machine does not appear to be a Connection Broker.  Please specify the`n FQDN of the RD Connection Broker using the -ConnectionBroker parameter.`n" -ForegroundColor Red
        }
        Else
        {
            Write-Host "`n Set-RDPublishedName Failed.`n`n $ConnectionBroker does not appear to be a Connection Broker.  Please make sure you have `n specified the correct FQDN for your RD Connection Broker server.`n" -ForegroundColor Red
        }
    }
    Else
    {
        $Error[0]
    }
    Exit
}

$OldClientAccessName = Get-RDMSDeployStringProperty "DeploymentRedirectorServer" $ConnectionBroker

If ($BrokerInHAMode.Value)
{
    Import-Module RemoteDesktop
    Set-RDClientAccessName -ConnectionBroker $ConnectionBroker -ClientAccessName $ClientAccessName
}
Else
{
    $return = iwmi -Class "Win32_RDMSDeploymentSettings" -Namespace "root\CIMV2\rdms" -Name "SetStringProperty" `
        -ArgumentList @("DeploymentRedirectorServer",$ClientAccessName) -ComputerName $ConnectionBroker `
        -Authentication PacketPrivacy -ErrorAction Stop
    $wksp = (gwmi -Class "Win32_Workspace" -Namespace "root\CIMV2\TerminalServices" -ComputerName $ConnectionBroker)
    $wksp.ID = $ClientAccessName
    $wksp.Put()|Out-Null
}

$CurrentClientAccessName = Get-RDMSDeployStringProperty "DeploymentRedirectorServer" $ConnectionBroker

If ($CurrentClientAccessName -eq $ClientAccessName)
{
    Write-Host "`n Set-RDPublishedName Succeeded." -ForegroundColor Green
    Write-Host "`n     Old name:  $OldClientAccessName`n`n     New name:  $CurrentClientAccessName"
    Write-Host "`n If you are currently logged on to RD Web Access, please refresh the page for the change to take effect.`n"
}
Else
{
    Write-Host "`n Set-RDPublishedName Failed.`n" -ForegroundColor Red
}