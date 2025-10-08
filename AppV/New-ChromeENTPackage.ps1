#variables
$SoftwareName = 'Google Chrome'
$DownloadUrl = 'https://support.google.com/chrome/a/answer/7650032?hl=nl'
$ReleaseNotesUrl = 'https://chromereleases.googleblog.com/'

#contstants
$AppVRepo = "\\Server\AppVRepo$\$SoftwareName"
$AppVShare = '\\Storage\dfs\AppV'
$Proxy = 'proxy:8080'

#region functions

function Get-LatestChromeEnterprise
{
    Param(
        $DownloadUrl,
        $ReleaseNotesUrl,
        $Proxy
    )
    $File = "C:\Temp\ChromeEnterprise.zip"
    If (!(Test-Path $File))
    {
        $DL = Invoke-WebRequest -Uri $DownloadUrl -Proxy http://$Proxy -ProxyUseDefaultCredentials -UseBasicParsing
        If ($DL.Content -match 'href=\"(?<Url>https://dl.google.com/[^\"]+Bundle64.zip[^\"]+)')
        {
            $DownloadLink = $Matches.Url
        }
        else
        {
            throw "Unable to retreive download url"
        }
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $DownloadLink -OutFile $File -Proxy http://$Proxy -ProxyUseDefaultCredentials
        $ProgressPreference = 'Continue'
    }
    If (!(Test-Path "C:\Temp\ChromeEnterprise"))
    {
        Expand-Archive -Path $File -DestinationPath "C:\Temp\ChromeEnterprise" -Force
    }
    $Content = Get-Content "C:\Temp\ChromeEnterprise\VERSION"
    $Version = $Content.ForEach{$_.Split('=')[1]} -join '.'
    $File = Rename-Item "C:\Temp\ChromeEnterprise" -NewName $Version -PassThru
    [pscustomobject]@{
        File = $File
        Version = $Version
    }
}

# Copy/Move files to the repository
function Move2Repo
{
    Param(
        $Path,
        $Installer,
        $Package
    )

    $Destination = Get-Item "$Path\Software"
    Move-Item $Installer.File -Destination $Destination -Force
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

# Disable shortcuts in an App-V configuration file
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

# Runs a powershell command with admin privilleges
function Invoke-ElevatedCommand
{
    [CmdletBinding()]
    [Alias('Elevate')]
    Param
    (
        # Command to run
        [Parameter(Mandatory=$true,
                   Position=0)]
        [string]
        $Command,

        # Parameters in hashtable format (like with splatting)
        [Parameter(Position=1)]
        [hashtable]
        $Parameters

    )

    If ($PSBoundParameters['Parameters'])
    {
        $Params = $Parameters.GetEnumerator().foreach{"-$($_.key) '$($_.value)'"} -join ' '
        $Script = "$Command $Params"
    }
    else
    {
        $Script = $Command
    }
    $ProcessParams = @{
        FilePath = 'powershell.exe'
        Verb = 'RunAs'
        ArgumentList = "-command & {$Script}"
        Wait = $true
        WindowStyle = 'Hidden'
    }
    Start-Process @ProcessParams
}

# Create installer batch file
function New-BatchFile
{
    Param($Installer)
    $Content = @(
        "msiexec /i `"$($Installer.File)\Installers\GoogleChromeStandaloneEnterprise64.msi`" ALLUSERS=TRUE /QN"
        "REM RD /Q /S `"%ProgramFiles(x86)%\Google\Chrome\Application\$($Installer.Version)\Installer`""
        "REM RD /Q /S `"%ProgramFiles(x86)%\Google\Update`""
        "REM ROBOCOPY `"%ProgramFiles(x86)%\Google\Chrome\Application\$($Installer.Version)`" `"%ProgramFiles(x86)%\Google\Chrome\Application`" /mov /e"
        "REG ADD HKLM\SOFTWARE\Policies\Google\Update /v AutoUpdateCheckPeriodMinutes /d 0 /t REG_DWORD /f"
        "REG ADD `"HKLM\System\CurrentControlSet\Control\Session Manager`" /v PendingFileRenameOperations /d `"`" /t REG_MULTI_SZ /f"
        "sc config gupdate start= disabled"
        "sc stop gupdate"
        "sc config gupdatem start= disabled"
        "sc stop gupdatem"
    )
    $Content | Out-File C:\Temp\Install.cmd -Encoding ascii
    Get-Item C:\Temp\Install.cmd
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
Write-Progress -Activity "Package $SoftwareName" -CurrentOperation "Downloading latest version" -PercentComplete 0
#Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -name ProxyEnable -value 1
#Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -name ProxyServer -value proxyvip:8080
$Installer = Get-LatestChromeEnterprise -DownloadUrl $DownloadUrl -ReleaseNotesUrl $ReleaseNotesUrl -Proxy $Proxy
$PackageName = "Google_Chrome_Ent_$($Installer.Version)"
$BatchFile = New-BatchFile -Installer $Installer
$Params = @{
    Name = $PackageName
    Installer = $BatchFile.FullName
    Path = 'C:\Temp'
}
If (Test-Path "$AppVRepo\Template.appvt")
{
    $Params.Add('TemplateFilePath',"$AppVRepo\Template.appvt")
}
Write-Progress -Activity "Package $SoftwareName" -CurrentOperation "Packaging application" -PercentComplete 20
New-AppvSequencerPackage @Params

If (Test-Path "C:\Temp\$PackageName")
{
    Write-Progress -Activity "Package $SoftwareName" -CurrentOperation "Disabling shortcuts" -PercentComplete 40
    Disable-AppVShortcuts -PackagePath "C:\Temp\$PackageName"

    Write-Progress -Activity "Package $SoftwareName" -CurrentOperation "Copying software files" -PercentComplete 60
    Move2Repo -Path $AppVRepo -Installer $Installer -Package $PackageName

    Write-Progress -Activity "Package $SoftwareName" -CurrentOperation "Copying package files" -PercentComplete 80
    If (Test-Path $AppVShare\$PackageName)
    {
        Remove-Item $AppVShare\$PackageName -Recurse
    }
    Move-Item -Path C:\Temp\$PackageName -Destination $AppVShare -Force
}
else
{
    Write-Error 'Packaging failed' -Category InvalidResult
}
Write-Progress -Activity "Package $SoftwareName" -Completed

Read-Host -Prompt 'Press enter to continue'

#endregion Main
