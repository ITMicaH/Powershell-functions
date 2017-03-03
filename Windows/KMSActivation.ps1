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
.PARAMETER Force
    With this parameter you will not be prompted to continue if windows is already activated.
.NOTES
    Author: Michaja van der Zouwen
    Date: 19-12-2013
    
    The Get-ActivationStatus function was written by Bryan Lipscy and is available at
    http://social.technet.microsoft.com/wiki/contents/articles/5675.determine-windows-activation-status-with-powershell.aspx
.EXAMPLE
    .\Activate-KMSClient -Domain contoso.com
    This will search the contoso.com domain for a KMS host and, when found, activate your windows OS.
.LINK
http://itmicah.wordpress.com/

#>
function Activate-KMSClient
{

    [CmdletBinding(SupportsShouldProcess=$true)]
    param (
        # Domain to search (FQDN)
        [string]
        $Domain = $env:USERDNSDOMAIN,

        [switch]
        $Force
    )

    #region Variables

    $hostname = hostname
    $KMSservice = Get-WMIObject -query "select * from SoftwareLicensingService"
    
    #endregion Variables

    #region Functions

    function IsAdministrator {
        $Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $Principal = New-Object System.Security.Principal.WindowsPrincipal($Identity)
        $Principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    }

    function Get-ActivationStatus {
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

    #endregion Functions

    #region Main

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
    [regex]$regex = '.+?\.' + ($Domain -replace '\.','\.')
    $kmshost = $regex.Matches($findkms) | ForEach-Object {$_.value} | select -Last 1

    IF ($kmshost -match "can't find") {
        throw 'No KMS host has been found. Please check the domain name.'
    }
    else {
        $kmshost = $kmshost -replace ' '
        Write-Verbose "KMS Host found: $kmshost"
    }

    # Determine KMS client key to use

    $OSversion = (Get-WmiObject -class Win32_OperatingSystem).Caption
    Write-Verbose "Operating system is $OSversion"

    switch -Regex ($OSversion) {
        'Windows 8.1 Professional N'                     {$key = 'HMCNV-VVBFX-7HMBH-CTY9B-B4FXY';break}
        'Windows 8.1 Professional'                       {$key = 'GCRJD-8NW9H-F2CDX-CCM8D-9D6T9';break}
        'Windows 8.1 Enterprise N'                       {$key = 'TT4HM-HN7YT-62K67-RGRQJ-JFFXW';break}
        'Windows 8.1 Enterprise'                         {$key = 'MHF9N-XY6XB-WVXMC-BTDCT-MKKG7';break}
        'Windows Server 2012 R2 Standard'                {$key = 'D2N9P-3P6X9-2R39C-7RTCD-MDVJX';break}
        'Windows Server 2012 R2 Datacenter'              {$key = 'W3GGN-FT8W3-Y4M27-J84CP-Q3VJ9';break}
        'Windows Server 2012 R2 Essentials'              {$key = 'KNC87-3J2TX-XB4WP-VCPJV-M4FWM';break}
        'Windows 8 Professional N'                       {$key = 'XCVCF-2NXM9-723PB-MHCB7-2RYQQ';break}
        'Windows 8 Professional'                         {$key = 'NG4HW-VH26C-733KW-K6F98-J8CK4';break}
        'Windows 8 Enterprise N'                         {$key = 'JMNMF-RHW7P-DMY6X-RF3DR-X2BQT';break}
        'Windows 8 Enterprise'                           {$key = '32JNW-9KQ84-P47T8-D8GGY-CWCK7';break}
        'Windows Server 2012 Standard'                   {$key = 'XC9B7-NBPP2-83J2H-RHMBY-92BT4';break}
        'Windows Server 2012 Single Language'            {$key = '2WN2H-YGCQR-KFX6K-CD6TF-84YXQ';break}
        'Windows Server 2012 Country Specific'           {$key = '4K36P-JN4VD-GDC6V-KDT89-DYFKP';break}
        'Windows Server 2012 Server Standard'            {$key = 'XC9B7-NBPP2-83J2H-RHMBY-92BT4';break}
        'Windows Server 2012 MultiPoint Standard'        {$key = 'HM7DN-YVMH3-46JC3-XYTG7-CYQJJ';break}
        'Windows Server 2012 MultiPoint Premium'         {$key = 'XNH6W-2V9GX-RGJ4K-Y8X6F-QGJ2G';break}
        'Windows Server 2012 Datacenter'                 {$key = '48HP8-DN98B-MYWDG-T2DCC-8W83P';break}
        'Windows Server 2012 N'                          {$key = '8N2M2-HWPGY-7PGT9-HGDD8-GVGGY';break}
        'Windows Server 2012'                            {$key = 'BN3D2-R7TKB-3YPBD-8DRP2-27GG4';break}
        'Windows 7 Professional N'                       {$key = 'MRPKT-YTG23-K7D7T-X2JMM-QY7MG';break}
        'Windows 7 Professional E'                       {$key = 'W82YF-2Q76Y-63HXB-FGJG9-GF7QX';break}
        'Windows 7 Professional'                         {$key = 'FJ82H-XT6CR-J8D7P-XQJJ2-GPDD4';break}
        'Windows 7 Enterprise N'                         {$key = 'YDRBP-3D83W-TY26F-D46B2-XCKRJ';break}
        'Windows 7 Enterprise E'                         {$key = 'C29WB-22CC8-VJ326-GHFJW-H9DH4';break}
        'Windows 7 Enterprise'                           {$key = '33PXH-7Y6KF-2VJC9-XBBR8-HVTHH';break}
        'Windows Server 2008 R2 Web'                     {$key = '6TPJF-RBVHG-WBW2R-86QPH-6RTM4';break}
        'Windows Server 2008 R2 HPC edition'             {$key = 'TT8MH-CG224-D3D7Q-498W2-9QCTX';break}
        'Windows Server 2008 R2 Standard'                {$key = 'YC6KT-GKW9T-YTKYR-T4X34-R7VHC';break}
        'Windows Server 2008 R2 Enterprise'              {$key = '489J6-VHDMP-X63PK-3K798-CPX3Y';break}
        'Windows Server 2008 R2 Datacenter'              {$key = '74YFP-3QFB3-KQT8W-PMXWJ-7M648';break}
        'Windows Server 2008 R2 for Itanium'             {$key = 'GT63C-RJFQ3-4GMB6-BRFB9-CB83V';break}
        'Windows Vista Business N'                       {$key = 'HMBQG-8H2RH-C77VX-27R82-VMQBT';break}
        'Windows Vista Business'                         {$key = 'YFKBB-PQJJV-G996G-VWGXY-2V3X8';break}
        'Windows Vista Enterprise N'                     {$key = 'VTC42-BM838-43QHV-84HX6-XJXKV';break}
        'Windows Vista Enterprise'                       {$key = 'VKK3X-68KWM-X2YGT-QR4M6-4BWMV';break}
        'Windows Web Server 2008'                        {$key = 'WYR28-R7TFJ-3X2YQ-YCY4H-M249D';break}
        'Windows Server 2008 Standard without Hyper-V'   {$key = 'W7VD6-7JFBR-RX26B-YKQ3Y-6FFFJ';break}
        'Windows Server 2008 Standard'                   {$key = 'TM24T-X9RMF-VWXK6-X8JC9-BFGM2';break}
        'Windows Server 2008 Enterprise without Hyper-V' {$key = '39BXF-X8Q23-P2WWT-38T2F-G3FPG';break}
        'Windows Server 2008 Enterprise'                 {$key = 'YQGMW-MPWTJ-34KDK-48M3W-X4Q6V';break}
        'Windows Server 2008 HPC'                        {$key = 'RCTX3-KWVHP-BR6TB-RB6DM-6X7HP';break}
        'Windows Server 2008 Datacenter without Hyper-V' {$key = '22XQ2-VRXRG-P8D42-K34TD-G3QQC';break}
        'Windows Server 2008 Datacenter'                 {$key = '7M67G-PC374-GR742-YH8V4-TCBY3';break}
        'Windows Server 2008 for Itanium-Based Systems'  {$key = '4DWFP-JF3DJ-B7DTH-78FJB-PDRHK';break}
    }

    IF (!$key) {
        throw "No KMS client key was found for operating system '$OSVersion'."
    }
    else {
        Write-Verbose "KMS client key is $key"
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
        $null = $KMSservice.InstallProductKey($key)
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
