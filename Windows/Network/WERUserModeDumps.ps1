<#
.Synopsis
   Enable User-Mode (Application Crash) dumps on a computer.
.DESCRIPTION
   Enables User-Mode (Application Crash) dumps using Windows Error Reporting on a local or remote computer.
   Requires to be run under an account with admin rights on the computer.
.PARAMETER ComputerName
   The name(s) of the computer(s) where you want to enable User-Mode dumps.
.PARAMETER Process
   The name of a process to create dumps for. If omitted all processes will trigger a dump creation.
.PARAMETER DumpFolder
   The path (folder) where the dump files will be stored. If the folder doesn't exist it will be created.
.PARAMETER DumpCount
   The maximum number of dump files in the folder.
.PARAMETER DumpType
   The type of dump that will be created.
.PARAMETER CustomDumpFlags
   Use only when DumpType is set to 'CustomDump'. The options are a bitwise combination of the MINIDUMP_TYPE enumeration values.
   For all possible values check out the article 'MINIDUMP_TYPE enumeration':
   https://msdn.microsoft.com/en-us/library/ms680519.aspx
.EXAMPLE
   Enable-WERUserModeDumps -ComputerName PC001,PC002
   Enables User-Mode dumps on PC001 and PC002 using default values:
   10 mini dump maximum in folder '%LOCALAPPDATA%\CrashDumps'
.EXAMPLE
   Enable-WERUserModeDumps -ComputerName PC001,PC002 -Process iexplore.exe -DumpFolder D:\Dumps -DumpType FullDump
   Enables User-Mode dumps on PC001 and PC002 using default values:
   10 full dump maximum in folder 'D:\Dumps' for application Internet Explorer (iexplorer.exe)
.EXAMPLE
   Enable-WERUserModeDumps -ComputerName PC001,PC002 -DumpFolder D:\Dumps -DumpType CustomDump -CustomDumpFlags 6100
   Enables User-Mode dumps on PC001 and PC002 using default values:
   10 custom dump maximum in folder 'D:\Dumps' using types: MiniDumpWithProcessThreadData,MiniDumpWithCodeSegs,MiniDumpWithoutAuxiliaryState
.NOTES
   Author: Michaja van der Zouwen
   Date  : 21-7-2016
.LINKS
#>
function Enable-WERUserModeDumps
{
    [CmdletBinding()]
    Param
    (
        # Computer to enable dumps on
        [Parameter(ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        [Alias('DNSHostName')]
        [string[]]
        $ComputerName = 'localhost',

        # Name of a process to create dumps for
        [Parameter(Position=1)]
        [string]
        $Process,

        # The path where the dump files are to be stored
        [Parameter(Position=2)]
        [Alias('Path')]
        [string]
        $DumpFolder = '%LOCALAPPDATA%\CrashDumps',

        # The maximum number of dump files in the folder
        [Parameter(Position=3)]
        [int]
        $DumpCount = 10,

        # The type of dump that should be created
        [Parameter(Position=4)]
        [ValidateSet('CustomDump','MiniDump','FullDump')]
        [string]
        $DumpType = 'MiniDump',

        # The custom dump options to be used.
        [Parameter(Position=5)]
        [int]
        $CustomDumpFlags = 121
    )

    Begin
    {
        Write-Verbose "Validating 'Application' parameter value..."
        switch -regex ($Application)
        {
            '.+\.exe$'   {Write-Verbose "Parameter value is valid.";break}
            '^.+(\..+)$' {throw "Invalid extension '$($Matches[1])' detected. Make sure the application has a '.exe' extension."}
            default      {$Application = "$Application.exe";Write-Verbose "Added '.exe' extension to application value."}
        }
        If ($DumpType -ne 'CustomDump' -and $CustomDumpFlags -ne 121)
        {
            Throw "The parameter 'CustomDumpFlags' can only be used when 'DumpType' is set to 'CustomDump'."
        }
        switch ($DumpType)
        {
            'CustomDump' {$DumpTypeData = 0}
            'MiniDump'   {$DumpTypeData = 1}
            'FullDump'   {$DumpTypeData = 2}
        }
        If ($DumpType -eq 'CustomDump')
        {
            Write-Verbose "Converting CustomDumpFlags value to decimal..."
            $CustomDumpFlags = [Convert]::ToInt32($CustomDumpFlags,16)
            Write-Verbose "Conversion complete."
        }
    }
    Process
    {
        foreach ($Computer in $ComputerName)
        {
            Write-Verbose "Processing computer '$Computer'..."

            Write-Verbose "->`tChecking DumpFolder existence..."
            Try
            {
                If ($DumpFolder -ne '%LOCALAPPDATA%\CrashDumps')
                {
                    $DumpFolderUNC = "\\$Computer\$($DumpFolder.Replace(':','$'))"
                    If (Test-Path $DumpFolderUNC)
                    {
                        Write-Verbose "->`tFolder '$DumpFolder' already exists."
                    }
                    else
                    {
                        Write-Verbose "->`tCreating folder '$DumpFolder'..."
                        $Folder = New-Item $DumpFolderUNC -ItemType Directory -ea 1
                        Write-Verbose "->`tFolder created."
                    }
                }
            }
            catch
            {
                Write-Error $_
                continue
            }
            Write-Verbose "->`tConnecting to registry..."
            try
            {
                $Reg = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $Computer)
            }
            catch
            {
                Write-Error $_
                continue
            }
            Write-Verbose "->`tConnection established."
            
            $Key = $Reg.OpenSubKey('SOFTWARE\Microsoft\Windows\Windows Error Reporting',$true)
            If ($Key.GetSubKeyNames() -notcontains 'LocalDumps')
            {
                Write-Verbose "->`tCreating LocalDumps registry key..."
                Try
                {
                    $Null = $Key.CreateSubKey('LocalDumps')
                }
                catch
                {
                    Write-Error $_
                    continue
                }
                Write-Verbose "->`tKey created."
            }
            $DumpKey = $Key.OpenSubKey('LocalDumps',$true)
            If ($Application)
            {
                If ($DumpKey.GetSubKeyNames() -notcontains $Application)
                {
                    Write-Verbose "->`tCreating '$Application' subkey..."
                    try
                    {
                        $null = $DumpKey.CreateSubKey($Application)
                    }
                    catch
                    {
                        Write-Error $_
                        continue
                    }
                    Write-Verbose "->`tSubkey created."
                }
                $DumpKey = $DumpKey.OpenSubKey($Application,$true)
            }
            Write-Verbose "->`tSetting values for Application crash dumps..."
            try
            {
                $Null = $DumpKey.SetValue('DumpFolder', $DumpFolder, [Microsoft.Win32.RegistryValueKind]::ExpandString)
                Write-Verbose "`t->`tDumpFolder value set to '$DumpFolder'"
                $Null = $DumpKey.SetValue('DumpCount', $DumpCount, [Microsoft.Win32.RegistryValueKind]::DWORD)
                Write-Verbose "`t->`tDumpCount value set to '$DumpCount'"
                $Null = $DumpKey.SetValue('DumpType', $DumpTypeData, [Microsoft.Win32.RegistryValueKind]::DWORD)
                Write-Verbose "`t->`tDumpType value set to '$DumpTypeData'"
                If ($DumpType -eq 'CustomDump')
                {
                    $Null = $DumpKey.SetValue('CustomDumpFlags', $CustomDumpFlags, [Microsoft.Win32.RegistryValueKind]::DWORD)
                    Write-Verbose "->`t`tCustomDumpFlags value set to '$CustomDumpFlags'"
                }
                Write-Verbose "->`tAll required values were set."
            }
            catch
            {
                Write-Error $_
                continue
            }
            $reg.Close()
            Write-Verbose "->`tRegistry connection closed."
            $WerSVC = Get-Service WerSvc -ComputerName $Computer
            If ($WerSVC.Status -eq 'Running')
            {
                Write-Verbose "->`tRestarting WER Service (WerSvc)..."
                $WerSVC | Restart-Service
                If ($?)
                {
                    Write-Verbose "->`tService restarted."
                }
            }
            else
            {
                Write-Verbose "->`tStarting WER Service (WerSvc)..."
                $WerSVC | Start-Service
                If ($?)
                {
                    Write-Verbose "->`tService started."
                }
            }
            Write-Verbose "Finished processing computer."
        } #end foreach computer
    }
    End
    {
        Write-Verbose 'All computers have been processed.'
    }
}
