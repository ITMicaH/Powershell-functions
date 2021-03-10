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
            Add-Member -InputObject $_ -MemberType NoteProperty -Name Group -Value $Matches.Values.TrimEnd('.','_')
        }
        $GroupedLinks = $WebResponse.Links | Group Group
        $DownloadLinks = foreach ($Group in $GroupedLinks)
        {
            Write-Verbose "Processing package $($Group.Name)"
            $Links = $Group.Group.where{$_ -like '*_x64_*' -or $_ -like '*_neutral_*'}
            $Appx = $Links.where{$_.innerText -match '\.appx'} | sort innerText | Select -Last 1
            $BlockMap = $Links.where{$_.innerText -match '\.BlockMap'} | sort innerText | Select -Last 1
            If ($Appx.innerText -match $Package.PackageName)
            {
                Write-Verbose "Skipping $($Group.Name)"
            }
            else
            {
                $Appx
                $BlockMap
            }
        }
        If ($DownloadLinks)
        {
            $MainPackage = $DownloadLinks.Where{$_.innerText -like "$($Package.DisplayName)*.appx*"}
            If (!$MainPackage)
            {
                Write-Verbose "Mainpackage is missing. Retrying."
                Download-AppxPackageUpdate @PSBoundParameters
                return
            }
            elseif ($MainPackage.innerText -match $Package.PackageName)
            {
                Write-Verbose "Package $($Package.DisplayName) is already installed and up-to-date. Skipping download."
                return
            }
            If (!(Test-Path "$Path\$($Package.DisplayName)"))
            {
                $null = New-Item -Path $Path -Name $Package.DisplayName -ItemType Directory
            }
            Write-Verbose "Downloading package and dependencies:"
            foreach ($Link in $DownloadLinks)
            {
                Write-Verbose "---$($Link.innerText)---"
                $ProgressPreference = 0
                Invoke-WebRequest -Uri $Link.href -OutFile "$Path\$($Package.DisplayName)\$($Link.innerText)" -ProxyUseDefaultCredentials -Proxy http://proxy02:8080
                $ProgressPreference = 2
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
    foreach ($Appx in $CurrentApps)
    {
        $NewApp = $NewApps | where DisplayName -eq $Appx.DisplayName
        [pscustomobject]@{
            AppxName = $Appx.DisplayName
            OldVersion = $Appx.Version
            NewVersion = $NewApp.Version
        }
    }
    if ($Params.ProxyCredential)
    {
        $Updates | Update-PackageShare -Path $Share -Credential $Params.ProxyCredential
    }
    else
    {
        $Updates | Update-PackageShare -Path $Share
    }
    $Updates | Remove-Item -Recurse
}

#endregion Main
