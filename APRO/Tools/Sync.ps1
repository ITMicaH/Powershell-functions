Param(
    # MultiThread count for robocopy command
    [int]
    $MT = 32,

    # Also sync PROD invoice viewer
    [switch]
    $Viewer,

    # Update the tools
    [switch]
    $UpdateTools
)

#region Constants

$UncPaths = @{
    PROD = [System.Environment]::GetEnvironmentVariable('APROPRD','USER') #PRD share
    ACC = [System.Environment]::GetEnvironmentVariable('APROACC','USER')  #ACC share
    TEST = [System.Environment]::GetEnvironmentVariable('APROTST','USER') #TEST share
}
$ProgramFolder = "$env:ProgramW6432\APRO"
$LogFile = "C:\ProgramData\APRO\APRO_Sync-$((Get-Date).ToShortDateString()).log"
$OCRMode = @{
    PROD = ''
    ACC = ''
    TEST = ''
}
$RightsAppUrl = 'https://<AzureFunction>.azurewebsites.net/api/GetAPRORights?code=<function code>'

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
            break
        }
    }
    try
    {
        "$((Get-Date).ToString()) - $Type - $($Message.Trim())" | Out-File -FilePath $Path -Append -Force -ErrorAction Stop
    }
    catch {}
    
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
        $MT,

        #Only list changes
        [switch]
        $ListOnly,

        #Only sync viewer
        [switch]
        $Viewer
    )

    If ($Software[$Environment] -eq 'ERROR')
    {
        Write-Log "Skipping sync for $Environment because of an error" -Type WARNING
        return
    }
    If ($Viewer -and $Environment -eq 'PROD')
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
            'OracleDatabase.txt',
            'FactuurLauncher.exe'
        )
        $ViewerOnly = $true
        If (Test-Path "$Destination\APRO Imaging")
        {
            Write-Log "Folder $Destination\APRO Imaging exists"
        }
        else
        {
            Write-Log "Creating folder $Destination\APRO Imaging"
            $null = New-Item "$Destination\APRO Imaging" -ItemType Directory -Force
        }
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
            Write-Log 'Only including Viewer files for PROD'
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
        elseif ($OCRMode[$Environment] -eq 'Folder')
        {
            $Command += '/XF OCR.zip'
        }
        elseif ($OCRMode[$Environment] -eq 'ZipFile')
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
            Invoke-Expression -Command ($Command -join ' ')
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
        Write-Log "Unable to reach path $Source" -Type ERROR -EventID 115
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

#Create item in the users start menu
function New-APROStartMenuItem
{
    [CmdletBinding()]
    Param(
        #Name of the shortcut
        [Parameter(mandatory)]
        [string]
        $Name,
        
        #Path to the programs executable
        [Parameter(mandatory,ParameterSetName='Executable')]
        [string]
        $Executable,

        # create send log shortcut
        [Parameter(mandatory,ParameterSetName='Logs')]
        [switch]
        $SendLogs,

        #Folder in startmenu
        [string]
        $Folder
    )

    $Shell = New-Object -ComObject WScript.Shell
    If ($PSBoundParameters.Folder)
    {
        If (!(Test-Path "$ENV:AppData\Microsoft\Windows\Start Menu\Programs\$Folder"))
        {
            Write-Log "Creating startmenu folder $Folder"
            $null = New-Item "$ENV:AppData\Microsoft\Windows\Start Menu\Programs" -Name $Folder -ItemType Directory
        }
        $LnkFile = "$ENV:AppData\Microsoft\Windows\Start Menu\Programs\$Folder\$Name.lnk"
    }
    else
    {
        $LnkFile = "$ENV:AppData\Microsoft\Windows\Start Menu\Programs\$Name.lnk"

    }
    If (Test-Path $LnkFile)
    {
        Write-Log "Shortcut $LnkFile already exists. Skipping creation."
        If ($PSBoundParameters.Executable -and $Shell.CreateShortcut($LnkFile).Arguments -like "*$Executable`"")
        {
            Write-Log 'Arguments are correct'
            return
        }
        elseif ($PSBoundParameters.SendLogs -and $Shell.CreateShortcut($LnkFile).Arguments -eq '-SendLogs')
        {
            Write-Log 'Arguments are correct'
            return
        }
        else
        {
            Write-Log "Arguments are incorrect, editing shortcut $LnkFile"
        }
    }
    else
    {
        Write-Log "Creating shortcut $LnkFile"
    }

    $Shortcut = $Shell.CreateShortcut($LnkFile)
    $Shortcut.TargetPath = "C:\Program Files\APRO\APRO_Launcher.exe"
    If ($PSBoundParameters.Executable)
    {
        $Shortcut.IconLocation = "$Executable,0"
        $Shortcut.Arguments = "-Executable `"$Executable`""
    }
    elseif ($PSBoundParameters.SendLogs)
    {
        $Shortcut.IconLocation = "C:\Windows\System32\shell32.dll,156"
        $Shortcut.Arguments = '-SendLogs'
    }
    $Shortcut.Save()
}

#Get the correct executable
function Get-Executable
{
    Param(
        [string]
        $Path,

        [ValidateSet('APROImaging.exe','APROEnterInvoices.exe','APROBankingGateway.exe')]
        [string]
        $Name
    )
    Write-Information "Getting executable $Name"
    $Start = Get-Date
    Do
    {
        sleep -Milliseconds 500
    }
    until ($Executable = Get-ChildItem $Path -Recurse -Filter $Name -ErrorAction Ignore | sort {$_.FullName.Length} | select -Last 1)
    Write-Information "Waiting took $(((Get-Date)- $Start).Seconds) seconds"
    return $Executable
}

#Get files that need updates
function Get-Updates
{
    Param(
        [bool]
        $Viewer
    )
    $Output = @{}
    foreach ($Env in $Environments)
    {
        $Params = @{
		    Source = $UncPaths[$Env.Name]
		    Destination = $Env.FullName
		    Environment = $Env.Name
		    Software = $Software
		    ListOnly = $true
	    }
        If ($Env.Name -eq 'PROD' -and $Viewer)
        {
            $Params.Add('Viewer',$true)
        }
	    $Output.Add($Env.Name, @(Sync-Environment @Params).Count)
    }
    return $Output
}

#endregion functions

#region Prerequisites

$Error.Clear()
$LogRoot = Split-Path $LogFile
If (Test-Path $LogRoot)
{
    Write-Verbose "$LogRoot exists"
    If (FileInUse -File $LogFile)
    {
        $LogFile = "C:\ProgramData\APRO\APRO_Sync-$((Get-Date).ToShortDateString())-$(Get-Random -Maximum 20).log"
        Write-Log "Logfile C:\ProgramData\APRO\APRO_Sync-$((Get-Date).ToShortDateString()).log was in use"
    }
}
else
{
    Write-Verbose "Creating $LogRoot folder for logfile"
    $null = New-Item $LogRoot -ItemType Directory -Force
}
$Params = $PSBoundParameters.Keys.ForEach{"-$_ $($PSBoundParameters[$_])"} -join ' '
Write-Log "New APRO Sync started with arguments $Params"
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
If ($NotWritable = FileInUse $ProgramFolder\APRO_Logo.png)
{
    Write-Log 'Waiting for filesystem helper to finish'
    $End = (Get-Date).AddSeconds(30)
    while ($NotWritable -and (Get-Date) -lt $End)
    {
        $NotWritable = FileInUse $ProgramFolder\APRO_Logo.png
        sleep -Milliseconds 500
    }
    If ($NotWritable)
    {
        Write-Log 'Filesystem helper failed to make folder writable within 30 seconds' -Type ERROR -EventID 113
        exit 1
    }
}

#endregion Prerequisites

#region Main

If ($PSBoundParameters.UpdateTools)
{
    If ($Updates = Get-ChildItem -Path C:\ProgramData\APRO -Filter *.exe)
    {
        Write-Log "Updates found: $($Updates.BaseName -join ', ')"
        $Updates | Move-Item -Destination $ProgramFolder -Force
        if ($?)
        {
            Write-Log 'Finished updating'
            If ($Updates.BaseName -contains 'RwEasyMAPI64')
            {
                Write-Log 'Registering new RwEasyMAPI64'
                Start-Process $ProgramFolder\RwEasyMAPI64.exe -ArgumentList '/regserver' -Wait
            }
        }
        else
        {
            Write-Log "Updates failed: $($Error[0].Message)" -Type ERROR
        }
    }
    else
    {
        Write-Log 'No updated tools found' -Type WARNING
    }
    Copy-Item $LogFile C:\ProgramData\Microsoft\IntuneManagementExtension\Logs -Force -ErrorAction Ignore
    exit 0
}
$Software = Get-AllowedSoftware
$Environments = Get-ChildItem $ProgramFolder -Directory
$Updates = Get-Updates -Viewer:$Viewer
$UpdateCount = $Updates.Values | measure -Sum
If ($UpdateCount.Sum)
{
    Write-Log "APRO needs to be updated. Files to copy: $($UpdateCount.Sum)" -EventID 1
    [System.Environment]::SetEnvironmentVariable('APROProgress',"0/$($UpdateCount.Sum)",'User')
    $Current = 0
    foreach ($Update in $Updates.Keys.Where{$Updates[$_] -gt 0})
    {
        $Env = $Environments | where Name -eq $Update
        $Endresult = $null
        Write-Log "Current environment is $($Env.Name)" -EventID 2
        $Params = @{
			Source = $UncPaths[$Env.Name]
			Destination = $Env.FullName
			Environment = $Env.Name
			Software = $Software
            MT = $MT
		}
        If ($Env.Name -eq 'PROD' -and $Viewer)
        {
            $Params.Add('Viewer',$true)
        }
        $ErrorCount = 0
		Sync-Environment @Params | foreach {
            If ($_ -match 'New File|Newer|Older|EXTRA File')
            {
                    $Current++
                    [System.Environment]::SetEnvironmentVariable('APROProgress',"$Current/$($UpdateCount.Sum)",'User')
                    Write-Log "$_ ($Current/$($UpdateCount.Sum))"
            }
            elseif ($_ -like '*ERROR*Copying File*')
            {
                $Current--
                $ErrorCount++
                [System.Environment]::SetEnvironmentVariable('APROProgress',"$Current/$($UpdateCount.Sum)",'User')
                [System.Environment]::SetEnvironmentVariable('APROErrorCount',$ErrorCount,'User')
                Write-Log "$_ ($Current/$($UpdateCount.Sum))"
                Write-Log -Message "Path $($Params.Source) is not available. VPN status: $((Get-VpnConnection -Name TKWSVPN).ConnectionStatus)" -Type ERROR -EventID 112
                
            }
            else
            {
                $_ | Out-File $LogFile -Append -ErrorAction Ignore
                If ($_ -match 'Total\s+Copied\s+Skipped\s+Mismatch\s+FAILED\s+Extras')
                {
                    $EndResult = @(
                        "Endresult for $($Env.Name):`n"
                        $_
                    )
                }
                elseif ($EndResult)
                {
                    if ($_ -like '*Files :*')
                    {
                        $Result = $_.trim() -Split '\s+'
                        if ($Fails = [int]$Result[6])
                        {
                            Write-Log -Message "File copy failures detected: $Fails files were not synced." -Type ERROR -EventID 114
                            Write-Error "Er zijn fouten ontdekt bij het synchroniseren. $Fails bestanden zijn niet gekopieerd."
                        }
                    }
                    $EndResult += $_
                }
            }
        }
        if ($EndResult)
        {
            Write-EventLog -LogName APRO -Source 'APROSync Scheduled task' -EntryType Information -EventId 2 -Message ($EndResult | Out-String)
        }
    }
    [System.Environment]::SetEnvironmentVariable('APROProgress',$null,'User')
    [System.Environment]::SetEnvironmentVariable('APROErrors',$null,'User')
    $Updates = Get-Updates -Viewer:$Viewer
    $UpdateCount = $Updates.Values | measure -Sum
    If ($UpdateCount.Sum)
    {
        Write-Log "Still missing $($UpdateCount.Sum) files" -Type WARNING -EventID 5
    }
    Write-Log "APRO has been updated" -EventID 3
}
else
{
    Write-Log 'APRO is up-to-date' -EventID 3
}
foreach ($Env in $Environments)
{
    If ($Env.Name -eq 'PROD' -and $Viewer)
    {
        Write-Log 'Skipping startmenu item for PROD (viewer only)'
    }
    else
    {
        Write-Log 'Checking startmenu items'
        If ($Software[$Env.Name] -contains 'IMA')
        {
            If ($Imaging = Get-Executable -Path $Env.FullName -Name APROImaging.exe)
            {
                New-APROStartMenuItem -Name "APRO Imaging $Env" -Executable $Imaging.FullName -Folder APRO
            }
        }
        If ($Software[$Env.Name] -contains 'Enter')
        {
            If ($Invoices = Get-Executable -Path $Env.FullName -Name APROEnterInvoices.exe)
            {
                New-APROStartMenuItem -Name "APRO Enter Invoices $Env" -Executable $Invoices.FullName -Folder APRO
            }
        }
        If ($Software[$Env.Name] -contains 'BANKING')
        {
            If ($BankingGW = Get-Executable -Path $Env.FullName -Name APROBankingGateway.exe)
            {
                New-APROStartMenuItem -Name "APRO Banking Gateway $Env" -Executable $BankingGW.FullName -Folder APRO
            }
        }
    }
}
If (Test-Path 'C:\Program Files\Microsoft Office\root\Office16\OUTLOOK.EXE')
{
    New-APROStartMenuItem -Name 'Verzend APRO logbestanden' -SendLogs -Folder APRO
}
else
{
    Write-Log 'No Outlook present so mo logfiles startmenu item'
}
If ($Error)
{
    Write-Log 'End of script. The following errors occured:'
    $Error | select Exception,TargetObject,CategoryInfo,@{name='Line';expression={$_.InvocationInfo.Line}},ScriptStackTrace | Out-File -FilePath $LogFile -Append -ErrorAction Ignore
}
'=' * 100 + "`n`n" | Out-File $LogFile -Append -ErrorAction Ignore
Copy-Item $LogFile C:\ProgramData\Microsoft\IntuneManagementExtension\Logs -Force -ErrorAction Ignore

#endregion Main
