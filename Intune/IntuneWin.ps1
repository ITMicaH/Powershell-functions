Param(
    [string]
    $PackagePath
)
#region Helper Functions

function Get-Folder
{
    Param(
        [string]
        $initialDirectory = $Path
    )

    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null

    $Browser = New-Object System.Windows.Forms.FolderBrowserDialog
    $Browser.Description = "Select a folder to place the package in"
    $Browser.rootfolder = "MyComputer"
    $Browser.SelectedPath = $initialDirectory

    if($Browser.ShowDialog() -eq "OK")
    {
        return $Browser.SelectedPath
    }
}

#endregion Helper Functions

#region functions

function New-IntuneWinPackage
{
    [CmdletBinding()]
    Param(
        [Parameter(mandatory)]
        [string]
        $Path
    )

    #region constants

    $IntuneWin = "C:\BeheerTools\IntuneWinAppUtil.exe"

    #endregion constants

    $Items = Get-ChildItem $Path
    If ($Installer = $Items.Where{$_.Name -eq 'Install.cmd'})
    {
        Write-Verbose "Installer: $($Installer.Name)"
    }
    elseif ($Installer = $Items.Where{$_.Extension -in '.msi','.exe','.cmd','.ps1'})
    {
        If ($Installer.Count -gt 1)
        {
            "Found $($Installer.Count) possible installers:"
            $i = 1
            $Installer.ForEach{"$i - $($_.Name)";$i++}
            [int]$Choice = Read-Host "Please enter the number of the main installer"
            If ($Choice -in 1..$i)
            {
                $Installer = $Installer[$Choice-1]
                Write-Verbose "Installer: $($Installer.Name)"
            }
            else
            {
                Write-Error 'You choose... poorly' -Category LimitsExceeded
                Read-Host 'Press Enter to continue...'
                exit 1
            }
        }
    }
    else
    {
        Write-Error 'No installer was found' -Category ObjectNotFound
        Read-Host 'Press Enter to continue...'
        exit 1
    }
    If (Test-Path "$Path\..\..\Packages")
    {
        $OutputPath = "$Path\..\..\Packages"
    }
    else
    {
        $OutputPath = Get-Folder
    }
    If ($OutputPath)
    {
        Start-Process -FilePath $IntuneWin -ArgumentList "-c `"$Path`" -s `"$($Installer.Name)`" -o `"$OutputPath`"" -NoNewWindow -Wait
        If ($Path.Split('\')[-1] -match '^\d[\.|\d]+$')
        {
            $Version = $Path.Split('\')[-1]
            Write-Verbose "Version : $Version"
        }
        if ($Path.Split('\')[-2] -eq 'Software' -and $Path.Split('\')[-4] -eq 'Packages')
        {
            $Software = $Path.Split('\')[-3].Replace(' ','')
            Write-Verbose "Software : $Software"
        }
        If ($Software -and $Version)
        {
            $PackageName = "$Software`_$Version"
        }
        else
        {
            $PackageName = $Path.Split('\')[-1]
        }
        Write-Verbose "Package name : $PackageName"
        If (Test-Path "$OutputPath\$PackageName.intunewin")
        {
            Write-Warning 'Output file already exists'
            Remove-Item "$OutputPath\$PackageName.intunewin" -Confirm
        }
        Write-Information "Renaming file to $PackageName.intunewin"
        Rename-Item -Path "$OutputPath\$($Installer.basename).intunewin" -NewName "$PackageName.intunewin"
        Start-Process -FilePath explorer.exe -ArgumentList $OutputPath
    }
}

#endregion functions

#region Main

New-IntuneWinPackage -Path $PackagePath -Verbose

#endregion Main
