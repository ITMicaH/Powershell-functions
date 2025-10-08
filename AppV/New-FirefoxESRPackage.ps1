# variables
$SoftwareName = 'Mozilla Firefox'
$DownloadUrl = 'https://download.mozilla.org/?product=firefox-esr-next-latest-ssl&os=win64&lang=nl'
#$DownloadUrl = 'https://download.mozilla.org/?product=firefox-esr-latest-ssl&os=win64&lang=nl'
$ReleaseNotesUrl = 'https://www.mozilla.org/nl/firefox/organizations/notes/'
$GPOUrl = 'https://github.com/mozilla/policy-templates/releases/latest'

# contstants
$AppVRepo = "\\Server\AppVRepo$\$SoftwareName"
$AppVShare = '\\Server\dfs\AppV'
$Proxy = 'proxy02:8080'

#region functions

function Get-LatestFireFoxESR
{
    [CmdletBinding()]
    Param(
        $DownloadUrl,
        $ReleaseNotesUrl,
        $Proxy
    )
    $ReleaseNotes = Invoke-WebRequest -Uri $ReleaseNotesUrl -Proxy http://$Proxy -ProxyUseDefaultCredentials
    $VersionLine = ($ReleaseNotes.Content -Split "`n") -match 'data-esr-versions'
    If ($VersionLine[0] -match 'data-esr-versions="(?<Version>[^"]+)"')
    {
        $Version = $Matches.Version
    }
    else
    {
        Write-Error "Unable to find correct Firefox ESR version" -Category ObjectNotFound -ErrorAction Stop
    }
    If ($Version -match '\s')
    {
        #Start-Process https://www.mozilla.org/nl/firefox/all/#product-desktop-esr
        #Write-Error "Multiple versions detected: $($Version -join ' & '). Please download correct version to C:\Temp and run this script again."
        #pause
        #exit 1
        $Version = $Version.Split(' ') | sort | Select -Last 1
    }
    else
    {
        $DownloadUrl = $DownloadUrl.Replace('-next','')
    }
    $File = "C:\Temp\Firefox Setup $version`esr.exe"
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $File -Proxy http://$Proxy -ProxyUseDefaultCredentials
    [pscustomobject]@{
        File = (Get-Item $File)
        Version = $Version
    }
}

function Get-PolicyTemplates
{
    Param(
        $GPOUrl,
        $Path,
        $Proxy
    )
    $Templates = Invoke-WebRequest -Uri $GPOUrl -Proxy http://$Proxy -ProxyUseDefaultCredentials
    $Ziplinks = ($Templates.Content -split "`n") -match 'href=".+\.zip'
    If ($Ziplinks[0] -match 'href="(?<SubUrl>.+\.zip)"')
    {
        $DownloadUrl = "https://github.com" + $Matches.SubUrl
        $File = $DownloadUrl.Split('/')[-1]
    }
    else
    {
        if ($Release = $Templates.Links | where href -like '/mozilla/policy-templates/releases/tag/*')
        {
            $DownloadUrl = "https://github.com/mozilla/policy-templates/releases/download/$($Release.innerText.Trim())/policy_templates_$($Release.innerText.Trim()).zip"
            $File = $DownloadUrl.Split('/')[-1]
        }
        else
        {
            Write-Error "Unable to find latest GPO link" -Category ObjectNotFound -ErrorAction Stop
        }
    }
    If (Test-Path "$Path\$($File.TrimEnd('.zip'))")
    {
        Write-Warning "Latest GPO is already present"
    }
    else
    {
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $Path\$File -Proxy http://$Proxy -ProxyUseDefaultCredentials
        Expand-Archive -Path $Path\$File -DestinationPath "$Path\$($File.TrimEnd('.zip'))"
    }
}

function Create-INIFile
{
    $Content = @(
        '[Install]',
        'InstallDirectoryName=Mozilla Firefox',
        'QuickLaunchShortcut=false',
        'DesktopShortcut=false',
        'StartMenuShortcuts=true',
        'MaintenanceService=false'
    )
    $Content | Out-File C:\Temp\FirefoxSilentInstall.ini
    Get-Item C:\Temp\FirefoxSilentInstall.ini
}

function Move2Repo
{
    Param(
        $Path,
        $Installer,
        $INIFile,
        $Package
    )
    If (!($Destination = Get-Item "$Path\Software\v$($Installer.version) ESR" -ErrorAction SilentlyContinue))
    {
        $Destination = New-Item "$Path\Software\v$($Installer.version) ESR" -ItemType Directory
    }
    Move-Item $Installer.File -Destination $Destination -Force
    Move-Item $INIFile -Destination $Destination -Force
    If (!($Destination = Get-Item "$Path\Packages\$Package" -ErrorAction SilentlyContinue))
    {
        $Destination = New-Item "$Path\Packages\$Package" -ItemType Directory
    }
    Copy-Item C:\Temp\$Package\*.* -Destination $Destination -Force
}

# Is the session elevated
function IsElevated
{
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Disable shortcuts in the App-V configuration files
function Disable-AppVShortcuts
{
    Param(
        # Path to the package
        [string]
        $PackagePath
    )
    
    If (Test-Path $PackagePath)
    {
        foreach ($File in (Get-ChildItem -Path $PackagePath -Filter *Config.xml))
        {
            [xml]$XML = Get-Content $File.FullName
            $XML.GetElementsByTagName('Shortcuts')[0].Enabled = 'false'
            $XML.GetElementsByTagName('FileTypeAssociations')[0].Enabled = 'false'
            $XML.Save($File.FullName)
        }
    }
    else
    {
        Write-Error "Unable to find package $PackagePath" -Category ObjectNotFound
    }
}

#endregion functions

#region Main
$script = $MyInvocation.MyCommand.Definition
$ps     = Join-Path $PSHome 'powershell.exe'

$isLocalAdmin = IsElevated

if (!$isLocalAdmin) 
{
    Start-Process $ps -Verb runas -ArgumentList "& '$script'"
    exit
}
Write-Progress -Activity "Package $SoftwareName" -CurrentOperation "Downloading latest version"
if ($Download = Get-Item "C:\Temp\Firefox*.exe")
{
    $Installer = [pscustomobject]@{
        File = $Download
        Version = ([regex]'\d+\.\d+\.?\d*').Matches($Download.BaseName).Value
    }
}
else
{
    $Installer = Get-LatestFireFoxESR -DownloadUrl $DownloadUrl -ReleaseNotesUrl $ReleaseNotesUrl -Proxy $Proxy -ErrorAction Stop
}
$INIFile = Create-INIFile
$PackageName = "Mozilla_Firefox_$($Installer.Version)_ESR"
$Params = @{
    Name = $PackageName
    PrimaryVirtualApplicationDirectory = "$env:ProgramFiles\Mozilla Firefox"
    Installer = $Installer.File
    InstallerOptions = "/INI=$INIFile"
    Path = 'C:\Temp'
}
Write-Progress -Activity "Package $SoftwareName" -CurrentOperation "Packaging application" -PercentComplete 20
New-AppvSequencerPackage @Params

If (Test-Path "C:\Temp\$PackageName")
{
    Write-Progress -Activity "Package $SoftwareName" -CurrentOperation "Disabling shortcuts" -PercentComplete 40
    Disable-AppVShortcuts -PackagePath "C:\Temp\$PackageName"

    Write-Progress -Activity "Package $SoftwareName" -CurrentOperation "Copying software files" -PercentComplete 60
    Move2Repo -Path $AppVRepo -Installer $Installer -Ini $INIFile -Package $PackageName

    Write-Progress -Activity "Package $SoftwareName" -CurrentOperation "Copying package files" -PercentComplete 80
    If (Test-Path $AppVShare\$PackageName)
    {
        Remove-Item $AppVShare\$PackageName -Recurse
    }
    Move-Item -Path C:\Temp\$PackageName -Destination $AppVShare
    Get-PolicyTemplates -GPOUrl $GPOUrl -Path $AppVRepo\GPO -Proxy $Proxy
}
else
{
    Write-Error 'Packaging failed' -Category InvalidResult
}
Write-Progress -Activity "Package $SoftwareName" -Completed

Read-Host -Prompt 'Press enter to continue'

#endregion Main
