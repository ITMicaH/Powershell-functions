[CmdletBinding()]
Param(
    [Parameter(mandatory)]
    [ValidateSet('PROD','ACC','TEST')]
    [string]
    $Environment,

    [switch]
    $ViewerOnly
)

#region Constants

$ProgramFolder = "$env:ProgramW6432\APRO"
$LogFile = "C:\ProgramData\APRO\APRO_Install_$Environment-$((Get-Date).ToShortDateString()).log"

#endregion Constants

#region functions

# Start launcher using a temporary scheduled task running at the user level2
function Start-Launcher
{
    Param(
        [string]
        $User,

        [ValidateSet('PROD','ACC','TEST')]
        [string]
        $Environment,

        [switch]
        $Viewer
    )
    If (Get-ScheduledTask -TaskName APROLaunch -TaskPath \ -ErrorAction SilentlyContinue)
    {
        Write-Information 'Removing old APROLaunch task'
        Get-ScheduledTask APROLaunch | Unregister-ScheduledTask -Confirm:$false
    }
    Write-Information 'Creating temporary APROLaunch Task'
    $Trigger = New-ScheduledTaskTrigger -AtLogOn -User $User
    If ($Viewer)
    {
        $Action = New-ScheduledTaskAction -Execute $ProgramFolder\APRO_Launcher.exe -Argument '-ViewerInstall'
    }
    else
    {
        $Action = New-ScheduledTaskAction -Execute $ProgramFolder\APRO_Launcher.exe -Argument "-Environment $Environment"
    }
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries
    $Task = New-ScheduledTask -Description 'Run APRO Launcher at installation' -Action $Action -Trigger $Trigger -Settings $Settings
    $RegTask = Register-ScheduledTask -TaskName APROLaunch -InputObject $Task -User $User
    
    Write-Information 'Setting Read and Execute rights on APROLaunch Task for Authenticated Users'
    $SD = Get-ItemPropertyValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\APROLaunch' -Name SD
    $SDHelper = [wmiclass]"Win32_SecurityDescriptorHelper"
    $SDDL = $SDHelper.BinarySDToSDDL($SD).SDDL
    $SDNew = $SDHelper.SDDLToBinarySD($SDDL + "(A;ID;0x1301bf;;;AU)").BinarySD
    Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\APROLaunch' -Name SD -Value $SDNew -Force
    
    Start-ScheduledTask -TaskName APROLaunch
    Do
    {
        sleep -Seconds 1
        $APROLaunch = Get-ScheduledTask -TaskName APROLaunch
    }
    Until ($APROLaunch.State -ne 'Running')
    while ((Get-ScheduledTask -TaskName APROLaunch).State -eq 'Running')
    {
        sleep -Seconds 1
    }
    $Info = Get-ScheduledTaskInfo -TaskName APROLaunch
    If ($Info.LastTaskResult -eq 0)
    {
        Get-ScheduledTask APROLaunch | Unregister-ScheduledTask -Confirm:$false
    }
    else
    {
        Write-Error 'APRO Launch task failed'
    }
}

#Create event trigger for scheduled task
function New-TaskEventTrigger
{
    Param(
        [ValidateSet('TaskStartEvent','TaskStartFailedEvent','TaskSuccessEvent')]
        [string]
        $EventType = 'TaskSuccessEvent',

        [string]
        $TaskName = '\APROSync'
    )

    $Query = @"
    <QueryList>
        <Query Id="0" Path="Microsoft-Windows-TaskScheduler/Operational">
        <Select Path="Microsoft-Windows-TaskScheduler/Operational">*[EventData [@Name='{0}'][Data[@Name='TaskName']='$TaskName']]</Select>
        </Query>
    </QueryList>
"@
    $CIMTriggerClass = Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace Root/Microsoft/Windows/TaskScheduler:MSFT_TaskEventTrigger
    $Trigger = New-CimInstance -CimClass $CIMTriggerClass -ClientOnly
    $Trigger.Subscription = $Query -f $EventType
    $Trigger.Enabled = $true
    return $Trigger
}

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
        Write-Information 'OCR dll registration successful'
    }
    else
    {
        Write-Error 'OCR dll registration unsuccessful'
    }
}

#endregion functions

#region Main

If ($ViewerOnly)
{
    $Environment = 'PROD'
    $LogFile = "C:\ProgramData\APRO\APRO_ViewerInstall-$((Get-Date).ToShortDateString()).log"
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
Start-Transcript $LogFile -Append
If ($User = Get-Process explorer -IncludeUserName | select -ExpandProperty Username -Unique)
{
    Write-Information "Logged in user is $User"
}
else
{
    Write-Error 'Unable to find logged in user'
    exit 1
}
$Acl = Get-Acl 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs'
If ($UserAccess = $Acl.Access.where{$_.IdentityReference -eq $User})
{
    If ($UserAccess.FileSystemRights -match 'Modify')
    {
        Write-Information "User $User already has access to the Intune logfolder"
    }
    else
    {
        Write-Information "Adding rule to the ACL for $User on the Intune logfolder"
        $Rule = New-Object System.Security.AccessControl.FileSystemAccessRule($User,'Modify','3','0','Allow')
        $Acl.SetAccessRule($Rule)
        $Acl | Set-Acl 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs'
    }
}
else
{
    Write-Information "Adding rule to the ACL for $User on the logfolder"
    $Rule = New-Object System.Security.AccessControl.FileSystemAccessRule($User,'Modify','3','0','Allow')
    $Acl.SetAccessRule($Rule)
    $Acl | Set-Acl 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs'
}

If ($ViewerOnly -and (Test-Path $ProgramFolder\$Environment\ViewFacturen.exe))
{
    Write-Information "APRO PROD viewer is already present so no need to install a seperate viewer"
    Stop-Transcript
    Copy-Item $LogFile C:\ProgramData\Microsoft\IntuneManagementExtension\Logs -Force
    exit 0
}

If (Test-Path $ProgramFolder)
{
    Write-Information "Skipping creation of $ProgramFolder, it already exists"
    $Acl = Get-Acl $ProgramFolder
    If ($Acl.Owner -ne 'NT AUTHORITY\SYSTEM')
    {
        $null = $ACL.SetOwner([System.Security.Principal.NTAccount]::new('NT AUTHORITY\SYSTEM'))
        $Acl | Set-Acl $ProgramFolder
    }
}
else
{
    Write-Information "Creating folder $ProgramFolder"
    $NewFolder = New-Item $ProgramFolder -ItemType Directory
    $Acl = Get-Acl $ProgramFolder
    $null = $ACL.SetOwner([System.Security.Principal.NTAccount]::new('NT AUTHORITY\SYSTEM'))
    $Acl | Set-Acl $ProgramFolder
}
$null = Copy-Item $PSScriptRoot\APRO_Sync.exe $ProgramFolder -Force
$null = Copy-Item $PSScriptRoot\APRO_Launcher.exe $ProgramFolder -Force
$null = Copy-Item $PSScriptRoot\APRO_Logo.png $ProgramFolder -Force
$null = Copy-Item $PSScriptRoot\APRO_FSHelper.exe $ProgramFolder -Force
if (!$ViewerOnly)
{
    $null = Copy-Item $PSScriptRoot\RwEasyMAPI64.exe $ProgramFolder -Force
}
If ((Get-MpPreference).ExclusionPath -notcontains "$ProgramFolder\APRO_Launcher.exe")
{
    Write-Information 'Adding Defender exclusion for Launcher'
    Add-MpPreference -ExclusionPath $ProgramFolder\APRO_Launcher.exe
}
If ((Get-MpPreference).ExclusionPath -notcontains "$ProgramFolder\APRO_Sync.exe")
{
    Write-Information 'Adding Defender exclusion for Sync tool'
    Add-MpPreference -ExclusionPath $ProgramFolder\APRO_Sync.exe
}
If ((Get-MpPreference).ExclusionPath -notcontains "$ProgramFolder\APRO_FSHelper.exe")
{
    Write-Information 'Adding Defender exclusion for FSHelper'
    Add-MpPreference -ExclusionPath $ProgramFolder\APRO_FSHelper.exe
}
If ((Get-MpPreference).ExclusionPath -notcontains "$ProgramFolder\RwEasyMAPI64.exe" -and !$ViewerOnly)
{
    Write-Information 'Adding Defender exclusion for MAPI tool'
    Add-MpPreference -ExclusionPath $ProgramFolder\RwEasyMAPI64.exe
}

if (Test-Path $ProgramFolder\$Environment)
{
    Write-Information "Folder $Environment already exists"
}
else
{
    Write-Information "Creating folder $Environment"
    $null = New-Item $ProgramFolder -Name $Environment -ItemType Directory
    $Acl = Get-Acl $ProgramFolder\$Environment
    $null = $ACL.SetOwner([System.Security.Principal.NTAccount]::new('NT AUTHORITY\SYSTEM'))
    $Acl | Set-Acl $ProgramFolder\$Environment
}
If (Test-Path 'C:\Program Files\WindowsPowerShell\Modules\BurntToast')
{
    Write-Information 'BurntToast module has already been installed'
}
else
{
    Write-Information 'Installing BurntToast module'
    Copy-Item "$PSScriptRoot\BurntToast" 'C:\Program Files\WindowsPowerShell\Modules' -Recurse
}
if ($Task = Get-ScheduledTask -TaskName APROSync -TaskPath \ -ErrorAction SilentlyContinue)
{
    Write-Information 'Scheduled task APROSync is already present'
    If ($ViewerOnly)
    {
        If ($Task.Actions[0].Arguments -ne '-Viewer')
        {
            Write-Information "Adding -Viewer argument to the tasks action."
            $Task.Actions[0].Arguments = '-Viewer'
            $null = $Task | Set-ScheduledTask -User $User
        }
    }
    If (!$ViewerOnly -and $Environment -eq 'PROD')
    {
        If ($Task.Actions[0].Arguments -eq '-Viewer')
        {
            Write-Information "Removing -Viewer argument from the tasks action because it's no longer needed."
            $Task.Actions[0].Arguments = ''
            $null = $Task | Set-ScheduledTask -User $User
        }
    }
}
else
{
    Write-Information 'Creating APROSync Scheduled Task'
    $Trigger = New-ScheduledTaskTrigger -AtLogOn -User $User
    If ($ViewerOnly)
    {
        $Action = New-ScheduledTaskAction -Execute $ProgramFolder\APRO_Sync.exe -Argument '-Viewer'
    }
    else
    {
        $Action = New-ScheduledTaskAction -Execute $ProgramFolder\APRO_Sync.exe
    }
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries
    $Task = New-ScheduledTask -Description 'Sync APRO with network shares' -Action $Action -Trigger $Trigger -Settings $Settings
    $RegTask = Register-ScheduledTask -TaskName APROSync -InputObject $Task -User $User

    Write-Information 'Setting Read and Execute rights on Scheduled Task for Authenticated Users'
    $SD = Get-ItemPropertyValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\APROSync' -Name SD
    $SDHelper = [wmiclass]"Win32_SecurityDescriptorHelper"
    $SDDL = $SDHelper.BinarySDToSDDL($SD).SDDL
    $SDNew = $SDHelper.SDDLToBinarySD($SDDL + "(A;ID;0x1301bf;;;AU)").BinarySD
    Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\APROSync' -Name SD -Value $SDNew -Force
    If (Get-WinEvent -ListLog APRO -ErrorAction SilentlyContinue)
    {
        Write-Information "EventLog APRO already exists."
    }
    else
    {
        Write-Information "Creating APRO Eventlog."
        New-EventLog -LogName APRO -Source 'APROSync Scheduled task' -ea 0
        New-EventLog -LogName APRO -Source 'APRO Launcher' -ea 0
        Limit-EventLog -LogName APRO -OverflowAction OverwriteAsNeeded -MaximumSize 10MB
    }
}
if ($Task = Get-ScheduledTask -TaskName APROFSHelperOn -TaskPath \ -ErrorAction SilentlyContinue)
{
    Write-Information 'Filesystem helper enabled task already present'
}
else
{
    Write-Information 'Creating filesystem helper enabled task'
    $Params = @{
        TaskName = 'APROFSHelperOn'
        Description = 'APRO Filesystem helper - Enable'
        Action = New-ScheduledTaskAction -Execute $ProgramFolder\APRO_FSHelper.exe -Argument "-User $User -Action Enable"
        Trigger = New-TaskEventTrigger -EventType TaskStartEvent
        Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DisallowDemandStart
        User = 'NT AUTHORITY\SYSTEM'
        RunLevel = 'Highest'
    }
    $RegTask = Register-ScheduledTask @Params -Force
}
if ($Task = Get-ScheduledTask -TaskName APROFSHelperOff -TaskPath \ -ErrorAction SilentlyContinue)
{
    Write-Information 'Filesystem helper enabled task already present'
}
else
{
    Write-Information 'Creating filesystem helper disabled task'
    $Params = @{
        TaskName = 'APROFSHelperOff'
        Description = 'APRO Filesystem helper - Disable'
        Action = New-ScheduledTaskAction -Execute $ProgramFolder\APRO_FSHelper.exe -Argument "-User $User -Action Disable"
        Trigger = @((New-TaskEventTrigger -EventType TaskSuccessEvent),(New-TaskEventTrigger -EventType TaskStartFailedEvent))
        Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DisallowDemandStart
        User = 'NT AUTHORITY\SYSTEM'
        RunLevel = 'Highest'
    }
    $RegTask = Register-ScheduledTask @Params -Force
}
$Eventlog = Get-WinEvent -ListLog Microsoft-Windows-TaskScheduler/Operational
if ($Eventlog.IsEnabled)
{
    Write-Information 'TaskScheduler eventlog is enabled'
}
else
{
    Write-Information 'Enabling TaskScheduler eventlog'
    $Eventlog.IsEnabled = $true
    $Eventlog.SaveChanges()
}
if (Get-ScheduledTask -TaskName APROSync -TaskPath \ -ErrorAction SilentlyContinue)
{
    Start-Launcher -User $User -Environment $Environment -Viewer:$ViewerOnly
    If (Get-Childitem $ProgramFolder\$Environment -File -Recurse)
    {
        Write-Information 'Installation was succesful'
    }
    else
    {
        Write-Error "Installation unsuccessful: no files were synced. Rolling back the changes." -Category InvalidResult
        Invoke-Expression -Command "$PSScriptRoot\APRO_Uninstall.ps1 -Environment $Environment -ViewerOnly:`$$ViewerOnly"
        exit 1
    }
    If ($OCRDll = Get-ChildItem -Path $ProgramFolder -Filter IproPlus.dll -Recurse)
    {
        If (@($OCRDll).Count -gt 1)
        {
            If ($OCRDll | where FullName -like *\PROD\*)
            {
                Write-Information 'Using PROD version of OCR'
                $OCRDll = $OCRDll | where FullName -like *\PROD\* | select -First 1
            }
            else
            {
                $OCRDll = $OCRDll | select -First 1
                Write-Information "Using $($OCRDll.FullName.Split('\')[3]) version of OCR"
            }
        }
        If (Get-Package '*2005 Redist*' -ErrorAction SilentlyContinue)
        {
            Write-Information 'VCRedist 2005 is already present'
        }
        else
        {
            Write-Information 'Installing VCRedist 2005 for OCR'
            $VCRedist = Get-Item "$($OCRDll.DirectoryName.TrimEnd('\bin'))\vcredist_x86.exe"
            Start-Process $VCRedist.FullName -ArgumentList '/Q' -Wait
        }
        If ($iProPlus = Get-ChildItem HKLM:\SOFTWARE\Classes\TypeLib -Recurse | where {$_.GetValue('') -like '*\iproplus.dll'})
        {
            if ($iProPlus.GetValue('') -eq $OCRDll.FullName)
            {
                Write-Information 'OCR dll has already been registered'
            }
            else
            {
                Write-Information 'Re-Registering IproPlus.dll for OCR'
                Register-OCRDll -Path $OCRDll.FullName
            }
        }
        else
        {
            Write-Information 'Registering IproPlus.dll for OCR'
            Register-OCRDll -Path $OCRDll.FullName
        }
    }
    else
    {
        Write-Information 'Unable to find the IproPlus.dll for OCR'
    }
    If (Test-Path $ProgramFolder\RwEasyMAPI64.exe)
    {
        If ($MAPIInstalled = Get-ItemProperty 'HKLM:\SOFTWARE\RAPWare\Easy MAPI' -ErrorAction Ignore)
        {
            Write-Information "RwEasyMAPI64 is already registered (v$($MAPIInstalled.RwEasyMAPI64))"
            If ($Environment -eq 'PROD')
            {
                Write-Information 'Registering PROD RwEasyMAPI64'
                Start-Process $ProgramFolder\RwEasyMAPI64.exe -ArgumentList '/regserver' -Wait
            }
        }
        else
        {
            Write-Information 'Registering RwEasyMAPI64'
            Start-Process $ProgramFolder\RwEasyMAPI64.exe -ArgumentList '/regserver' -Wait
        }
    }
}
else
{
    Write-Error "APROSync task creation failed. Rolling back the changes." -Category InvalidResult
    Invoke-Expression -Command "$PSScriptRoot\APRO_Uninstall.ps1 -Environment $Environment -ViewerOnly:`$$ViewerOnly"
    exit 1
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
    Write-Information "Protocol $Viewer is already present"
}
else
{
    Write-Information "Creating protocol $Viewer"
    $ViewFacturen = Get-ChildItem $ProgramFolder\$Environment -Recurse -Filter StartViewFacturen.exe
    If (@($ViewFacturen).Count -gt 1)
    {
        If ($ViewFacturen | where FullName -like *\PROD\*)
        {
            Write-Information 'Using PROD version of ViewFacturen'
            $ViewFacturen = $ViewFacturen | where FullName -like *\PROD\* | select -First 1
        }
        else
        {
            $ViewFacturen = $ViewFacturen | select -First 1
            Write-Information "Using $($ViewFacturen.FullName.Split('\')[3]) version of Viewfacturen"
        }
    }
    elseif (!$ViewFacturen)
    {
        Write-Error "Unable to find StartViewFacturen.exe in $Environment"
    }
    else
    {
        $Key = New-Item "$($HKCU.PSParentPath)\SOFTWARE\Classes\$Viewer\shell\open\command" -Value "`"$ProgramFolder\APRO_Launcher.exe`" -Executable `"$($ViewFacturen.FullName)`" -Arguments `"%1`"" -Force
        $Value = New-ItemProperty "$($HKCU.PSParentPath)\SOFTWARE\Classes\$Viewer" -Name 'URL Protocol'
        If ($Key)
        {
            Write-Information 'Viewer protocol created:'
            $Key
            $Value
        }
        else
        {
            Write-Error 'No protocol was created because of an unknown error'
        }
    }
}

Stop-Transcript
Copy-Item $LogFile C:\ProgramData\Microsoft\IntuneManagementExtension\Logs -Force

#endregion Main
