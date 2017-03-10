<#
.SYNOPSIS
    Find a KMS host and activate windows.
.DESCRIPTION
    This Powershell script will look for a KMS host on your network and activate Windows on
    your local computer. It will set the domain on which the computer should scan for a KMS 
    host so even if the KMS host is migrated to another server it will still be able to renew
    the activation. Supported operating systems are Windows 7 (or Server 2008 R2) or higher.
.PARAMETER Domain
    This parameter is used to determine in which domain the script will search for the KMS host.
    Use the FQDN format. When not specified the script will assume the local domain.
.PARAMETER ClientKey
    KMS Client key to use for activation.
.PARAMETER AutoDetectKey
    Autodetect KMS Client key to use for activation. Needs internet connection.
.PARAMETER Force
    With this parameter you will not be prompted to continue if windows is already activated.
.NOTES
    Author: Michaja van der Zouwen
    Date: 19-12-2013
    
    The Get-ActivationStatus function was written by Bryan Lipscy and is available at
    http://social.technet.microsoft.com/wiki/contents/articles/5675.determine-windows-activation-status-with-powershell.aspx

    ChangeLog:
    ===========
    Version : 1.1
    Date    : 3-3-2017
    Changes : Better parameter support and replaced the list of client keys with a function to retreive a list from internet.

.EXAMPLE
    .\Activate-KMSClient -Domain contoso.com -ClientKey NPPR9-FWDCX-D2C8J-H872K-2YT43
    This will search the contoso.com domain for a KMS host and, when found, activate your windows OS suing the provided client key.
.EXAMPLE
    .\Activate-KMSClient -AutoDetectKey
    This will search the local computer's domain for a KMS host and, when found, activate your windows OS using the client key retreived from internet.
.LINK
    https://itmicah.wordpress.com/2013/12/20/auto-activate-a-non-domain-joined-windows-os-using-powershell-and-kms/
#>
function Activate-KMSClient
{

    [CmdletBinding(DefaultParameterSetName='Key',SupportsShouldProcess=$true)]
    param (
        # Domain to search (FQDN)
        [Parameter(Mandatory=$false,
                   ParameterSetName='Key')]
        [Parameter(Mandatory=$false,
                   ParameterSetName='AutoDetect')]
        [string]
        $Domain,

        [Parameter(Mandatory=$true,
                   ParameterSetName='Key')]
        [string]
        $ClientKey,

        [Parameter(ParameterSetName='AutoDetect')]
        [switch]
        $AutoDetectKey,

        [switch]
        $Force
    )

    #region Variables

    $hostname = hostname
    $KMSservice = Get-WMIObject -query "select * from SoftwareLicensingService"
    
    #endregion Variables

    #region Functions

    function IsAdministrator
    {
        $Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $Principal = New-Object System.Security.Principal.WindowsPrincipal($Identity)
        $Principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    }

    function Get-ActivationStatus
    {
        [CmdletBinding()]
        param(
            [Parameter(ValueFromPipeline = $true,
                       ValueFromPipelineByPropertyName = $true)]
            [string]
            $DNSHostName = $Env:COMPUTERNAME
        )
        process
        {
            try {
                $wpa = Get-WmiObject SoftwareLicensingProduct -ComputerName $DNSHostName `
                -Filter "ApplicationID = '55c92734-d682-4d71-983e-d6ec3f16059f'" `
                -Property LicenseStatus -ErrorAction Stop
            } catch {
                $status = New-Object ComponentModel.Win32Exception ($_.Exception.ErrorCode)
                $wpa = $null    
            }
            $out = New-Object psobject -Property @{
                ComputerName = $DNSHostName;
                Status = [string]::Empty;
            }
            if ($wpa) {
                :outer foreach($item in $wpa) {
                    switch ($item.LicenseStatus) {
                        0 {$out.Status = "Unlicensed"}
                        1 {$out.Status = "Licensed"; break outer}
                        2 {$out.Status = "Out-Of-Box Grace Period"; break outer}
                        3 {$out.Status = "Out-Of-Tolerance Grace Period"; break outer}
                        4 {$out.Status = "Non-Genuine Grace Period"; break outer}
                        5 {$out.Status = "Notification"; break outer}
                        6 {$out.Status = "Extended Grace"; break outer}
                        default {$out.Status = "Unknown value"}
                    }
                }
            } else {$out.Status = $status.Message}
            $out
        }
    }

    function Get-KMSClientKeys
    {
        Param ($Url = 'https://technet.microsoft.com/en-us/library/jj612867(v=ws.11).aspx')
        try
        {
            $Site = Invoke-WebRequest -Uri $Url -ErrorAction Stop
        }
        catch
        {
            throw "Unable to reach urkl '$Url'."
        }
        $Tables = @($Site.ParsedHtml.getElementsByTagName('TABLE'))
        foreach ($Table in $Tables)
        {
            Try
            {
                [xml]$XMLTable = $Table.innerHTML.ToString().Replace('scope=col','')
                $Cells = $XMLTable.GetElementsByTagName('TD')
                If ($Cells[0].'data-th' -eq 'Operating system edition')
                {
                    for ($i = 0; $i -lt $Cells.count; $i++)
                    { 
                        switch -w ($Cells[$i].'data-th')
                        {
                            Operating* {$OS = $Cells[$i].P}
                            KMS*       {
                                [pscustomobject]@{
                                    OperatingSystem = $OS
                                    KMSClientKey = $Cells[$i].P
                                }
                            }
                        }
                    }
                }
            }
            catch
            {}
        }
    }

    #endregion Functions

    #region Main

    If (!$Domain -and (Get-WmiObject Win32_ComputerSystem).PartOfDomain)
    {
        $Domain = (Get-WmiObject Win32_ComputerSystem).Domain
    }
    If (!$Domain -and !(Get-WmiObject Win32_ComputerSystem).PartOfDomain)
    {
        $Domain = Read-Host 'Domain (FQDN)'
    }
    IF ($Domain -notlike '*.*') {
        Throw 'You must specify a domain FQDN.'
    }

    # Check if script runs elevated

    If (!(IsAdministrator)) {
        throw "You must be administrator to run this script."
    }

    # Determine current activation status

    Write-Verbose "Determining current activation status"
    $Licensed = Get-ActivationStatus $hostname

    IF (($Licensed.status -eq 'Licensed') -and (!$Force)) {
        Write-Verbose 'Windows is already activated.'
        $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes",""
        $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No",""
        $choices = [System.Management.Automation.Host.ChoiceDescription[]]($yes,$no)
        $caption = "Warning!"
        $message = "Windows is already activated! Proceed anyway?"
        $result = $Host.UI.PromptForChoice($caption,$message,$choices,0)
        if($result -eq 1) { 
            Write-Error 'The script was cancelled.'
	    return
        }
        else {
            Write-Verbose 'Windows will be deactivated.'
            $Deactivate = $true
        }
    }
    elseif (($Licensed.status -eq 'Licensed') -and ($Force)){
        Write-Verbose 'Windows is already activated.'
        Write-Verbose 'Windows will be deactivated.'
        $Deactivate = $true
    }
    else {
        Write-Verbose 'Windows is not activated.'
    }

    # Find out if there is a KMS host on the domain

    $findkms = nslookup -type=srv _vlmcs._tcp.$domain 2>&1
    If ([string]$findkms -match '(?<=svr\s+hostname\s+=\s)(.+)')
    {
        $kmshost = $Matches[1].Split(' ')[0]
        Write-Verbose "KMS Host found: $kmshost"
    }
    else {
        throw 'No KMS host has been found. Please check the domain name.'
    }

    # Determine KMS client key to use
    If ($AutoDetectKey)
    {
        $OSversion = (Get-WmiObject -class Win32_OperatingSystem).Caption.Trim()
        Write-Verbose "Operating system is $OSversion"
        $KMSKeys = Get-KMSClientKeys
        foreach ($KMSKey in $KMSKeys)
        {
            $KMSobject = $KMSKey.OperatingSystem.Split(' ') | where {$_ -ne 'server'}
            $Caption = $OSversion.TrimStart('Microsoft ').Split(' ') | where {$_ -ne 'server'}
            $Compared = Compare $KMSobject $caption
            If ($Compared.SideIndicator -notcontains '<=')
            {
                $ClientKey = $KMSKey.KMSClientKey
                Write-Verbose "Found KMS OS: $($KMSKey.OperatingSystem)"
            }
        }
        IF (!$ClientKey) {
            throw "No KMS client key was found for operating system '$OSVersion'."
        }
        else {
            Write-Verbose "KMS client key is $ClientKey"
        }
    }

    # Deactivate Windows if necessary
    IF ($Deactivate) {
        if ($pscmdlet.ShouldProcess($hostname, "Deactivating Windows"))
        {
            Write-Verbose 'Deactivating windows.'
            $result = cscript $env:windir\System32\slmgr.vbs /upk 2>&1
            Write-Verbose ($result | Select-String 'key')
            $Licensed = Get-ActivationStatus $hostname
            IF ($Licensed.status -eq 'Licensed') {
                Write-Warning 'Windows deactivation failed.'
            }
        }
    }

    # Activate Windows
    if ($pscmdlet.ShouldProcess($hostname, "Activating Windows"))
    {
        Write-Verbose 'Activating Windows.'
        $null = $KMSservice.InstallProductKey($ClientKey)
        IF (($KMSservice | gm -Name SetKeyManagementServiceLookupDomain) -ne $null) {
            $null = $KMSservice.SetKeyManagementServiceLookupDomain($Domain)
        }
        else {
            $null = $KMSservice.SetKeyManagementServiceMachine($kmshost)
        }
        $null = $KMSservice.RefreshLicenseStatus()

        Write-Verbose 'Checking if Windows is activated...'
        sleep -Seconds 1
        $Licensed = Get-ActivationStatus $hostname

        if ($Licensed.Status -eq 'Notification') 
        {
            Write-Verbose 'Forcing activation using slmgr script...'
            $null = cscript $env:windir\System32\slmgr.vbs /ato 2>&1
        }
        elseif ($Licensed.status -ne 'Licensed') {
            Write-Verbose 'Server not activated yet. Retrying.'
            $KMSservice.RefreshLicenseStatus()
        }
        else {
            return $Licensed
        }

        sleep -Seconds 2
        $Licensed = Get-ActivationStatus $hostname

        IF ($Licensed.status -ne 'Licensed') {
            Write-Error 'Windows activation failed.'
            $Licensed
        }
        else {
            return $Licensed
        }
    }
    #endregion Main
}
