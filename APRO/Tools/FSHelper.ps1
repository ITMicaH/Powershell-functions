Param(
    [Parameter(mandatory)]
    [string]
    $User,

    [Parameter(mandatory)]
    [ValidateSet('Enable','Disable')]
    [string]
    $Action
)

#region Constants

$ProgramFolder = "$env:ProgramW6432\APRO"
$LogFile = "C:\ProgramData\APRO\APRO_FSHelper-$((Get-Date).ToShortDateString()).log"

#endregion Constants

#region Functions

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
    "$((Get-Date).ToString()) - $Type - $($Message.Trim())" | Out-File -FilePath $Path -Append -Force -ErrorAction Stop
    
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

#cleanup old log files
function Clear-LogFiles
{
    Param(
        $LogPath
    )

    $OldFiles = Get-ChildItem -Path $LogPath -Filter APRO_* | 
        where {$_ -match 'Sync|Launcher|FSHelper' -and $_.LastWriteTime -lt (Get-Date).AddDays(-5)}
    If ($OldFiles)
    {
        Write-Log "Removing $($OldFiles.Count) old sync & launcher log files"
        $OldFiles | Remove-Item -Force -ErrorAction Ignore
    }
    $OldFiles = Get-ChildItem -Path $LogPath -Filter APRO_* | 
        where {$_ -match 'Install|Cleanup' -and $_.LastWriteTime -lt (Get-Date).AddDays(-30)}
    If ($OldFiles)
    {
        Write-Log "Removing $($OldFiles.Count) old installer log files"
        $OldFiles | Remove-Item -Force -ErrorAction Ignore
    }
}

#endregion Functions

#region Main
If (FileInUse -File $LogFile)
{
    $LogFile = "C:\ProgramData\APRO\APRO_FSHelper-$((Get-Date).ToShortDateString())-$(Get-Random -Maximum 20).log"
    Write-Log "Logfile C:\ProgramData\APRO\APRO_FSHelper-$((Get-Date).ToShortDateString()).log was in use"
}
$Acl = Get-Acl $ProgramFolder
$Access = $Acl.Access.where{$_.IdentityReference -eq $User}
$Rule = New-Object System.Security.AccessControl.FileSystemAccessRule($User,'Modify','3','0','Allow')
if ($Action -eq 'Enable' -and !$Access)
{
    Write-Log "Adding rule to the ACL for $User"
    $Acl.SetAccessRule($Rule)
    $Acl | Set-Acl $ProgramFolder
}
elseif ($Access)
{
    Write-Log "Removing access rule for $User"
    $Acl.RemoveAccessRule($Rule)
    $Acl | Set-Acl $ProgramFolder
    $Owner = New-Object System.Security.Principal.Ntaccount('NT AUTHORITY\SYSTEM')
    If ($Items = Get-ChildItem $ProgramFolder -Recurse | Get-Acl | where owner -ne 'NT AUTHORITY\SYSTEM')
    {
        $Start = Get-Date
        Write-Output "Setting owner to SYSTEM for $($Items.Count) items"
        $Items.foreach{
            $_.SetOwner($Owner)
            Set-Acl -Path $_.Path -AclObject $_
        }
        $Time = (Get-Date) - $Start
        if (!$Time.TotalSeconds -lt 1)
        {
            Write-Log "Finished in $($Time.Milliseconds) milliseconds"
        }
        else
        {
            Write-Log "Finished in $([int]$Time.TotalSeconds) seconds"
        }
    }
}
if ($Action -eq 'Disable')
{
    If (Get-Process APRO_Launch*)
    {
        Write-Log 'Waiting for Launcher to finish'
        while (Get-Process APRO_Launch*)
        {
            sleep -Milliseconds 500
        }
    }
    If ($Updates = Get-ChildItem -Path C:\ProgramData\APRO -Filter *.exe)
    {
        Write-Log "Updates found: $($Updates.BaseName -join ', ')"
        $Updates | where BaseName -eq APRO_Sync | Move-Item -Destination $ProgramFolder -Force
        Start-Process $ProgramFolder\APRO_Sync.exe -ArgumentList '-UpdateTools'
    }
    Clear-LogFiles -LogPath C:\ProgramData\APRO
    Clear-LogFiles -LogPath C:\ProgramData\Microsoft\IntuneManagementExtension\Logs
}

#endregion Main

