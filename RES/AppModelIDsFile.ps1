<#
.Synopsis
   Create CustomAppModelIDs.xml file for RES/Ivanti Worspace Control
.DESCRIPTION
   Create a CustomAppModelIDs.xml file for RES/Ivanti Worspace Control to force a specific 
   AppUserModelID to a Workspace Managed application. This solves issues where multiple
   applications using the same commandline (but may have different parameters, like IE links) 
   are not all displayed on the Start Menu (e.g. https://community.ivanti.com/docs/DOC-64513).

   The file can be created by entering application IDs manually or by using a Building Block. 
   When running the script on a computer where the Workspace Management console is installed
   the building block can be generated automatically and the resulting xml file can be imported
   in the root of the Custom Resources folder.
.EXAMPLE
   New-CustomAppUserModelIDsFile -AutoCreate -OutputPath C:\Temp
   Creates the CustomAppUserModelIDs.xml file in folder C:\Temp for all iexplore.exe applications
.EXAMPLE
   New-CustomAppUserModelIDsFile -BuildingBlock .\RESWMBB.xml -Executable mstsc.exe
   Uses a Building Block to create the CustomAppUserModelIDs.xml file in the users Temp folder 
   for all mstsc.exe applications
.EXAMPLE
   New-CustomAppUserModelIDsFile -AppID 16,25,165,1487 -AutoImport
   Creates the CustomAppUserModelIDs.xml file for all apps with the provided IDs and automatically
   imports the file into the root of the RES/Ivanti Custom Resources
.LINK
   https://itmicah.wordpress.com
   https://community.ivanti.com/docs/DOC-63186
   https://community.ivanti.com/docs/DOC-64513
#>
function New-CustomAppUserModelIDsFile
{
    [CmdletBinding(DefaultParameterSetName='ID', 
                   SupportsShouldProcess=$true, 
                   PositionalBinding=$false,
                   HelpUri = 'https://itmicah.wordpress.com',
                   ConfirmImpact='High')]
    [OutputType([System.IO.FileInfo])]
    Param
    (
        # Path to a Building Block file
        [Parameter(Mandatory=$true,
                   ParameterSetName='BuildingBlock')]
        [System.IO.FileInfo]
        $BuildingBlock,

        # Application ID list
        [Parameter(Mandatory=$true,
                   ParameterSetName='ID')]
        [int[]]
        $AppID,

        # Automatically create application building block
        [Parameter(ParameterSetName='Auto')]
        [switch]
        $AutoCreate,

        # Name of the executable to create AppModelIDs for
        [Parameter(ParameterSetName='BuildingBlock')]
        [Parameter(ParameterSetName='Auto')]
        [SupportsWildcards()]
        [string]
        $Executable = 'iexplore.exe',

        # Path to the folder for the output file
        [System.IO.DirectoryInfo]
        $OutputPath = "$Env:TEMP",

        # Automatically import the file into Custom Resources rootfolder
        [switch]
        $AutoImport
    )

    If (($PSBoundParameters['AutoCreate'] -or $PSBoundParameters['AutoImport']) -and !$env:RESPFDIR)
    {
        Write-Error -Message 'Workspace console application is not installed.' -Category NotInstalled
        return
    }
    If ($PSBoundParameters['AutoCreate'])
    {
        Write-Verbose "Creating application Building Block [$Env:TEMP\Apps.xml]"
        Start-Process -FilePath $env:RESPFDIR\pwrtech.exe -ArgumentList /export,$Env:TEMP\Apps.xml,/type=APPLICATION -Wait -ErrorAction Stop

        Write-Verbose "Retreiving application IDs from BuidingBlock"
        [xml]$BB = Get-Content $Env:TEMP\Apps.xml
        $IDs = $BB.respowerfuse.buildingblock.application.Where({
            $_.configuration.commandline -like "*\$Executable"
        }) | sort {[int]$_.appid} | select -ExpandProperty appid -Unique
    }
    ElseIf ($PSBoundParameters['BuildingBlock'])
    {
        Write-Verbose "Retreiving application IDs from BuidingBlock [$BuildingBlock]"
        [xml]$BB = Get-Content $BuildingBlock -ErrorAction Stop
        If ($BB.respowerfuse.buildingblock.application)
        {
            $IDs = $BB.respowerfuse.buildingblock.application.Where({
                $_.configuration.commandline -like "*\$Executable"
            }) | sort {[int]$_.appid} | select -ExpandProperty appid -Unique
        }
        else
        {
            Write-Error "Building Block [$BuildingBlock] does not contain applications or is invalid." -Category InvalidData
            return
        }
    }
    else
    {
        $IDs = $AppID
    }

    If (!$IDs)
    {
        Write-Error "No applications found for executable [$Executable]" -Category ObjectNotFound
        return
    }
    # Set the File Name
    $filePath = "$OutputPath\CustomAppUserModelIDs.xml"
 
    Write-Verbose "Creating the xml document [$filePath]"
    $Settings = New-Object System.XMl.XmlWriterSettings
    $Settings.OmitXmlDeclaration = $true
    $Settings.Indent = $true
    $XmlWriter = [System.XMl.XmlTextWriter]::Create($filePath,$Settings)
    $xmlWriter.WriteStartDocument()
    $xmlWriter.WriteStartElement("applist")

    Write-Verbose "Adding $($IDs.count) Application IDs to the xml document"
    foreach ($ID in $IDs)
    {
        Write-Verbose "`tAdding ID [$ID]"
        $xmlWriter.WriteStartElement("app")
        $xmlWriter.WriteElementString("id",$ID)
        $xmlWriter.WriteElementString("appusermodelid","WorkspaceManager.$ID")
        $xmlWriter.WriteEndElement()
    }

    Write-Verbose "Finalizing xml document"
    $xmlWriter.WriteEndElement()
    $xmlWriter.WriteEndDocument()
    $xmlWriter.Flush()
    $xmlWriter.Close()

    If ($PSBoundParameters['AutoImport'])
    {
        if ($pscmdlet.ShouldProcess($filePath, "Import into Custom Resources"))
        {
            Start-Process -FilePath $env:RESPFDIR\pwrtech.exe -ArgumentList /addresource,$filePath -Wait -ErrorAction Stop
        }
    }
    else
    {
        Write-Verbose 'Generating output'
        Get-Item $filePath
    }
}
