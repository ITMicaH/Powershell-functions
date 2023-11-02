<#
.Synopsis
   Update Citrix Backend server components
.DESCRIPTION
   This script will detect which Citrix backend server application is installed and upgrade the components
   by mounting the appropriate ISO file and perform a silent update. If Provisioning Services is present
   in the environment the PVS iso must also be present on the ISOPath location. ISO names cannot be altered.
.EXAMPLE
   Upgrade-CitrixComponents -ISOPPath \\FileServer\Share\Citrix
#>
function Upgrade-CitrixComponents
{
    [CmdletBinding()]
    Param(
        #Path to the folder containing all Citrix iso's
        [System.IO.DirectoryInfo]
        $ISOPath
    )
    
    Begin
    {
        #region constants

        #Path for logfiles
        $LogPath = 'C:\Windows\Logs\CVADUpgrade'
        #Don't upgrade Vda Update Service DB (Bypasses cloud prompt)
        $SkipVdaUpdateService = $true

        #endregion constants

        #region functions

        #Update a CVAD component
        function Update-CitrixComponent
        {
            [CmdletBinding()]
            Param(
                [string]
                $PackageName,

                [System.IO.FileInfo]
                $ISOPath,
        
                [string]
                $SetupExe,

                [string[]]
                $ArgumentsList,

                [version]
                $CurrentVersion,

                [switch]
                $SkipVUS
            )

            Write-Verbose "Upgrading component $PackageName"
            $Media = Mount-DiskImage $ISOPath.FullName -PassThru -ErrorAction Stop | Get-Volume
            $Setup = Get-Item "$($Media.DriveLetter):\$SetupExe"
            if ($ArgumentsList -contains "/Components LICENSESERVER")
            {
                $LicExe = Get-Item "$($Media.DriveLetter):\x64\Licensing\CitrixLicensing.exe"
                $LicUpgrade = $LicExe.VersionInfo.ProductVersion -gt $CurrentVersion
            }
            if ($ArgumentsList -contains "/Components CONTROLLER")
            {
                $XDSite = Get-XDSite
            }
            if ([version]$Setup.VersionInfo.ProductVersion -gt $CurrentVersion -or $LicUpgrade)
            {
                $Start = Get-Date
                Start-Process $Setup.FullName -ArgumentList $ArgumentsList -Wait
                $InstallTime = (Get-Date) - $Start
                Write-Verbose "Upgrade process completed in $([int]$InstallTime.TotalMinutes) minutes"
                $NewVersion = [version](Get-Package $PackageName -ProviderName msi).Version
                If ($NewVersion -gt $CurrentVersion)
                {
                    Write-Verbose "$PackageName was successfully upgraded from $CurrentVersion to $NewVersion"
                    if ($ArgumentsList -contains "/Components CONTROLLER")
                    {
                        $CurrentDBVersion = Get-BrokerInstalledDbVersion
                        if ([version]$CurrentDBVersion.ToString(3) -lt [version]$NewVersion.ToString(3))
                        {
                            If ($PSBoundParameters.SkipVUS)
                            {
                                Update-CitrixDatabase -TargetVersion ($NewVersion.ToString(3) + '.0') -XDSite $XDSite -SkipVUS
                            }
                            else
                            {
                                Update-CitrixDatabase -TargetVersion ($NewVersion.ToString(3) + '.0') -XDSite $XDSite
                            }
                        }
                    }
                }
                else
                {
                    if ($ErrLine = Get-Content "$LogPath\Citrix\XenDesktop Installer\XenDesktop Installation.log" -ea 0 | where {$_ -like '*$ERR$*'})
                    {
                        $Reason = " Possible reason: $($errLine.Split(':')[-1])"
                    }

                    Write-Error "$PackageName upgrade failed. Please upgrade manually.$Reason"
                }
            }
            else
            {
                Write-Error "Unable to upgrade $PackageName. Version installed: $CurrentVersion, version upgrade: $($Setup.VersionInfo.ProductVersion)"
            }
            $null = Dismount-DiskImage -ImagePath $ISOPath
        }

        #Update a PVS component
        function Update-CitrixPVS
        {
            [CmdletBinding()]
            Param(
                [string]
                $PackageName,

                [System.IO.FileInfo]
                $ISOPath,
        
                [string]
                $SetupExe,

                [version]
                $CurrentVersion
            )

            Write-Verbose "Upgrading $($PackageName.Trim('*'))"
            $Media = Mount-DiskImage $ISOPath.FullName -PassThru -ErrorAction Stop | Get-Volume
            $Setup = Get-Item "$($Media.DriveLetter):\$SetupExe"
            If ($PackageName -eq '*Provisioning Server*')
            {
                Stop-Service StreamService
            }
            if ([version]$Setup.VersionInfo.ProductVersion -gt $CurrentVersion)
            {
                $Start = Get-Date
                Start-Process $Setup.FullName -ArgumentList '/s','/v"/qn"' -Wait
                $InstallTime = (Get-Date) - $Start
                Write-Verbose "Upgrade process completed in $([int]$InstallTime.TotalMinutes) minutes"
                $NewVersion = [version](Get-Package $PackageName).Version
                If ($NewVersion -gt $CurrentVersion)
                {
                    Write-Verbose "$($PackageName.Trim('*')) was successfully upgraded from $CurrentVersion to $NewVersion"
                }
                else
                {
                    Write-Error "$($PackageName.Trim('*')) upgrade failed. Please upgrade manually."
                }
            }
            else
            {
                Write-Error "Unable to upgrade $($PackageName.Trim('*')). Version installed: $CurrentVersion, version upgrade: $($Setup.VersionInfo.ProductVersion)"
            }
            If ($PackageName -eq '*Provisioning Server*')
            {
                if (Test-Path 'C:\ProgramData\Citrix\Provisioning Services\ConfigWizard.ans')
                {
                    Write-Verbose "Running ConfigWizard in silent mode"
                    Start-Process "C:\Program Files\Citrix\Provisioning Services\ConfigWizard.exe" -ArgumentList '/a' -Wait
                }
                else
                {
                    If ([Environment]::UserInteractive)
                    {
                        Write-Verbose "Running ConfigWizard in interactive mode and saving config"
                        Start-Process "C:\Program Files\Citrix\Provisioning Services\ConfigWizard.exe" -ArgumentList '/s' -Wait
                    }
                    else
                    {
                        Write-Error "Unable to run ConfigWizard silently: No ConfigWizard.ans file is present. Please run ConfigWizard with the /s parameter on this server."
                    }
                }
            }
            else
            {
                Write-Verbose "Registering PVS SnapIn"
                $Params = @{
                    FilePath = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\installutil.exe'
                    ArgumentList = 'C:\Program Files\Citrix\Provisioning Services Console\Citrix.PVS.SnapIn.dll'
                }
                Start-Process @Params -Wait
            }
            $null = Dismount-DiskImage -ImagePath $ISOPath
        }

        #Update the CVAD database
        function Update-CitrixDatabase
        {
            [CmdletBinding()]
            Param(
                [version]
                $TargetVersion,

                [Citrix.XenDesktopPowerShellSdk.ServiceInterfaces.Configuration.Site]
                $XDSite,

                [switch]
                $SkipVUS
            )

            Write-Verbose "Updating databases to $TargetVersion"
            $Commands = Get-Command -Verb Get -Noun *DBConnection | select -ExpandProperty Name -Unique
            If ($PSBoundParameters.SkipVUS)
            {
                Write-Verbose "Skipping VDA Update Service"
                $Commands = $Commands -notmatch 'vusdb'
            }
            $Connections = foreach ($Command in $Commands)
            {
                [pscustomobject]@{
                    DBType = $Command.Substring(4,$Command.Length-16)
                    String = Invoke-Expression "$Command" -ErrorAction SilentlyContinue
                }
            }
            $DBScripts = foreach ($Connection in $Connections)
            {
                $DBName = $Connection.String.Split(';')[1].Split('=')[1]
                try
                {
                    $VCS = Invoke-Expression "Get-$($Connection.DBType)DBVersionChangeScript -DatabaseName $DBName -TargetVersion $TargetVersion"
                    $VCS | Add-Member -MemberType NoteProperty -Name DBType -Value $Connection.DBType
                    $VCS | Add-Member -MemberType NoteProperty -Name Connection -Value $Connection.String
                    $VCS
                }
                catch{}
            }
            If ($DBScripts)
            {
                Write-Verbose "Upgradeble databases found: $($DBScripts.DBType -join ',')"
                foreach ($DBScript in $DBScripts)
                {
                    Write-Verbose "Disabling $($DBScript.DBType) service"
                    foreach ($Controller in $XDSite.Controllers)
                    {
                        Invoke-Expression "Set-$($DBScript.DBType)DBConnection -AdminAddress $($Controller.DnsName):80 -DBConnection $null -Force"
                    }
                }
                Write-Verbose "Executing scripts"
                $Script = @()
                switch -w ($DBScripts.Script)
                {
                    '--*'            {<#Skipping comments#>}
                    ''               {<#Skipping empty lines#>}
                    'if @@error*'    {<#Skipping error handling#>}
                    ':on error exit' {<#Skipping error handling#>}
                    go {
                        if ($Script)
                        {
                            $SqlCmd.CommandText = $Script -join "`n"
                            $SqlCmd.Connection.Open()
                            try
                            {
                                $ReturnValue = $SqlCmd.ExecuteNonQuery()
                                $SqlCmd.Connection.Close()
                            }
                            catch
                            {
                                $SqlCmd.Connection.Close()
                                Write-Error "DB upgrade failed: $_" -ErrorAction Stop
                            }
                            $Script = @()
                        }
                    }
                    Default {
                        $Script += $_
                    }
                }
                foreach ($DBScript in $DBScripts)
                {
                    Write-Verbose "Enabling $($DBScript.DBType) service"
                    foreach ($Controller in $XDSite.Controllers)
                    {
                        Invoke-Expression "Set-$($DBScript.DBType)DBConnection -AdminAddress $($Controller.DnsName):80 -DBConnection $($DBScript.Connection) -Force"
                    }
                }
            }
            else
            {
                Write-Verbose "No upgradeble databases found."
            }
        }

        #endregion functions
    }
    Process
    {
        $CtxPackages = Get-Package -Name Citrix* -ProviderName msi -ErrorAction Stop

        If ($Package = $CtxPackages | Where Name -eq 'Citrix Licensing')
        {
            $Params = @{
                PackageName = 'Citrix Licensing'
                ISOPath = Get-Item  "$ISOPath\Citrix_Virtual_Apps_and_Desktops_*.iso" -ErrorAction Stop
                SetupExe = 'x64\XenDesktop Setup\XenDesktopServerSetup.exe'
                ArgumentsList = "/Components LICENSESERVER","/quiet","/logpath $LogPath",'/noreboot'
                CurrentVersion = $Package.Version
            }
            Update-CitrixComponent @Params -Verbose
        }
        If ($Package = $CtxPackages | Where Name -eq 'Citrix StoreFront')
        {
            $Params = @{
                PackageName = 'Citrix Storefront'
                ISOPath = Get-Item  "$ISOPath\Citrix_Virtual_Apps_and_Desktops_*.iso" -ErrorAction Stop
                SetupExe = 'x64\StoreFront\CitrixStoreFront-x64.exe'
                ArgumentsList = '-silent'
                CurrentVersion = $Package.Version
            }
            Update-CitrixComponent @Params -Verbose
        }
        If ($Package = $CtxPackages | Where Name -eq 'Citrix Director')
        {
            $Params = @{
                PackageName = 'Citrix Director'
                ISOPath = Get-Item  "$ISOPath\Citrix_Virtual_Apps_and_Desktops_*.iso" -ErrorAction Stop
                SetupExe = 'x64\XenDesktop Setup\XenDesktopServerSetup.exe'
                ArgumentsList = "/Components DESKTOPDIRECTOR","/quiet","/logpath $LogPath",'/noreboot'
                CurrentVersion = $Package.Version
            }
            Update-CitrixComponent @Params -Verbose
        }
        If ($Package = $CtxPackages | Where Name -eq 'Citrix Broker Service')
        {
            $Params = @{
                PackageName = 'Citrix Broker Service'
                ISOPath = Get-Item  "$ISOPath\Citrix_Virtual_Apps_and_Desktops_*.iso" -ErrorAction Stop
                SetupExe = 'x64\XenDesktop Setup\XenDesktopServerSetup.exe'
                ArgumentsList = "/Components CONTROLLER","/quiet","/logpath $LogPath",'/noreboot'
                CurrentVersion = $Package.Version
            }
            if ($SkipVdaUpdateService)
            {
                $Params.Add('SkipVUS',$true)
            }
            Update-CitrixComponent @Params -Verbose
            Get-Service -DisplayName Citrix* | where StartType -eq Automatic | where Status -eq Stopped | Start-Service
            return
        }
        If ($Package = $CtxPackages | Where Name -like '*Provisioning Server*')
        {
            $Params = @{
                PackageName = '*Provisioning Server*'
                ISOPath = Get-Item "$ISOPath\Citrix_Provisioning_*.iso" -ErrorAction Stop
                SetupExe = 'Server\PVS_Server_x64.exe'
                CurrentVersion = $Package.Version
            }
            Update-CitrixPVS @Params -Verbose
            return
        }
        If ($Package = $CtxPackages | Where Name -eq 'Citrix Studio')
        {
            $Params = @{
                PackageName = 'Citrix Studio'
                ISOPath = Get-Item  "$ISOPath\Citrix_Virtual_Apps_and_Desktops_*.iso" -ErrorAction Stop
                SetupExe = 'x64\XenDesktop Setup\XenDesktopServerSetup.exe'
                ArgumentsList = "/Components DESKTOPSTUDIO","/quiet","/logpath $LogPath",'/noreboot'
                CurrentVersion = $Package.Version
            }
            Update-CitrixComponent @Params -Verbose
        }
        If ($Package = $CtxPackages | Where Name -like '*Provisioning Console*')
        {
            $Params = @{
                PackageName = '*Provisioning Console*'
                ISOPath = Get-Item "$ISOPath\Citrix_Provisioning_*.iso" -ErrorAction Stop
                SetupExe = 'Console\PVS_Console_x64.exe'
                CurrentVersion = $Package.Version
            }
            Update-CitrixPVS @Params -Verbose
        }
    }
}
