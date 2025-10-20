[CmdletBinding(DefaultParameterSetName='Executable')]
Param(
    # Path to the executable to launch
    [Parameter(mandatory,
               ParameterSetName='Executable')]
    [string]
    $Executable,

    # Arguments for the executable
    [Parameter(ParameterSetName='Executable')]
    [string]
    $Arguments,

    # Environment that's installing
    [Parameter(ParameterSetName='Install')]
    [ValidateSet('PROD','ACC','TEST')]
    [string]
    $Environment,

    # Only install factuurviewer
    [Parameter(ParameterSetName='Install')]
    [switch]
    $ViewerInstall,

    # Send todays logs by email
    [Parameter(ParameterSetName='Logs')]
    [switch]
    $SendLogs,

    # Transcribe output
    [switch]
    $Transcribe
)

#region Constants

$UncPaths = @{
    PROD = [System.Environment]::GetEnvironmentVariable('APROPRD','USER') #PROD share
    ACC =  [System.Environment]::GetEnvironmentVariable('APROACC','USER') #ACC share
    TEST = [System.Environment]::GetEnvironmentVariable('APROTST','USER') #TEST share
}
$ProgramFolder = "$env:ProgramW6432\APRO"
$Removed = @()
$LogFile = "C:\ProgramData\APRO\APRO_Launcher-$((Get-Date).ToShortDateString()).log"
$Transcription = "C:\ProgramData\APRO\APRO_Launcher_Transcription.log"
$EmailAddress = "FEZ-Applicatiebeheer@tweedekamer.nl"
$OCRMode = @{
    PROD = ''
    ACC = ''
    TEST = ''
}
$RightsAppUrl = 'https://<Azure Function GetAPRORights url>'

#endregion Constants

#region functions

#Check if the logfile is in use
function FileInUse
{
    Param(
        [string]
        $File
    )

    try { 
        [IO.File]::OpenWrite($file).close()
        return $false 
    }
    catch {
        $Error.RemoveAt(0)
        $true
    }
}

#Write information to logfile and/or Eventlog
function Write-Log
{
    Param(
        [string]
        $Message,

        [ValidateSet('INFO','ERROR','WARNING')]
        [string]
        $Type = 'INFO',

        [string]
        $Path = $LogFile,

        [int]
        $EventID
    )
    $End = (Get-Date).AddSeconds(5)
    while (FileInUse -File $Path)
    {
        sleep -Milliseconds 100
        If ((Get-Date) -ge $End)
        {
            return
        }
    }
    try
    {
        "$((Get-Date).ToString()) - $Type - $($Message.Trim())" | Out-File -FilePath $Path -Append -Force -ErrorAction Stop
    }
    catch{}
    
    if ($PSBoundParameters.EventID)
    {
        switch ($Type)
        {
            INFO    {$EventType = 'Information'}
            ERROR   {$EventType = 'Error'}
            WARNING {$EventType = 'Warning'}
        }
        Write-EventLog -LogName APRO -Source 'APRO Launcher' -EntryType $EventType -EventId $EventID -Message $Message
    }
}

function New-ToastNotification
{
    Param(
        #Message text
        [string]
        $Message,

        #path to logo
        [string]
        $Logo,

        #AppID of application
        [string]
        $AppID,

        #Progressbar object
        [Microsoft.Toolkit.Uwp.Notifications.AdaptiveProgressBar]
        $ProgressBar,

        #Identifier for notification
        [string]
        $UniqueIdentifier,

        #Progress data
        [hashtable]
        $Data
           
    )

    $Text = New-BTText -Text $Message
    $AppLogoImage = New-BTImage -Source $Logo -AppLogoOverride
    $BindingSplat = @{
        Children        = $Text,$ProgressBar
        AppLogoOverride = $AppLogoImage
    }
    $Binding = New-BTBinding @BindingSplat
    $Visual = New-BTVisual -BindingGeneric $Binding

    $ContentSplat = @{
        Audio  = New-BTAudio -Silent
        Visual = $Visual
        Actions = New-BTAction -SnoozeAndDismiss
        Scenario = 'reminder'
    }
    $Content = New-BTContent @ContentSplat
    $ToastSplat = @{
        Content = $Content
        AppId   = $AppId
        UniqueIdentifier = $UniqueIdentifier
        DataBinding = $Data
        WarningAction = 'SilentlyContinue'
    }
    Submit-BTNotification @ToastSplat
}

#test if unc path is reachable
function Test-UncPath
{
    Param(
        [string]
        $Path,

        [int]
        $Timeout = 3
    )
    #using a background job 
    Write-Log "Testing if $Path is reachable"
    $Test = Start-Job -Name TestPath -ScriptBlock {Test-Path $args} -ArgumentList $Path | Wait-Job -Timeout $Timeout | Receive-Job
    If ($Test)
    {
        Write-Log "$Path is reachable"
        'Bereikbaar'
    }
    else
    {
        Write-Log "$Path is not reachable" -Type ERROR
        'Onbereikbaar'
    }
    Remove-Job -Name TestPath -Force
}

function Show-ProgressToast 
{
    Param(
        #Name of the software
        [string]
        $Software = 'APRO',

        #Path to the logo
        [string]
        $Logo,

        #Short task description
        [string]
        $Description = 'Bestanden downloaden',

        #AppID 
        [string]
        $AppID = 'Windows.SystemToast.StartupApp',

        #Installation not update
        [switch]
        $IsInstallation
    )
    
    Write-Log 'Showing initial toast progress'
    $Data = @{
        ProgressStatus = 'Bestanden controleren...'
        ProgressValue = 0
        ProgressDisplay = ''
    }
    $ProgressBar = New-BTProgressBar -Status ProgressStatus -Value ProgressValue -ValueDisplay ProgressDisplay
    #Using a custom function so we can use the reminder scenario for a longer presence
    $Params = @{
		Message = "$Software wordt bijgewerkt..."
		ProgressBar = $ProgressBar
		AppId = $AppID
		UniqueIdentifier = 'APRO'
		Logo = $Logo
		Data = $Data
	}
    if ($PSBoundParameters.IsInstallation)
    {
        $Params.Message = "$Software wordt geïnstalleerd..."
    }
	New-ToastNotification @Params -WarningAction SilentlyContine
    Do
    {
        $Progress = [System.Environment]::GetEnvironmentVariable('APROProgress','USER')
        If (!$Progress)
        {
            Write-Log 'No sync data yet. Retrying in a second...'
            $Task = Get-ScheduledTask -TaskName APROSync
            sleep -Seconds 1
        }
    }
    Until ($Progress -or $Task.State -ne 'Running')
    If (!$Progress)
    {
        Write-Log 'No progress found while sync was running' -Type ERROR
        Remove-BTNotification -AppId $AppID -UniqueIdentifier APRO -WarningAction SilentlyContinue
        return
    }
    Write-Log "Sync data found ($Progress). Updating progress notification."
    $Data.ProgressStatus = "$Description..."
    sleep -Seconds 1
    Do
    {
        $Progress = [System.Environment]::GetEnvironmentVariable('APROProgress','USER')
        [int]$ErrorCount = [System.Environment]::GetEnvironmentVariable('APROErrorCount','USER')
        If ($Progress -ne $Data.ProgressDisplay -and $Progress -ne $null)
        {
            $Data.ProgressValue = [Data.DataTable]::New().Compute($Progress, $null)
            If ($Data.ProgressValue -gt 1)
            {
                $Data.ProgressValue = 1
            }
            $Data.ProgressDisplay = $Progress
            $Params = @{
			    UniqueIdentifier = 'APRO'
			    DataBinding = $Data
			    AppId = $AppID
                WarningAction = 'SilentlyContinue'
                ErrorAction = 'SilentlyContinue'
		    }
		    $null = Update-BTNotification @Params
        }
        If ($ErrorCount -ge 5 -and !$WarningShown)
        {
            $VPNState = Get-VpnConnection -Name TKWSVPN -ErrorAction Ignore | Select -ExpandProperty ConnectionStatus
            $ShareState = Test-UncPath $UncPaths['PROD']
            $SMBTest = Test-NetConnection -ComputerName $UncPaths['PROD'].Split('\')[2] -CommonTCPPort SMB -InformationLevel Quiet
            switch ($SMBTest)
            {
                $True {$SMBState = 'Bereikbaar'}
                $false {$SMBState = 'Onbereikbaar'}
            }
            if ($Executable)
            {
                $what = 'het starten van de applicatie'
            }
            else
            {
                $what = 'de installatie'
            }
            Write-Warning "Er zijn problemen ontdekt met synchroniseren, waardoor $what langer kan duren.`n`n`tVPN Status: $VPNState`n`tShare Status: $ShareState`n`tSMB Status: $SMBState"
            $WarningShown = $true
            Write-Log "Sync issues detected. VPN Status: $VPNState, Share Status: $ShareState, SMB Status: $SMBState"
        }
        sleep -Seconds 1
        $APROSync = Get-ScheduledTask -TaskName APROSync
    }
    Until($APROSync.State -ne 'Running')
    If ($ErrorCount)
    {
        Write-Log "Sync ended with $ErrorCount errors" -Type WARNING
    }
    Remove-BTNotification -AppId $AppID -UniqueIdentifier APRO
}

#Get content of the OCR zipfile
function Get-ZipContent
{
    Param($Zipfile)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $Content = [System.IO.Compression.ZipFile]::OpenRead($Zipfile)
    foreach ($Entry in $Content.Entries.where{$_.name})
    {
        [pscustomobject]@{
            Name = $Entry.Name
            FullName = $Entry.FullName -replace '/','\'
            Length = $Entry.Length
            LastWriteTime = $Entry.LastWriteTime
        }
    }
    $Content.Dispose()
}

#Compare OCR zipfile to uncompressed
function Compare-OCRContent
{
    Param(
        #Path to the zipfile
        [string]
        $Zipfile
    )
    $File = Get-Item -Path $Zipfile
    $ZipContent = Get-ZipContent -Zipfile $File.FullName
    $Files = Get-ChildItem "$($File.Directory)\distributionv16_1_" -Recurse -File

    foreach ($ZipItem in $ZipContent)
    {
        if ($Item = $Files | Where FullName -like "*\$($ZipItem.FullName)")
        {
            $SameDate = $Item.LastWriteTime.Ticks.ToString().Substring(0,8) -eq $ZipItem.LastWriteTime.Ticks.ToString().Substring(0,8) -or 
                $Item.LastWriteTime.Ticks.ToString().Substring(0,8) -eq $ZipItem.LastWriteTime.UtcTicks.ToString().Substring(0,8)
            $SameSize = $Item.Length -eq $ZipItem.Length
            If (!$SameSize -or !$SameDate)
            {
                [pscustomobject]@{
                    File = $Item
                    ZipFile = $ZipItem
                }
            }
        }
        else
        {
            If ($ZipItem.Name -ne 'Thumbs.db')
            {
                [pscustomobject]@{
                    File = 'Not present'
                    ZipFile = $ZipItem
                }
            }
        }
    }
}

#Sync between UNCpath and local folder
function Sync-Environment
{
    Param(
        #Source path
        [string]
        $Source,

        #Destination path
        [string]
        $Destination,

        #Environment to process
        [string]
        $Environment,

        #Allowed software for user
        [hashtable]
        $Software,

        #MultiThread count for robocopy command
        [int]
        $MT = 32,

        #Only list changes
        [switch]
        $ListOnly,

        #Only sync viewer
        [switch]
        $Viewer
    )

    If ($Software -and $Software[$Environment] -eq 'ERROR')
    {
        Write-Log "Skipping sync for $Environment because of an error" -Type WARNING
        return
    }
    If ($Viewer)
    {
        $Command = @(
            'robocopy'
            "'$Source\APRO Imaging'",
            "'$Destination\APRO Imaging'",
            '*viewfacturen*',
            '*.jdbg',
            'APRO*.dll',
            'Edge*.dll',
            'QPL1711PDFium32.dll',
            'OracleDatabase.txt'
        )
        $ViewerOnly = $true
    }
    else
    {
        $Command = @(
            'robocopy'
            "'$Source'",
            "'$Destination'",
            '/MIR',
            '/XF Rechten.xml'
        )
        $ViewerOnly = $false
    }
    If ($PSBoundParameters.ListOnly)
    {
        $Command += '/L'
        If ($ViewerOnly)
        {
            Write-Log 'Only including Viewer files'
        }
    }
    else
    {
        $Command += "/R:5 /W:5 /MT:$MT /NP"
    }
    If (!$ViewerOnly)
    {
        If ($Software[$Environment] -notcontains 'BANKING')
        {
            If ($PSBoundParameters.ListOnly)
            {
                Write-Log "Excluding Banking Gateway for $Environment"
            }
            $Command += '/XD'
            $Command += "'APRO Banking Gateway'"
            If (Test-Path "$Destination\APRO Banking Gateway")
            {
                Write-Log "User no langer has access to Banking Gateway" -Type WARNING
                Write-Log "Removing Banking Gatway folder for $Environment"
                Remove-Item "$Destination\APRO Banking Gateway" -Recurse -Force
                If ($Shortcut = Get-Item "$ENV:AppData\Microsoft\Windows\Start Menu\Programs\*\APRO Banking Gateway $Environment.lnk")
                {
                    Write-Log "Removing Banking Gateway shortcut from the start menu"
                    $Shortcut | Remove-Item
                }
            }
        }
        If ($Software[$Environment] -notcontains 'Enter')
        {
            If ($PSBoundParameters.ListOnly)
            {
                Write-Log "Excluding Enter Invoices for $Environment"
            }
            $Command += '/XF APROEnterInvoices.exe'
            $Command += '/XF OCR.zip'
            $Command += '/XD distributionv16_1_'
            If ($Enter = Get-ChildItem $Destination -Filter APROEnterInvoices.exe -Recurse)
            {
                Write-Log "User no langer has access to Enter Invoices" -Type WARNING
                Write-Log "Removing $Enter for $Environment"
                $Enter | Remove-Item -Force
                If ($Shortcut = Get-Item "$ENV:AppData\Microsoft\Windows\Start Menu\Programs\*\APRO Enter Invoices $Environment.lnk")
                {
                    Write-Log "Removing Enter Invoices shortcut from the start menu"
                    $Shortcut | Remove-Item
                }
            }
            If (Test-Path "$Destination\APRO Imaging\distributionv16_1_")
            {
                Write-Log "Removing OCR folder for $Environment"
                Remove-Item "$Destination\APRO Imaging\distributionv16_1_" -Recurse -Force
            }
        }
        elseif (Test-Path "$Destination\APRO Imaging\distributionv16_1_")
        {
            Write-Log "OCR files are already installed. Using uncompressed files to sync."
            $Command += '/XF OCR.zip'
        }
        elseif ($OCRMode -and $OCRMode[$Environment] -eq 'Folder')
        {
            $Command += '/XF OCR.zip'
        }
        elseif ($OCRMode -and $OCRMode[$Environment] -eq 'ZipFile')
        {
            $Command += '/XD distributionv16_1_'
        }
        else
        {
            If (Test-Path "$Source\APRO Imaging\OCR.zip")
            {
                Write-Log "OCR.zip file found. Checking contents against uncompressed files."
                If ($Compared = Compare-OCRContent -Zipfile "$Source\APRO Imaging\OCR.zip")
                {
                    Write-Log "Differences detected between OCR.zip contents and uncompressed files." -Type WARNING
                    $Compared | Out-File $LogFile -Append -ErrorAction Ignore
                    Write-Log 'Using uncompressed OCR files for installation.' -Type WARNING
                    $Command += '/XF OCR.zip'
                    $script:OCRMode[$Environment] = 'Folder'
                }
                else
                {
                    Write-Log "OCR.zip contents is current. Using zipfile for installation."
                    $Command += '/XD distributionv16_1_'
                    $script:OCRMode[$Environment] = 'ZipFile'
                }
            }
            else
            {
                Write-Log 'No OCR.zip file found. Using uncompressed OCR files.'
            }
        }
        If ($Software[$Environment] -notcontains 'IMA')
        {
            If ($PSBoundParameters.ListOnly)
            {
                Write-Log "Excluding Imaging for $Environment"
            }
            $Command += '/XF'
            $Command += 'APROImaging.exe'
            If ($IMA = Get-ChildItem $Destination -Filter APROImaging.exe -Recurse)
            {
                Write-Log "User no langer has access to Imaging" -Type WARNING
                Write-Log "Removing $IMA for $Environment"
                $IMA | Remove-Item -Force
                If ($Shortcut = Get-Item "$ENV:AppData\Microsoft\Windows\Start Menu\Programs\*\APRO Imaging $Environment.lnk")
                {
                    Write-Log "Removing Imaging shortcut from the start menu"
                    $Shortcut | Remove-Item
                }
            }
        }
    }
    If (Test-Path $Source)
    {
        If ($PSBoundParameters.ListOnly)
        {
            Write-Log "Listing changes for $Environment"
            Invoke-Expression -Command ($Command -join ' ') | where {$_ -Match 'New File|Newer|EXTRA File'}
        }
        else
        {
            Write-Log "Syncing environment $Environment"
            Invoke-Expression -Command ($Command -join ' ') | Out-File $LogFile -Append -ErrorAction Ignore
            If (Test-Path "$Destination\APRO Imaging\OCR.zip")
            {
                Write-Log 'Unzipping OCR files.'
                Expand-Archive -Path "$Destination\APRO Imaging\OCR.zip" -DestinationPath "$Destination\APRO Imaging" -Force
                If ($?)
                {
                    Write-Log 'Removing zipfile.'
                    Remove-Item "$Destination\APRO Imaging\OCR.zip"
                }
            }
        }
    }
    else
    {
        Write-Log "Unable to reach path $Source" -Type ERROR -EventID 110
    }
}

#Get software per environment the current user has rights to
function Get-AllowedSoftware
{
    Param(
        #URL to the function app
        [string]
        $Url = $RightsAppUrl
    )

    $SID = ([System.Security.Principal.NTAccount]$env:USERNAME).Translate([System.Security.Principal.SecurityIdentifier]).Value
    $UserName = Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Microsoft\IdentityStore\Cache\$SID\IdentityCache\$SID" -Name UserName
    $Body = @{userName=$UserName} | ConvertTo-Json
    Write-Log "Retreiving APRO rights for user $UserName"
    If ($Rights = Invoke-RestMethod -Method Post -Uri $url -Body $Body -ContentType application/json)
    {
        $Software = @{
            PROD = $Rights.PROD
            ACC = $Rights.ACC
            TEST = $Rights.TEST
        }
        Write-Log 'Approved software:'
        $End = (Get-Date).AddSeconds(5)
        while (FileInUse -File $Path)
        {
            sleep -Milliseconds 100
            If ((Get-Date) -ge $End)
            {
                break
            }
        }
        $Software | Out-File $LogFile -Append -ErrorAction Ignore
        return $Software
    }
}

#Get files that need updates
function Get-Updates
{
    Param(
        [ValidateSet('PROD','ACC','TEST')]
        [string]
        $Environment,

        [switch]
        $Viewer
    )
    
    $Env = Get-Item $ProgramFolder\$Environment
    $Params = @{
		Source = $UncPaths[$Env.Name]
		Destination = $Env.FullName
		Environment = $Env.Name
		ListOnly = $true
	}
    If ($Viewer)
    {
        $Params.Add('Viewer',$true)
    }
    else
    {
        $Params.Add('Software',$Software)
    }
    Sync-Environment @Params
}

#Get updates for launcher and sync tools
function Get-ToolsUpdates
{
    #Write-Log 'Checking for updated tools'
    $Command = @(
        'robocopy'
        "'$(Split-Path $UncPaths.PROD)'",
        "'$ProgramFolder'",
        'APRO_Launcher.exe',
        'APRO_Sync.exe',
        'APRO_FSHelper.exe',
        'RwEasyMAPI64.exe',
        '/L',
        '/XO'
    )
    Invoke-Expression -Command ($Command -join ' ') | 
        where {$_ -Match 'New File|Newer|EXTRA File'} | foreach {
            $_ -Split '\s' | select -Last 1
        }
}

#Update a tool
function Install-ToolsUpdate
{
    Param(
        [ValidateSet('APRO_Launcher.exe','APRO_Sync.exe','APRO_FSHelper.exe','RwEasyMAPI64.exe')]
        [string]
        $Tool,

        [string]
        $Source,

        [string]
        $Destination
    )

    $Command = @(
        'robocopy'
        "'$Source'",
        "'$Destination'",
        $Tool
    )
    Invoke-Expression -Command ($Command -join ' ') | Out-File $LogFile -Append -ErrorAction Ignore
}

#Start executable and wait until the window is visible
function Start-Executable 
{
    [CmdletBinding()]
    param (
        #Path to the executable
        [Parameter(mandatory)]
        [string]
        $Executable,

        [string[]]
        $ArgumentList,

        [int]
        $TimeoutInSeconds = 30
    )

    Add-Type @"
    using System;
    using System.Runtime.InteropServices;
    public class User32 {
        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool IsWindowVisible(IntPtr hWnd);
    }
"@
    $Params = @{ErrorAction = 'Ignore'}
    $EndTime = (Get-Date).AddSeconds($TimeoutInSeconds)
    If ($Executable -like '*\StartViewFacturen.exe')
    {
        $ExcludeIDs = Get-Process -Name ViewFacturen -ErrorAction Ignore | select -ExpandProperty Id
        $Params.Add('Name','ViewFacturen')
        Start-Process -FilePath $Executable -ArgumentList $ArgumentList
    }
    else
    {
        $Process = Start-Process -FilePath $Executable -PassThru
        $Params.Add('Id',$Process.Id)
    }
    Write-Log "Waiting until the process has a visible window"
    
    while ((Get-Date) -lt $EndTime)
    {
        If ($Process = Get-Process @Params | where Id -NotIn $ExcludeIDs)
        {
            if ($Process.MainWindowHandle -ne 0 -and [User32]::IsWindowVisible($Process.MainWindowHandle))
            {
                Write-Log "Window is visible"
                $wshell = New-Object -ComObject wscript.shell
                $End = (Get-Date).AddSeconds(10)
                while ($wshell.AppActivate($Process.MainWindowTitle) -eq $false -and (Get-Date) -lt $End)
                {
                    sleep -Milliseconds 500
                }
                return
            }
        }
        Start-Sleep -Milliseconds 500
    }
    Write-Log "Timeout: $($Process.Name) window did not become visible within $TimeoutInSeconds seconds." -Type ERROR
}

#Gather logs and send by Outlook email
function Send-TodaysLogs
{
    Param(
        [string]
        $EmailAddress
    )

    $outlook = new-object -comobject outlook.application

    $email = $outlook.CreateItem(0)
    $email.To = $EmailAddress
    $email.Subject = "APRO logbestanden"
    $email.Body = "Hierbij mijn APRO logbestanden"
    $ZipFile = "$env:TEMP\APROLogs_$((Get-Date).ToShortDateString()).zip"
    Get-ChildItem C:\ProgramData\APRO\*.log | Compress-Archive -DestinationPath $ZipFile -Force
    Get-ChildItem C:\ProgramData\APRO\*Install*.log | Compress-Archive -DestinationPath $ZipFile -Update
    $null = $email.Attachments.add($ZipFile)
    $email.Display()
    $wshell = New-Object -ComObject wscript.shell
    $OL = Get-Process outlook | where MainWindowTitle -Like 'APRO logbestanden*'
    $Window = $wshell.AppActivate($OL.MainWindowTitle)
    while ($email.Sent -eq $false)
    {
        sleep -Milliseconds 500
    }
    Remove-Item $ZipFile
}

function Show-SMBWarning
{
    Param(
        [string]
        $AppID
    )
    If ($VPN = Get-VpnConnection TKWSVPN -ErrorAction Ignore)
    {
        switch ($VPN.ConnectionStatus)
        {
            Connected {$VPNStatus = 'Online'}
            Disconnected {$VPNStatus = 'Offline'}
            Default {$VPNStatus = $VPN.ConnectionStatus}
        }
    }
    else
    {
        $VPNStatus = 'Afwezig'
    }
    $SMB = Test-UncPath $UncPaths['PROD']
    $Net = [System.Net.Sockets.TcpClient]::new($UncPaths['PROD'].Split('\')[2],445).Connected
    switch ($Net)
    {
        $true  {$Port = 'Bereikbaar'}
        $false {$Port = 'Onbereikbaar'}
    }
    $Message = "Er zijn connectie problemen gedetecteerd. Mogelijk werkt de applicatie niet goed."
    If (!$AppID -or $AppID -eq '')
    {
        $AppID = Get-StartApps Taakplanner | select -ExpandProperty AppID
    }

    Write-Log "VPN status: $VPNStatus, UNC pad: $SMB & SMB poort: $Port"
}

#endregion functions

#region Main

$Error.Clear()
$Params = $PSBoundParameters.Keys.ForEach{"-$_ '$($PSBoundParameters[$_])'"} -join ' '
If ($PSBoundParameters.ViewerInstall)
{
    $LogFile = "C:\ProgramData\APRO\APRO_Launcher-ViewerInstall-$((Get-Date).ToShortDateString()).log"
}
If (FileInUse -File $LogFile)
{
    $LogFile = "C:\ProgramData\APRO\APRO_Launcher-$((Get-Date).ToShortDateString())-$(Get-Random -Maximum 20).log"
    Write-Log "Logfile C:\ProgramData\APRO\APRO_Launcher-$((Get-Date).ToShortDateString()).log was in use"
}
Write-Log "Launcher started with arguments $Params" -EventID 100
$TestUNC = Test-UncPath $UncPaths['PROD']
If ($TestUNC -eq 'Bereikbaar')
{
    Write-Log 'Checking for updated tools'
    $ToolsUpdates = Get-ToolsUpdates
    If ($ToolsUpdates)
    {
        foreach ($Tool in $ToolsUpdates)
        {
            Write-Log "Downloading updated version of $Tool"
            Install-ToolsUpdate -Tool $Tool -Source (Split-Path $UncPaths.PROD) -Destination C:\ProgramData\APRO
        }
    }
}
$TSlog = Get-WinEvent -ListLog "Microsoft-Windows-TaskScheduler/Operational"
If ($TSlog.IsEnabled)
{
    Write-Log 'TaskScheduler log is enabled'
}
else
{
    Write-Log 'TaskScheduler log is disabled' -Type ERROR
    Write-Log 'Enabling TaskScheduler log'
    try
    {
        $TSlog.IsEnabled = $true
        $TSlog.SaveChanges()
        Write-Log 'Log enabled'
    }
    catch
    {
        Write-Log 'Unable to enable the TaskScheduler Operational log' -Type ERROR -EventID 115
        exit 1
    }
}
if ($PSBoundParameters.SendLogs)
{
    Write-Log 'Sending todays logfiles'
    Send-TodaysLogs -EmailAddress $EmailAddress
    return
}
If ($PSBoundParameters.ViewerInstall)
{
    $Environment = 'PROD'
}
elseif ($PSBoundParameters.Executable)
{
    $Environment = $Executable.Split('\')[3]
    $Text = "De applicatie wordt gestart."
    switch -w ($Executable)
    {
        *\APROImaging.exe {$App = "APRO Imaging $Environment"}
        *\APROEnterInvoices.exe {$App = "APRO Enter Invoices $Environment"}
        *\APROBankingGateway.exe {$App = "APRO Banking Gateway $Environment"}
        *\StartViewFacturen.exe {$App = '*Edge';$Text = "De factuurviewer wordt gestart"}
    }
    Write-Log "Starting toast using application $($App.TrimStart('*'))" -EventID 102
    $AppID = Get-StartApps $App | select -ExpandProperty AppID
    If (!$AppID)
    {
        Write-Log 'No AppID found! Using PowerShell instead.' -Type ERROR
        $AppID = Get-StartApps PowerShell | select -First 1 -ExpandProperty AppID
    }
    Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
    New-BurntToastNotification -Text $Text -AppLogo $ProgramFolder\APRO_Logo.png -AppId $AppID -UniqueIdentifier APROStart -WarningAction SilentlyContinue
}
If ($Executable -like '*\StartViewFacturen.exe' -or $ViewerInstall)
{
    #$TestUNC = Test-UncPath $UncPaths[$Environment]
    #If ($TestUNC -eq 'Bereikbaar')
    #{
        Write-Log "Checking for viewer updates in $Environment"
        [array]$Files = Get-Updates -Environment $Environment -Viewer

        if ($Files.Count -and (Test-UncPath $UncPaths[$Environment]) -ne 'Bereikbaar')
        {
            Show-SMBWarning -AppID $AppID
            $Files = @()
        }
    #}
    #else
    #{
    #    Show-SMBWarning -AppID $AppID
    #    $Files = @()
    #}
}
else
{
    Write-Log "Checking for updates in $Environment"
    If ($Software = Get-AllowedSoftware)
    {
        [array]$Files = Get-Updates -Environment $Environment
    }
    else
    {
        Show-SMBWarning -AppID $AppID
        $Files = @()
    }
}
if ($Files.Count -and (Get-ScheduledTask -TaskName APROSync).State -ne 'Running')
{
    $SyncActive = $true
    Write-Log "Starting Update task" -EventID 101
    Start-ScheduledTask -TaskName APROSync
    $TimeOut = (Get-Date).AddMinutes(2)
    Do
    {
        sleep -Seconds 1
        $Now = Get-Date
    }
    Until ((Get-ScheduledTask -TaskName APROSync).State -eq 'Running' -or $Now -gt $TimeOut)
}
if ((Get-ScheduledTask -TaskName APROSync).State -eq 'Running')
{
    $SyncActive = $true
    Set-ExecutionPolicy RemoteSigned -Scope Process -Force
    Import-Module BurntToast -ErrorAction Ignore
    If ($Environment)
    {
        Write-Log 'Starting toast for installation' -EventID 102
        $AppID = Get-StartApps Bedrijfsportal | select -ExpandProperty AppID
    }
    If (!$AppID)
    {
        Write-Log 'Using default AppID' -EventID 102
        $AppID = Get-StartApps Taakplanner | select -ExpandProperty AppID
    }
    If ($Environment)
    {
        Show-ProgressToast -Logo 'C:\Program Files\APRO\APRO_Logo.png' -AppID $AppID -IsInstallation
    }
    else
    {
        Show-ProgressToast -Logo 'C:\Program Files\APRO\APRO_Logo.png' -AppID $AppID
    }
}

if ($PSBoundParameters.Executable)
{
    If ($Executable -notin $Removed)
    {
        $SMB = Get-SmbMapping | where LocalPath -eq 'Y:'
        If ($SMB -and $SMB.Status -eq 'Unavailable')
        {
            Write-Log 'Reconnecting disconnected Y drive'
            $null = New-SmbMapping -LocalPath Y: -RemotePath $SMB.RemotePath -ErrorAction Ignore
        }
        elseif (!$SMB)
        {
            Write-Log "No Y drive available" -Type ERROR
        }
        if ($PSBoundParameters.Arguments)
        {
            Write-Log "Starting executable $Executable with arguments $Arguments" -EventID 103
            Start-Executable -Executable $Executable -ArgumentList $Arguments
        }
        else
        {
            Write-Log "Starting executable $Executable" -EventID 103
            Start-Executable -Executable $Executable
        }
        Remove-BTNotification -AppId $AppID -UniqueIdentifier APROStart
    }
    else
    {
        Remove-BTNotification -AppId $AppID -UniqueIdentifier APROStart
        $Env = $Executable.Split('\')[3]
        switch (Split-Path $Executable -Leaf)
        {
            APROImaging.exe {$Name = 'APRO Imaging'}
            APROEnterInvoices.exe {$Name = 'APRO Enter Invoices'}
            APROBankingGateway.exe {$Name = 'APRO Banking Gateway'}
        }
        Write-Log "User started an executable that was removed: $Name $Env" -Type WARNING -EventID 105
        Write-Warning "U heeft geen rechten meer op de APRO software die u wilde starten: $Name $Env. De software is verwijderd van uw systeem. Is dit onterecht neem dan contact op met de applicatiebeheerder."
    }
}

If ($ToolsUpdates -and !$SyncActive)
{
    Write-Log 'Starting sync in background to update the tools'
    Start-ScheduledTask -TaskName APROSync
}

If ($Error)
{
    Write-Log 'End of script. The following errors occured:'
    $Error | select Exception,TargetObject,CategoryInfo,@{name='Line';expression={$_.InvocationInfo.Line}},ScriptStackTrace | Out-File -FilePath $LogFile -Append -ErrorAction Ignore
}
'=' * 100 + "`n`n" | Out-File $LogFile -Append

Copy-Item $LogFile C:\ProgramData\Microsoft\IntuneManagementExtension\Logs -Force -ErrorAction Ignore

#endregion Main
