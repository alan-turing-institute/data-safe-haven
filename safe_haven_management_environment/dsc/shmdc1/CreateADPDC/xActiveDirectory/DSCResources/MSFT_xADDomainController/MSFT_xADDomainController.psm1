#
# xADDomainController: DSC resource to install a domain controller in Active
# Directory.
#

## Import the common AD functions
$adCommonFunctions = Join-Path `
    -Path (Split-Path -Path $PSScriptRoot -Parent) `
    -ChildPath '\MSFT_xADCommon\MSFT_xADCommon.psm1'
Import-Module -Name $adCommonFunctions

<#
    .SYNOPSIS
        Returns the current state of the certificate that may need to be requested.

    .PARAMETER DomainName
        Provide the FQDN of the domain the Domain Controller is being added to.

    .PARAMETER DomainAdministrationCredential
        Provide the Domain Admin credentials to be able to promote a new Domain Controller. This is a PSCredential.

    .PARAMETER SafemodeAdministratorPassword
        Provide a password that will be used to set the DSRM password. This is a PSCredential.

    .PARAMETER DatabasePath
        Provide the path where the NTDS.dit will be created and stored.

    .PARAMETER LogPath
        Provide the path where the logs for the NTDS will be created and stored.

    .PARAMETER SysvolPath
        Provide the path where the Sysvol will be created and stored.

    .PARAMETER SiteName
        Provide the name of the site you want the Domain Controller to be added to.
#>
function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $DomainName,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $DomainAdministratorCredential,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $SafemodeAdministratorPassword,

        [Parameter()]
        [System.String]
        $DatabasePath,

        [Parameter()]
        [System.String]
        $LogPath,

        [Parameter()]
        [System.String]
        $SysvolPath,

        [Parameter()]
        [System.String]
        $SiteName
    )

    $returnValue = @{
        DomainName = $DomainName
        Ensure = $false
    }

    try
    {
        Write-Verbose -Message "Resolving '$($DomainName)' ..."
        $domain = Get-ADDomain -Identity $DomainName -Credential $DomainAdministratorCredential
        if ($null -ne $domain)
        {
            Write-Verbose -Message "Domain '$($DomainName)' is present. Looking for DCs ..."
            try
            {
                $dc = Get-ADDomainController -Identity $env:COMPUTERNAME -Credential $DomainAdministratorCredential
                Write-Verbose -Message "Found domain controller '$($dc.Name)' in domain '$($dc.Domain)'."
                if ($dc.Domain -eq $DomainName)
                {
                    Write-Verbose -Message "Current node '$($dc.Name)' is already a domain controller for domain '$($dc.Domain)'."

                    $serviceNTDS     = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters'
                    $serviceNETLOGON = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters'

                    $returnValue.Ensure       = $true
                    $returnValue.DatabasePath = $serviceNTDS.'DSA Working Directory'
                    $returnValue.LogPath      = $serviceNTDS.'Database log files path'
                    $returnValue.SysvolPath   = $serviceNETLOGON.SysVol -replace '\\sysvol$', ''
                    $returnValue.SiteName     = $dc.Site
                }
            }
            catch
            {
                if ($error[0]) {Write-Verbose $error[0].Exception}
                Write-Verbose -Message "Current node does not host a domain controller."
            }
        }
    }
    catch [System.Management.Automation.CommandNotFoundException]
    {
        if ($error[0]) {Write-Verbose $error[0].Exception}
        Write-Verbose -Message "Current node is not running AD WS, and hence is not a domain controller."
    }
    $returnValue
}

<#
    .SYNOPSIS
        Returns the current state of the certificate that may need to be requested.

    .PARAMETER DomainName
        Provide the FQDN of the domain the Domain Controller is being added to.

    .PARAMETER DomainAdministrationCredential
        Provide the Domain Admin credentials to be able to promote a new Domain Controller. This is a PSCredential.

    .PARAMETER SafemodeAdministratorPassword
        Provide a password that will be used to set the DSRM password. This is a PSCredential.

    .PARAMETER DatabasePath
        Provide the path where the NTDS.dit will be created and stored.

    .PARAMETER LogPath
        Provide the path where the logs for the NTDS will be created and stored.

    .PARAMETER SysvolPath
        Provide the path where the Sysvol will be created and stored.

    .PARAMETER SiteName
        Provide the name of the site you want the Domain Controller to be added to.

    .PARAMETER InstallationMediaPath
        Provide the path for the IFM folder that was created with ntdsutil.
        This should not be on a share but locally to the Domain Controller being promoted.
#>
function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $DomainName,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $DomainAdministratorCredential,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $SafemodeAdministratorPassword,

        [Parameter()]
        [System.String]
        $DatabasePath,

        [Parameter()]
        [System.String]
        $LogPath,

        [Parameter()]
        [System.String]
        $SysvolPath,

        [Parameter()]
        [System.String]
        $SiteName,

        [Parameter()]
        [System.String]
        $InstallationMediaPath
    )

    # Debug can pause Install-ADDSDomainController, so we remove it.
    $parameters = $PSBoundParameters.Remove("Debug")
    $parameters = $PSBoundParameters.Remove('InstallationMediaPath')
    $targetResource = Get-TargetResource @PSBoundParameters

    if ($targetResource.Ensure -eq $false)
    {
        ## Node is not a domain controllr so we promote it
        Write-Verbose -Message "Checking if domain '$($DomainName)' is present ..."
        $domain = $null;
        try
        {
            $domain = Get-ADDomain -Identity $DomainName -Credential $DomainAdministratorCredential
        }
        catch
        {
            if ($error[0]) {Write-Verbose $error[0].Exception}
            throw (New-Object -TypeName System.InvalidOperationException -ArgumentList "Domain '$($DomainName)' could not be found.")
        }

        Write-Verbose -Message "Verified that domain '$($DomainName)' is present, continuing ..."
        $params = @{
            DomainName = $DomainName
            SafeModeAdministratorPassword = $SafemodeAdministratorPassword.Password
            Credential = $DomainAdministratorCredential
            NoRebootOnCompletion = $true
            Force = $true
        }
        if ($DatabasePath -ne $null)
        {
            $params.Add("DatabasePath", $DatabasePath)
        }
        if ($LogPath -ne $null)
        {
            $params.Add("LogPath", $LogPath)
        }
        if ($SysvolPath -ne $null)
        {
            $params.Add("SysvolPath", $SysvolPath)
        }
        if ($SiteName -ne $null -and $SiteName -ne "")
        {
            $params.Add("SiteName", $SiteName)
        }
        if (-not [string]::IsNullOrWhiteSpace($InstallationMediaPath))
        {
            $params.Add("InstallationMediaPath", $InstallationMediaPath)
        }

        Install-ADDSDomainController @params
        Write-Verbose -Message "Node is now a domain controller for '$($DomainName)'."

        # Signal to the LCM to reboot the node to compensate for the one we
        # suppressed from Install-ADDSDomainController
        $global:DSCMachineStatus = 1
    }
    elseif ($targetResource.Ensure)
    {
        ## Node is a domain controller. We check if other properties are in desired state
        if ($PSBoundParameters["SiteName"] -and $targetResource.SiteName -ne $SiteName)
        {
            ## DC is not in correct site. Move it.
            Write-Verbose "Moving Domain Controller from '$($targetResource.SiteName)' to '$SiteName'"
            Move-ADDirectoryServer -Identity $env:COMPUTERNAME -Site $SiteName -Credential $DomainAdministratorCredential
        }
    }
}

<#
    .SYNOPSIS
        Returns the current state of the certificate that may need to be requested.

    .PARAMETER DomainName
        Provide the FQDN of the domain the Domain Controller is being added to.

    .PARAMETER DomainAdministrationCredential
        Provide the Domain Admin credentials to be able to promote a new Domain Controller. This is a PSCredential.

    .PARAMETER SafemodeAdministratorPassword
        Provide a password that will be used to set the DSRM password. This is a PSCredential.

    .PARAMETER DatabasePath
        Provide the path where the NTDS.dit will be created and stored.

    .PARAMETER LogPath
        Provide the path where the logs for the NTDS will be created and stored.

    .PARAMETER SysvolPath
        Provide the path where the Sysvol will be created and stored.

    .PARAMETER SiteName
        Provide the name of the site you want the Domain Controller to be added to.

    .PARAMETER InstallationMediaPath
        Provide the path for the IFM folder that was created with ntdsutil.
        This should not be on a share but locally to the Domain Controller being promoted.
#>
function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $DomainName,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $DomainAdministratorCredential,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $SafemodeAdministratorPassword,

        [Parameter()]
        [System.String]
        $DatabasePath,

        [Parameter()]
        [System.String]
        $LogPath,

        [Parameter()]
        [System.String]
        $SysvolPath,

        [Parameter()]
        [System.String]
        $SiteName,

        [Parameter()]
        [System.String]
        $InstallationMediaPath
    )

    if ($PSBoundParameters.SiteName)
    {
        if (-not (Test-ADReplicationSite -SiteName $SiteName -DomainName $DomainName -Credential $DomainAdministratorCredential))
        {
            throw (New-Object -TypeName System.InvalidOperationException -ArgumentList "Site '$($SiteName)' could not be found.")
        }
    }

    $isCompliant = $true

    try
    {
        $parameters = $PSBoundParameters.Remove("Debug")
        $parameters = $PSBoundParameters.Remove('InstallationMediaPath')
        $existingResource = Get-TargetResource @PSBoundParameters
        $isCompliant = $existingResource.Ensure

        if ([System.String]::IsNullOrEmpty($SiteName))
        {
            #If SiteName is not specified confgiuration is compliant
        }
        elseif ($existingResource.SiteName -ne $SiteName)
        {
            Write-Verbose "Domain Controller Site is not in a desired state. Expected '$SiteName', actual '$($existingResource.SiteName)'"
            $isCompliant = $false
        }
    }
    catch
    {
        if ($error[0]) {Write-Verbose $error[0].Exception}
        Write-Verbose -Message "Domain '$($DomainName)' is NOT present on the current node."
        $isCompliant = $false
    }

    $isCompliant

}

Export-ModuleMember -Function *-TargetResource
