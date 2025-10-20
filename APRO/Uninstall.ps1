[CmdletBinding()]
Param(
    [Parameter(mandatory)]
    [ValidateSet('PROD','ACC','TEST')]
    [string]
    $Environment,

    [switch]
    $ViewerOnly
)

#region constants

$ProgramFolder = "$env:ProgramW6432\APRO"
$Logfile = "C:\ProgramData\APRO\APRO_UnInstall_$Environment-$((Get-Date).ToShortDateString()).log"

#endregion constants

#region functions

#register iProPlus.dll for OCR
function Register-OCRDll
{
    Param(
        #Path to dll
        [string]
        $Path
    )


    & regsvr32 /s $Path
    while (Get-Process regsvr*)
    {
        sleep -Milliseconds 100
    }
    If (Get-ChildItem HKLM:\SOFTWARE\Classes\TypeLib -Recurse | where {$_.GetValue('') -eq $Path})
    {
        Write-Log 'OCR dll registration successful'
    }
    else
    {
        Write-Log 'OCR dll registration unsuccessful' -Type ERROR
    }
}

#endregion Functions

#region main

If ($ViewerOnly)
{
    $Environment = 'PROD'
    $LogFile = "C:\ProgramData\APRO\APRO_Viewer_UnInstall-$((Get-Date).ToShortDateString()).log"
}
$LogRoot = Split-Path $LogFile
If (Test-Path $LogRoot)
{
    Write-Information "$LogRoot exists"
}
else
{
    Write-Information "Creating $LogRoot folder for logfile"
    $null = New-Item $LogRoot -ItemType Directory -Force
}
Start-Transcript $Logfile -Force
If ($User = Get-Process explorer -IncludeUserName | select -ExpandProperty Username -Unique)
{
    Write-Information "Logged in user is $User"
}
else
{
    Write-Error 'Unable to find logged in user'
    Stop-Transcript
    exit 1
}
Get-Process APRO_* | Stop-Process -Force
If ($Folder = Get-Item $ProgramFolder\$Environment -ErrorAction SilentlyContinue)
{
    If ($ViewerOnly)
    {
        If ($Other = Get-ChildItem -Path $Folder -Filter *.exe | where BaseName -NotLike *viewfacturen)
        {
            Write-Error "Other PROD executables found ($($Other.BaseName -join '/')). Unable to remove ViewFacturen."
            Stop-Transcript
            exit 1
        }
    }
    If ($OCRDll = Get-ChildItem -Path $Folder.FullName -Filter IproPlus.dll -Recurse)
    {
        If ($iProPlus = Get-ChildItem HKLM:\SOFTWARE\Classes\TypeLib -Recurse | where {$_.GetValue('') -eq $OCRDll.FullName})
        {
            Write-Information 'Unregistering iProPlus.dll'
            & regsvr32 /u /s $OCRDll.FullName
            $Unregistered = $true
        }
    }
    Write-Information "Removing APRO $Environment files"
    $Folder | Remove-Item -Recurse -Force
}
If ($Shortcuts = Get-Item "C:\Users\$($User.Split('\')[1])\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\APRO\APRO*$Environment.lnk")
{
    Write-Information "Removing start menu shortcuts"
    $Shortcuts | Remove-Item -Force
}
If ($TBShortcuts = Get-Item "C:\Users\$($User.Split('\')[1])\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\APRO*$Environment.lnk")
{
    Write-Information "Removing taskbar shortcuts"
    $TBShortcuts | Remove-Item -Force
}
switch ($Environment) 
{
    PROD {$Viewer = 'aproview'}
    ACC  {$Viewer = 'aproviewa'}
    TEST {$Viewer = 'aproviewo'}
}
$HKCU = Get-ItemProperty 'Registry::HKEY_USERS\S-*\Volatile Environment' -ErrorAction SilentlyContinue | where USERNAME -EQ $User.Split('\')[1]
if (!$HKCU)
{
    Write-Error "Unable to find CurrentUser key for $($User.Split('\')[1]):"
    Get-ItemProperty 'Registry::HKEY_USERS\S-*\Volatile Environment' -ErrorAction SilentlyContinue
}
else
{
    Write-Information "Found CurrentUser key for $($User.Split('\')[1]): $($HKCU.PSParentPath.Split(':')[2])"
}
if (Get-Item "$($HKCU.PSParentPath)\SOFTWARE\Classes\$Viewer" -ErrorAction SilentlyContinue)
{
    Write-Information "Removing protocol $Viewer"
    Get-Item "$($HKCU.PSParentPath)\SOFTWARE\Classes\$Viewer" | Remove-Item -Recurse -Force
}
else
{
    Write-Information "Protocol $Viewer not present"
}
if ($APRO = Get-ChildItem $ProgramFolder -Directory)
{
    Write-Information "Other APRO environments are still present: $($APRO.Name -join ',')"
    $OCRDll = Get-ChildItem -Path $ProgramFolder -Filter IproPlus.dll -Recurse
    If ($Unregistered -and $OCRDll)
    {
        If (@($OCRDll).Count -gt 1)
        {
            If ($OCRDll | where FullName -like *\PROD\*)
            {
                Write-Information 'Installing PROD version of OCR'
                $OCRDll = $OCRDll | where FullName -like *\PROD\* | select -First 1
            }
            else
            {
                $OCRDll = $OCRDll | select -First 1
                Write-Information "Installing $($OCRDll.FullName.Split('\')[3]) version of OCR"
            }
        }
        Register-OCRDll -Path $OCRDll.FullName
    }
    Stop-Transcript
    Copy-Item $LogFile C:\ProgramData\Microsoft\IntuneManagementExtension\Logs -Force
}
else
{
    Write-Information "All APRO software has been removed"
    If ($Tasks = Get-ScheduledTask APRO*)
    {
        Write-Information "Removing Update tasks $($Tasks.TaskName -join ', ')"
        $Tasks | Stop-ScheduledTask
        $Tasks | Unregister-ScheduledTask -Confirm:$false
    }
    If ($Root = Get-Item $ProgramFolder -ErrorAction Ignore)
    {
        Write-Information "Removing root folder"
        $Root | Remove-Item -Recurse -Force
    }
    if ((Get-MpPreference).ExclusionPath | where {$_ -Match 'APRO'})
    {
        Write-Information 'Removing Defender exclusions'
        Remove-MpPreference -ExclusionPath $ProgramFolder\APRO_Launcher.exe
        Remove-MpPreference -ExclusionPath $ProgramFolder\APRO_Sync.exe
        Remove-MpPreference -ExclusionPath $ProgramFolder\APRO_FSHelper.exe
    }
    If ($StartMenu = Get-Item "C:\Users\$($User.Split('\')[1])\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\APRO")
    {
        Write-Information "Removing startmenu folder"
        $StartMenu | Remove-Item -Recurse -Force
    }
    If (Get-WinEvent -ListLog APRO -ErrorAction Ignore)
    {
        Write-Information "Removing eventlog"
        Remove-EventLog -LogName APRO -Confirm:$false
    }
    Stop-Transcript
    Copy-Item $LogFile C:\ProgramData\Microsoft\IntuneManagementExtension\Logs -Force
    Remove-Item C:\ProgramData\APRO -Recurse
}


#endregion main
