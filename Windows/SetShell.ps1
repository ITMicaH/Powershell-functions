<#
.Synopsis
   Set Windows shell
.DESCRIPTION
   Sets the Windows operating systems shell on a local or remote computer
   to Windows Explorer, RES One Workspace or Citrix Desktop Lock using (remote) registry.
.EXAMPLE
   Set-WindowsShell -ShellType RESWorkspace -ComputerName PC001,PC002
   Changes the shell on computers PC001 and PC002 to the RES One Workspace shell.
.EXAMPLE
   Get-ADComputer -Filter * -SearchBase 'OU=Workstations,DC=CONTOSO,DC=LOCAL' | select * | Set-WindowsShell
   Retreives all computer objects from the Workstations OU and sets the shell to explorer.
.OUTPUTS
   Custom object with properties ComputerName, OldShell and NewShell
.NOTES
   Author: Michaja van der Zouwen
   Date  : 23-2-2017
.LINK
   https://itmicah.wordpress.com
#>
function Set-WindowsShell
{
    [CmdletBinding(SupportsShouldProcess=$true,
                  ConfirmImpact='Medium')]
    [Alias("setshell")]
    Param
    (
        # Type of shell
        [Parameter(Position=0)]
        [ValidateSet("Explorer", "RESWorkspace", "DesktopLock")]
        [string]
        $ShellType = 'Explorer',
        
        # Name of a remote computer
        [Parameter(ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true, 
                   Position=1)]
        [Alias("DNSHostName")]
        [Alias("PSComputerName")]
        [string[]] 
        $ComputerName = 'localhost'
    )

    Begin
    {
        Write-Verbose 'Setting necessary variables...'
        $htShellNames = @{
            Explorer = 'Windows Explorer'
            RESWorkspace = 'RES One Workspace'
            DesktopLock = 'Citrix Desktop Lock'
        }
        $ShellKey = 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
        Write-Verbose 'Variables set.'
    }
    Process
    {
        foreach ($Computer in $ComputerName)
        {
            Write-Verbose "Processing '$Computer'..."
            try
            {
                Write-Verbose 'Connecting to remote registry...'
                $Reg = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $Computer)
                Write-Verbose 'Connection established.'
            }
            catch
            {
                If (Test-Connection $ComputerName -Count 1 -ErrorAction SilentlyContinue)
                {
                    Write-Error "Unable to connect to registry on computer '$Computer'."
                }
                else
                {
                    Write-Error "Computer '$Computer' appears to be offline."
                }
                continue
            }
            try
            {
                $Key = $Reg.OpenSubKey($ShellKey,$true)
                $CurrentShellValue = $Key.GetValue('Shell')
                switch -Regex ($CurrentShellValue)
                {
                    explorer {$CurrentShell = 'Windows Explorer'}
                    pwrstart {$CurrentShell = 'RES One Workspace'}
                    SelfServicePlugin   {$CurrentShell = 'Citrix Desktop Lock'}
                }
                Write-Verbose "Current shell is $CurrentShell."
                switch ($ShellType)
                {
                    RESWorkspace {
                        If (Test-Path 'C:\Program Files\RES Software\Workspace Manager\pwrstart.exe')
                        {
                            $NewShell = 'C:\Program Files\RES Software\Workspace Manager\pwrstart.exe'
                            $Pwrinit = 'C:\Program Files\RES Software\Workspace Manager\pwrinit.exe'
                        }
                        elseif (Test-Path 'C:\Program Files (x86)\RES Software\Workspace Manager\pwrstart.exe')
                        {
                            $NewShell = 'C:\Program Files (x86)\RES Software\Workspace Manager\pwrstart.exe'
                            $Pwrinit = 'C:\Program Files (x86)\RES Software\Workspace Manager\pwrinit.exe'
                        }
                        elseif (Test-Path 'C:\Program Files\Ivanti\Workspace Control\pwrstart.exe')
                        {
                            $NewShell = 'C:\Program Files\Ivanti\Workspace Control\pwrstart.exe'
                            $Pwrinit = 'C:\Program Files\Ivanti\Workspace Control\pwrinit.exe'
                        }
                        elseif (Test-Path 'C:\Program Files (x86)\Ivanti\Workspace Control\pwrstart.exe')
                        {
                            $NewShell = 'C:\Program Files (x86)\Ivanti\Workspace Control\pwrstart.exe'
                            $Pwrinit = 'C:\Program Files (x86)\Ivanti\Workspace Control\pwrinit.exe'
                        }
                        else
                        {
                            Write-Error -Message "Unable to find pwrstart.exe" -Category ObjectNotFound -TargetObject $Computer
                            continue
                        }
                                
                    }
                    DesktopLock {
                        If (Test-Path 'C:\Program Files\Citrix\ICA Client\SelfServicePlugin\selfservice.exe')
                        {
                            $NewShell = 'C:\Program Files\Citrix\ICA Client\SelfServicePlugin\selfservice.exe'
                        }
                        elseif (Test-Path 'C:\Program Files (x86)\Citrix\ICA Client\SelfServicePlugin\selfservice.exe')
                        {
                            $NewShell = 'C:\Program Files (x86)\Citrix\ICA Client\SelfServicePlugin\selfservice.exe'
                        }
                        else
                        {
                            Write-Error -Message "Unable to find selfservice.exe" -Category ObjectNotFound -TargetObject $Computer
                            continue
                        }
                    }
                    Explorer {
                        $NewShell = 'explorer.exe'
                    }
                }
                $ShowOutput = $false
                If ($CurrentShell -ne $htShellNames[$ShellType])
                {
                    if ($pscmdlet.ShouldProcess($Computer, "Set shell to '$($htShellNames[$ShellType])'"))
                    {
                        $ShowOutput = $true
                        
                        $Key.SetValue('Shell', $NewShell)
                        $UserInit = $Key.GetValue('Userinit')
                        If ($ShellType -eq 'RESWorkspace')
                        {
                            If ($UserInit -notmatch 'pwrinit.exe')
                            {
                                Write-Verbose "Adding 'pwrinit.exe' to userinit value..."
                                $Key.SetValue('Userinit', "$Pwrinit,$UserInit")
                            }
                            else
                            {
                                Write-Verbose "'pwrinit.exe' already in userinit value!"
                            }
                        }
                        else
                        {
                            If ($UserInit -match 'pwrinit.exe')
                            {
                                Write-Verbose "Removing 'pwrinit.exe' from userinit value..."
                                $NewUserinit = $UserInit.Split(',') -notmatch 'pwrinit' -join ','
                                $Key.SetValue('Userinit', $NewUserinit)
                            }
                            else
                            {
                                Write-Verbose "'pwrinit.exe' not in userinit value!"
                            }
                        }
                    } #End If ShouldProcess
                }
                else
                {
                    Write-Verbose 'Shell is already correct!'
                    $ShowOutput = $true
                }
                if ($ShowOutput -and !$WhatIfPreference.IsPresent)
                {
                    [pscustomobject]@{
                        ComputerName = $Computer
                        OldShell = $CurrentShell
                        NewShell = $htShellNames[$ShellType]
                    }
                }
            }
            catch
            {
                Write-Error $_
            }
            Write-Verbose "Finished processing '$Computer'."
        }
    }
    End
    {
        Write-Verbose 'Finished all tasks.'
    }
}
