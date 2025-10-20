using namespace Microsoft.Dism.Commands

# This script gets present Appx Provisioned packages, downloads updates for them and installs them.

#region constants

$TempPath = '' # Path to existing temporary location (E.G. C:\Temp)
$Language = '' # Language for Appx packages (E.G. en-US, nl-nl...)
$Proxy = '' # Proxyserver (E.G. http://proxy:80)
$ProxyUser = '' # Username for authenticated proxies
$ProxyUserPW = '' # Password for authenticated proxies
$Share = '' # Path to share (E.G. \\FileServer\AppxShare)
$VerbosePreference = 'SilentlyContinue' #SilentlyContinue,Continue
$UpdateShare = $True # False = download only

#endregion


#region functions

# Download package update from microsoft
function Download-AppxPackageUpdate
{
    [CmdletBinding()]
    Param(
        # Appx Package object
        [Parameter(mandatory,ValueFromPipeline)]
        [AppxPackageObject]
        $Package,

        # Path for download
        [Parameter(mandatory)]
        [string]
        $Path,

        # Language for Appx package
        [string]
        $Language = 'en-us',

        # Name of a proxy server
        [string]
        $Proxy,

        # Credentials for the proxy server
        [pscredential]
        $ProxyCredential
    )

    Process
    {
        $PackageFamilyName = $Package.PackageName -Replace '_.+_','_'
        Write-Verbose "Getting links to download the lastest $($Package.DisplayName) package."
        $Params = @{
            Method = 'POST'
            Uri = 'https://store.rg-adguard.net/api/GetFiles'
            Body = "type=PackageFamilyName&url=$PackageFamilyName&ring=Retail&lang=$Language"
            ContentType = 'application/x-www-form-urlencoded'
            UseBasicParsing = $true
        }
        If ($PSBoundParameters.Proxy)
        {
            $Params.Add('Proxy',$Proxy)
            if ($PSBoundParameters.ProxyCredential)
            {
                $Params.Add('ProxyCredential',$ProxyCredential)
            }
            else
            {
                $Params.Add('ProxyUseDefaultCredentials',$true)
            }
        }
        $WebResponse = Invoke-WebRequest @Params -ErrorAction Stop
        $WebResponse.Links.ForEach{
            $text = $_.outerHTML.Substring(($_.outerHTML.IndexOf('>')+1),($_.outerHTML.LastIndexOf('<') - $_.outerHTML.IndexOf('>')-1))
            Add-Member -InputObject $_ -MemberType NoteProperty -Name innerText -Value $text
            $null = $text -match '^[^\d]+'
            Add-Member -InputObject $_ -MemberType NoteProperty -Name Group -Value $text.Split('_')[0]
            Add-Member -InputObject $_ -MemberType NoteProperty -Name Version -Value ([version]$text.Split('_')[1])
        }
        $GroupedLinks = $WebResponse.Links | Group Group
        $DownloadLinks = foreach ($Group in $GroupedLinks)
        {
            Write-Verbose "Processing package $($Group.Name)"
            $Links = $Group.Group.where{$_ -like '*_x64_*' -or $_ -like '*_neutral_*'}
            $Appx = $Links.where{$_.innerText -match '\.appx|\.msix'} | sort innerText
            $Appx
        }
        
        If ($DownloadLinks)
        {
            $Params.Remove('ContentType')
            $Params.Remove('UseBasicParsing')
            $Params.Remove('Method')
            $Params.Remove('Body')
            $Params.Add('OutFile','')
            If ($Package.DisplayName -notin $DownloadLinks.Group)
            {
                Write-Verbose "Mainpackage is missing. Retrying."
                Download-AppxPackageUpdate @PSBoundParameters
                return
            }
            $GroupedLinks = $DownloadLinks | Group Group
            Write-Verbose "Downloading main package"
            $null = New-Item "$Path\$($Package.DisplayName)" -ItemType Directory -ErrorAction SilentlyContinue
            $MainGroup = $GroupedLinks.Where{$_.Name -eq $Package.DisplayName}
            $Appx = $MainGroup.Group | where{$_.innerText -match '\.appx|\.msix'}
            for ($i = -1; $i -ge -@($Appx).Count; $i--)
            {
                $Link = $Appx[$i]
                Write-Verbose "---$($Link.innerText)---"
                if ([version]$Package.Version -ge $Link.Version)
                {
                    Write-Verbose "Package $($Package.DisplayName) is already installed and up-to-date. Skipping upgrade."
                    return
                }
                $ProgressPreference = 0
                $Params.Uri = $Link.href
		$Params.OutFile = "$Path\$($Package.DisplayName)\$($Link.innerText)"
		Invoke-WebRequest @Params
                $Dependencies = Get-AppxDependencies -Path $Params.OutFile
                [version]$MinOSVersion = $Dependencies.TargetDeviceFamily | where Name -eq Windows.Desktop | Select -ExpandProperty MinVersion
                if ($MinOSVersion -lt [System.Environment]::OSVersion.Version)
                {
                    Write-Verbose "Applicable version found: $($Link.innerText)"
                    $AppxFile = Get-Item $Params.OutFile
                    $i = -$Appx.Count - 1
                }
                else
                {
                    Remove-Item $Params.OutFile
                }
            }
            If ($Dependencies.PackageDependency)
            {
                Write-Verbose "Downloading dependencies"
                foreach ($Dependency in $Dependencies.PackageDependency)
                {
                    Write-Verbose "Downloading $($Dependency.Name)"
                    $Appx = $GroupedLinks.where{$_.Name -eq $Dependency.Name}
                    $Link = $Appx.group[-1]
                    if ($Link.Version -ge [version]$Dependency.MinVersion)
                    {
                        $Params.Uri = $Link.href
			$Params.OutFile = "$Path\$($Package.DisplayName)\$($Link.innerText)"
			Invoke-WebRequest @Params
                    }
                }
            }
            Write-Verbose "Done with downloading $($Package.DisplayName)."
            Get-Item "$Path\$($Package.DisplayName)"
        }
        else
        {
            Write-Verbose "No download links available for $($Package.DisplayName)."
        }
    }
}

#Get Appx dependencies
function Get-AppxDependencies
{
    Param(
        [string]
        $Path
    )
    Add-Type -assembly "system.io.compression.filesystem"
    $Archive = [System.IO.Compression.ZipFile]::OpenRead($Path)
    If ($Path -like '*bundle')
    {
        $Package = $Archive.Entries.where{$_.FullName -notlike '*/*' -and $_.Name -like '*x64*x'}
        $Stream = $Package.Open()
        $Appx = [System.IO.Compression.ZipArchive]::new($Stream)
        $Manifest = $Appx.Entries | Where Name -eq AppxManifest.xml
        $txtStream = $Manifest.Open()
        $Reader = [System.IO.StreamReader]::new($txtStream)
        [xml]$XML = $Reader.ReadToEnd()
        $Dependencies = $XML.Package.Dependencies
        $txtStream.Close()
    }
    else
    {
        $Manifest = $Archive.Entries | Where Name -eq AppxManifest.xml
        $Stream = $Manifest.Open()
        $Reader = [System.IO.StreamReader]::new($Stream)
        [xml]$XML = $Reader.ReadToEnd()
        $Dependencies = $XML.Package.Dependencies
    }
    $Reader.Close()
    $Stream.Close()
    $Archive.Dispose()
    return $Dependencies
}

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
        $MainPackage = $Files.Where{$_.BaseName -like "$($PackagePath.Name)*" -and $_.Extension -like '*x*'}
        $Dependencies = $Files.Where{$_.Name -ne $MainPackage.Name -and $_.extension -like '.appx*'}
        Write-Verbose "Updating $($PackagePath.Name) using $MainPackage"
        $Params = @{
            PackagePath = $MainPackage.FullName
        }
        If ($Dependencies)
        {
            $Params.Add('DependencyPackagePath',$Dependencies.FullName)
        }
        try
        {
            $null = Add-AppxProvisionedPackage @Params -Online -SkipLicense -ErrorAction Stop
        }
        catch
        {
            Write-Warning "Package $($MainPackage.Basename) generated the following error: $_"
        }
    }
}

# Update the packages on the share
function Update-PackageShare
{
    [CmdletBinding()]
    Param(
        # Path to the package share
        [Parameter(mandatory)]
        [string]
        $Path,

        # Folder containing the package update
        [Parameter(mandatory,ValueFromPipeline)]
        [IO.DirectoryInfo]
        $PackagePath,

        # Credential for the file actions
        [pscredential]
        $Credential
    )

    Begin
    {
        $Params = @{
            Name = 'Packages'
            PSProvider = 'FileSystem'
            Root = $Path
        }
        If ($PSBoundParameters.Credential)
        {
            $Params.Add('Credential',$Credential)
        }
        $null = New-PSDrive @Params -ErrorAction Stop
    }
    Process
    {
        If (Test-Path Packages:\$($PackagePath.Name))
        {
            Remove-Item -Path Packages:\$($PackagePath.Name) -Recurse
        }
        Copy-Item -Path $PackagePath.FullName -Destination Packages:\ -Recurse
    }
    End
    {
        Remove-PSDrive -Name Packages
    }
}

#endregion functions

#region Main

$Params = @{
    Path = $TempPath
    Language = $Language
}
If ($Proxy)
{
    $Params.Add('Proxy',$Proxy)
    If ($ProxyUser)
    {
        $SecurePW = ConvertTo-SecureString $ProxyUserPW -AsPlainText -Force
        $Params.Add('ProxyCredential',[PSCredential]::new($ProxyUser,$SecurePW))
    }
}
$CurrentApps = Get-AppxProvisionedPackage -Online
$Updates = $CurrentApps | Download-AppxPackageUpdate @Params
if ($Updates)
{
    $Updates | Update-AppxProvisionedPackage
    $NewApps = Get-AppxProvisionedPackage -Online
    $Output = foreach ($Appx in $CurrentApps)
    {
        If ($NewApp = $NewApps | where DisplayName -eq $Appx.DisplayName)
        {
            [pscustomobject]@{
                AppxName = $Appx.DisplayName
                OldVersion = $Appx.Version
                NewVersion = $NewApp.Version
            }
        }
        else
        {
            Write-Error "Package $($Appx.DisplayName) failed to install"
            [pscustomobject]@{
                AppxName = $Appx.DisplayName
                OldVersion = $Appx.Version
                NewVersion = 'FAILED!! Please reïnstall package'
            }
        }
    }
    $Output | ft -AutoSize
    if ($UpdateShare)
    {
        if ($Params.ProxyCredential)
        {
            $Updates | Update-PackageShare -Path $Share -Credential $Params.ProxyCredential
        }
        else
        {
            $Updates | Update-PackageShare -Path $Share
        }
    }
    $Updates | Remove-Item -Recurse
}

#endregion Main
