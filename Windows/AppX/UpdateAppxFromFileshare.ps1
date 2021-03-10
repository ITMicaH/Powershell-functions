# This script installs Appx Provisioned packages from a fileshare

#region constants

$Share = ''
$VerbosePreference = 'SilentlyContinue' #SilentlyContinue,Continue
$UserName = ''
$UserPW = ''

#endregion constants

#region functions

# Install update as provisioned package
function Update-AppxProvisionedPackage
{
    [CmdletBinding()]
    Param(
        # Folder containing the package update
        [Parameter(mandatory,ValueFromPipeline)]
        [IO.DirectoryInfo]
        $PackagePath
    )
    Process
    {
        $Files = Get-ChildItem $PackagePath.FullName
        $MainPackage = $Files.Where{$_.Name -like "$($PackagePath.Name)*.appx*"}
        $Dependencies = $Files.Where{$_.Name -ne $MainPackage.Name -and $_.extension -like '.appx*'}
        Write-Verbose "Updating $($PackagePath.Name) using $MainPackage"
        $Params = @{
            PackagePath = $MainPackage.FullName
        }
        If ($Dependencies)
        {
            $Params.Add('DependencyPackagePath',$Dependencies.FullName)
        }
        $null = Add-AppxProvisionedPackage @Params -Online -SkipLicense
    }
}

#endregion functions

#region Main

$CurrentApps = Get-AppxProvisionedPackage -Online
$Params = @{
    Name = 'Packages'
    PSProvider = 'Filesystem'
    Root = $Share
}
If ($UserName)
{
    $SecurePW = ConvertTo-SecureString $UserPW -AsPlainText -Force
    $Params.Add('Credential',[PSCredential]::new($UserName,$SecurePW))
}
$null = New-PSDrive @Params
Get-ChildItem Packages: | Update-AppxProvisionedPackage
$NewApps = Get-AppxProvisionedPackage -Online
foreach ($Appx in $CurrentApps)
{
    $NewApp = $NewApps | where DisplayName -eq $Appx.DisplayName
    [pscustomobject]@{
        AppxName = $Appx.DisplayName
        OldVersion = $Appx.Version
        NewVersion = $NewApp.Version
    }
}

#endregion Main
