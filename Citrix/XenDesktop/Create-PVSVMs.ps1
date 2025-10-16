<#
.Synopsis
   Maakt VM's aan in ESX en devices op PVS.
.DESCRIPTION
   Dit script wordt gebruikt om op de VDI ESX hosts VM's aan te maken aan de hand van een
   template. Eerst wordt d.m.v. een overzicht in variabele $Desktops bepaald hoeveel VM's 
   er voor een bepaalde functie nodig zijn. Daarna worden de VM's verdeeld over alle hosts
   die er zijn zodat op alle hosts ongeveer hetzelfde aantal machines landen.

   De verdeling maakt objecten met de volgende eigenschappen:

        VMHost              - Naam van de vSphere host waar de VM op moet landen.
        VMName              - Naam van de VM.
        VMTemplate          - De VM Template die wordt gekloond
        VMFolder            - De VM folder waar de VM binnen vCenter in wordt geplaatst
        PVSSite             - De PVS site waar het device moet worden aangemaakt
        PVSDeviceCollection - Naam van de PVS Device Collection
        PVSDeviceType       - Het type PVS Device (Maintenance/Test/Productie)
        OrganizationalUnit  - Distinguished Name van de OU waar het computer object in moet landen.

   Voorbeeld:

        VMHost              : fse-dc2-040.contoso.com
        VMName              : VDA23-040-005
        VMTemplate          : PVSTemplate-DC2
        VMFolder            : DC2 - RP3
        PVSSite             : ESX-DC2
        PVSDeviceCollection : Acceptatie
        PVSDeviceType       : Test
        OrganizationalUnit  : OU=Acceptatie,OU=VDI,OU=Workstations,OU=Resources,DC=CONTOSO,DC=COM

   De naamgeving van de VM's wordt bepaald aan de hand van de volgende variabelen:

        [Prefix]        - Staat in $Desktops gedefinieerd voor elke functie
        [DataCenter]    - afhankelijk van de vCenter Server
        [Resource Pool] - Geen letterlijke resource pool in vSphere maar een blok van 5 servers
        [Hostnummer]    - Wordt bepaald door naam van de host
        [Volgnummer]    - Wordt bepaald door het aantal VM's per functie

   Voorbeeld:

        VDA23-040-005

        VDA : Prefix geeft aan dat het een Acceptatie VM is
        2   : Datacenter 2
        3   : Resourcepool 3
        040 : Host nummer 40
        005 : VM volgnummer 5

        Hieruit kunnen we opmaken dat deze VM draait op server fse-dc2-040.

   Nadat de verdeling is gemaakt worden de objecten geëxporteerd naar een XML-bestand. Deze kan worden 
   gebruikt om de omgeving opnieuw op te bouwen mocht er iets mis gaan.

   Na de export worden alle objecten één voor één behandeld middels de volgende procedure:
   
   Eerst wordt de VM aangemaakt op basis van het juiste template. Hierna wordt het MAC adres van de 
   nieuwe VM gebruikt om een device in PVS aan te maken. Vervolgens laten we PVS een computer account 
   aanmaken in AD in de juiste OU.

   Dit proces herhaalt zich totdat alle VM's zijn aangemaakt.
.PARAMETER ExportOnly
   Switch parameter waarmee wordt aangegeven dat er alleen een XML bestand moet worden
   gegenereerd zonder daadwerkelijk VM's en PVS devices aan te maken.
.PARAMETER XMLFile
   Pad naar het XML bestand voor import en export.
.PARAMETER ImportFromXml
   Switch parameter om aan te geven of de VM eigenschappen moeten worden geïmporteerd uit
   het XML bestand. Zonder deze switch wordt de hele omgeving van scratch af aan opgebouwd.
.PARAMETER Filter
   Filter de te maken VM's uit de XML op basis van een scriptblock, zoals in een WHERE command.
.PARAMETER ShowDesktops
   Laat alleen 
.EXAMPLE
   Create-PVSVMs
   Maakt zelf een onderverdeling van de gewenste VM's en exporteert deze naar het default XML
   bestand pad. Hierna worden de VM's en de bijbehorende PVS devices gemaakt.
.EXAMPLE
   Create-PVSVMs -XMLFile O:\VMs.xml -ExportOnly
   Maakt zelf een onderverdeling van de gewenste VM's en exporteert deze naar O:\VMs.xml. Er
   worden geen VM's aangemaakt.
.EXAMPLE
   Create-PVSVMs -ImportFromXML -Filter {$_.VMHost -like 'fse-dc1-033.*' -and $_.VMName -like 'VDA*'}
   Importeerd de VM's uit het default XML bestand en maakt alleen de Acceptatie VM's aan op de
   host fse-dc1-033.contoso.com.
.NOTES
   Author : Michaja van der Zouwen
   Date   : 18-10-2016
#>

[CmdletBinding(DefaultParameterSetName='DefaultSet', 
                  SupportsShouldProcess=$true, 
                  PositionalBinding=$false,
                  ConfirmImpact='Medium')]
Param(
    
    # Path to XML file for import or export
    [Parameter(ParameterSetName='DefaultSet')]
    [Parameter(ParameterSetName='ImportXML')]
    [string]
    $XMLFile,
    
    # Only export the VM properties to XML but don't create
    [Parameter(ParameterSetName='DefaultSet')]
    [switch]
    $ExportOnly,

    # Import VM properties from XML
    [Parameter(ParameterSetName='ImportXML')]
    [ValidateScript({Test-Path $XMLFile})]
    [switch]
    $ImportFromXML,

    # Filter VM's using a WHERE type scriptblock
    [Parameter(ParameterSetName='ImportXML')]
    [scriptblock]
    $Filter,

    [Parameter(ParameterSetName='ShowDesktops')]
    [switch]
    $ShowDesktops
)

#region constants

$VIServer = 'vsa-vsp-001','vsa-vsp-002'
$VITemplate = 'PVSTemplate*'
$PVSServer = 'fsw-dc1-pvs-001'
$OUName = 'VDI ESX'
$PVSDiskName = 'WIN11-x64-ESX'
$PVSStoreName = 'StoreESX'
$PVSSitePrefix = 'ESX-DC'
$Desktops = @"
    Function,VMs,Prefix,Type,SubOU
    Acceptatie,150,VDA,Test,Acceptatie
    BuildTest,1,VDB,Test,Acceptatie
    Ontwikkel,1,VDO,Maintenance,Ontwikkel
    Externe Leveranciers,100,VDE,Productie,Leveranciers
    Gasten,50,VDG,Productie,Gasten
    Productie,2640,VD,Productie,Productie
    Pre-Test,4,VDT,Test,Acceptatie
"@ | ConvertFrom-CSV

#endregion constants

#region Prerequisites

If ($ShowDesktops)
{
    Write-Verbose 'Showing desktops defined in this script.'
    return $Desktops
}

If (!(Get-Module VMware.VimAutomation.Core))
{
    Write-Verbose "Initialising PowerCLI environment..."
    Import-Module VMware.VimAutomation.Core -ErrorAction Stop
}

Write-Verbose "Connecting to vCenter servers..."
If (!$Credential)
{
    $Credential = Get-Credential $env:USERDOMAIN\$env:USERNAME -ErrorAction Stop
}
$VISession = Connect-VIServer -Server $VIServer -Credential $Credential -WarningAction SilentlyContinue -ErrorAction Stop

Write-Verbose "Retreiving template(s) '$VITemplate'..."
$VMTemplates = Get-Template $VITemplate -ErrorAction Stop

Write-Verbose "Retreiving VM folders..."
$VMFolders = Get-Folder DC*RP*

Write-Verbose "Retreiving Organizational Unit '$OUName' and subOU's..."
$OU = Get-ADOrganizationalUnit -Filter "Name -eq '$OUName'" -ErrorAction Stop
$SubOUs = Get-ADOrganizationalUnit -SearchBase $OU -Filter "Name -ne '$OUName'" -Properties CanonicalName

#endregion Prerequisites

#region Functions

<#
.Synopsis
   Create host information objects
.DESCRIPTION
   Create host information objects and split by datacenter.
.EXAMPLE
   $VMs = Organize-VMHostsPerDC
#>
function Organize-VMHostsPerDC
{
    $VMHosts = Get-VMHost | sort Name
    $HostsInfo = foreach ($VMHost in $VMHosts)
    {
        If ($Matches)
        {
            $Matches.Clear()
        }
        $VMHost.Name -match 'fse-dc(\d)-(\d+)' | Out-Null
        If ($VMs = $VMHost | Get-VM)
        {
            $VMCount = @($VMs.Count)
        }
        else 
        {
            $VMCount = 0
        }
        [pscustomobject]@{
            Name = $VMHost.Name
            DataCenter = $Matches[1]
            ResourcePool = 0
            ShortName = "$($Matches[1])x-$($Matches[2])"
            PowerState = $VMHost.PowerState
            VMCount = $VMs.Count
        }
    }
    foreach ($DC in 1..2)
    {
        $DCVMhosts = $HostsInfo | ?{$_.DataCenter -eq $DC}
        foreach ($RP in 1..3)
        {
            $Start = ($RP - 1) * 5
            $RPVMHosts = $DCVMhosts[$Start..($Start+4)]
            $RPVMHosts | %{
                $_.ShortName = $_.ShortName.Replace('x',$RP)
                $_.ResourcePool = $RP
            }
        }
        [pscustomobject]@{
            DataCenter = $DC
            VMHosts = $DCVMhosts
        }
    }
}

<#
.Synopsis
   Create VM and add to PVS
.DESCRIPTION
   Creates a vSphere VM and a PVS Device. If the required Device Collection 
   does not exist it will be created in the appropriate Site.
#>
function New-PVSVM
{
    [CmdletBinding(
        SupportsShouldProcess=$True,
        ConfirmImpact='Medium'
    )]

    Param
    (
        # Host on which to create the VM
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true)]
        $VMHost,

        # VM Template object
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true)]
        [string]
        $VMTemplate,

        # Name of the VM
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true)]
        [string]
        $VMName,

        # VM folder object
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true)]
        [string]
        $VMFolder,

        [ValidateSet('EagerZeroedThick','Thick','Thick2GB','Thin','Thin2GB')]
        [string]
        $DiskStorageFormat = 'EagerZeroedThick',

        # Name of the PVS Server
        [string]
        $PVSServer,

        # Name of the PVS Site
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true)]
        [string]
        $PVSSite,

        # Name of the PVS Device Collection
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true)]
        [string]
        $PVSDeviceCollection,

        # Type of the PVS device
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true)]
        [ValidateSet('Productie','Test','Maintenance')]
        [string]
        $PVSDeviceType,

        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true)]
        $OrganizationalUnit
    )

    Begin
    {
        
        $PVSDeviceTypes = @{
            'Productie' = 0
            'Test' = 1
            'Maintenance' = 2
        }
        Add-PSSnapin Citrix.PVS.Snapin -ErrorAction Stop
        Set-PvsConnection -Server $PVSServer
        $PVSDevices = Get-PvsDevice
        $PVSDeviceCollections = Get-PvsCollection
    }
    Process
    {
        If ($VMHost -is [string])
        {
            $VMHost = Get-VMHost $VMHost
        }
        $Datastore = $VMHost | Get-Datastore
        If ($VM = Get-VM -Name $VMName -ErrorAction SilentlyContinue)
        {
            Write-Verbose "VM named '$VMName' already exists."
        }
        else
        {
            Write-Verbose "Creating new VM named '$VMName'..."
            if ($pscmdlet.ShouldProcess($VMHost,"New-VM $VMName")) {
                $VMproperties = @{
                    VMHost = $VMHost
                    Template = $VMTemplates | ?{$_.Name -eq $VMTemplate}
                    Name = $VMName
                    Location = $VMFolders | ?{$_.Name -eq $VMFolder}
                    Datastore = $Datastore
                    DiskStorageFormat = $DiskStorageFormat
                }
                # Using task to avoid errors
                $Task = New-VM @VMproperties -RunAsync
                while ($Task.State -eq 'Running')
                {
                    $Task = Get-Task -Id $Task.Id

                    switch ($Task.State)
                    {
                         Success { $VM = Get-VM -Name $VMName;break}
                         Error   { Write-Error $VM.ExtensionData.Info.Error.LocalizedMessage;break}
                         Running { Start-Sleep -Seconds 2}
                    }
                }
            }
        }
        If ($?)
        {
            Write-Verbose "Creating PVS Device for VM '$VMName'..."
            $MACAddress = $VM | Get-NetworkAdapter |
                ?{$_.NetworkName -like 'PG-Prov-*'} | 
                Select -ExpandProperty MacAddress

            #Using WHERE because erroraction is unable to SilentlyContinue
            If ($Collection = $PVSDeviceCollections | ?{$_.CollectionName -eq $PVSDeviceCollection})
            {
                Write-Verbose "Device Collection '$PVSDeviceCollection' is present on site '$PVSSite'."
            }
            else
            {
                Write-Verbose "Creating Device Collection '$PVSDeviceCollection' on site '$PVSSite'..."
                if ($pscmdlet.ShouldProcess($PVSSite,"New-PvsCollection '$PVSDeviceCollection'")) {
                    $Collection = New-PvsCollection -CollectionName $PVSDeviceCollection -SiteName $PVSSite
                    $PVSDeviceCollections = Get-PvsCollection
                }
            }
            If ($PVSDevice = $PVSDevices | ?{$_.DeviceName -eq $VMName})
            {
                Write-Verbose "PVS Device '$VMName' already exists."
            }
            else
            {
                Write-Verbose "Creating PVS Device '$VMName' on site '$PVSSite' in collection '$PVSDeviceCollection' with type '$PVSDeviceType'..."
                if ($pscmdlet.ShouldProcess($PVSDeviceCollection,"New-PvsDevice $VMName")) {
                    $DevProps = @{
                        DeviceName = $VMName
                        CollectionName = $PVSDeviceCollection
                        SiteName = $PVSSite
                        DeviceMac = $MACAddress.Replace(':','-')
                        Type = $PVSDeviceTypes[$PVSDeviceType]
                    }
                    $PVSDevice =  New-PvsDevice @DevProps
                }
            }
            If (($PVSDevice | Get-PvsDiskLocator | select -ExpandProperty Name) -eq $PVSDiskName)
            {
                Write-Verbose "vDisk already assigned to device."
            }
            else
            {
                Write-Verbose 'Assigning vDisk to the device...'
                if ($pscmdlet.ShouldProcess($VMName,'Add-PvsDiskLocatorToDevicer')) {
                    Add-PvsDiskLocatorToDevice -DeviceName $VMName -DiskLocatorName $PVSDiskName -SiteName $PVSSite -StoreName $PVSStoreName
                }
            }
            #$OrganizationalUnit = $OrganizationalUnit | Get-ADOrganizationalUnit -Properties CanonicalName
            $OU = $OrganizationalUnit.CanonicalName.Substring($OrganizationalUnit.CanonicalName.IndexOf('/')+1)
            If ($PVSDevice.DomainObjectSID)
            {
                Write-Verbose "Computer account for VM '$VMName' already exists in AD."
                Write-Verbose "Resetting AD Computer account password..."
                $PVSDevice | Reset-PvsDeviceForDomain -OrganizationUnit $OU
            }
            else
            {
                Write-Verbose 'Creating a computer account in AD...'
                if ($pscmdlet.ShouldProcess($OrganizationalUnit,"Add-PvsDeviceToDomain")) {
                    $PVSDevice | Add-PvsDeviceToDomain -OrganizationUnit $OU
                }
            }
            [pscustomobject]@{
                VMHost = $VMHost.Name
                VMName = $VMName
                MACAddress = $MACAddress
                PVSSite = $PVSSite
                PVSDeviceCollection = $PVSDeviceCollection
                PVSDeviceType = $PVSDeviceType
                OrganizationalUnit = $OrganizationalUnit
            }
        }
    }
    End
    {
        Write-Verbose 'Disconnecting session to PVS server...'
        Clear-PvsConnection
        Remove-PSSnapin Citrix.PVS.Snapin
    }
}

function Divide-VdiVMs
{
    [CmdletBinding()]
    Param(
        [ValidateNotNullOrEmpty()]
        $Desktops
    )

    Write-Verbose 'Organizing virtualization hosts per datacenter...'
    $DataCenters = Organize-VMHostsPerDC
    $Desktops | foreach {$_.VMs = [int]$_.VMs}
    foreach ($Desktop in ($Desktops))
    {
        Write-Verbose "Dividing VM's for '$($Desktop.Function)'..."
        $VMsPerDC = $Desktop.VMs / $DataCenters.Count
        If ($Desktop.VMs -gt 1)
        {
            foreach ($DataCenter in $DataCenters)
            {
                Write-Verbose "Processing DataCenter $($DataCenter.DataCenter)..."
                Write-Verbose 'Creating VM objects for hosts with the lowest VM count...'
                $HostsPerDC = $DataCenter.VMHosts.Count
                $LowestCount = ($DataCenter.VMHosts | sort VMCount)[0].Count
                $LowestHosts = $DataCenter.VMHosts | ?{$_.VMCount -eq $LowestCount}
                foreach ($VMHost in $LowestHost)
                {
                    $VMnr = '001'
                    $VMName = $Desktop.Prefix + $VMHost.ShortName +  "-$VMnr"
                    Write-Verbose "Creating object for VM '$VMName'..."
                    If ($Desktop.Function -eq 'Productie')
                    {
                        $PVSDeviceCollection = "{0} RP{1}" -f $Desktop.Function,$VMHost.ResourcePool
                    }
                    else
                    {
                        $PVSDeviceCollection = $Desktop.Function
                    }
                    [pscustomobject]@{
                        VMHost = $VMHost.Name
                        VMName = $VMName
                        VMTemplate = $VMTemplates | ?{$_.Name -like "*DC$($DataCenter.DataCenter)"}
                        VMFolder = $VMFolders | ?{$_.Name -eq "DC$($DataCenter.DataCenter) - RP$($VMHost.ResourcePool)"}
                        PVSSite = $PVSSitePrefix + $DataCenter.DataCenter
                        PVSDeviceCollection = $PVSDeviceCollection
                        PVSDeviceType = $Desktop.Type
                        OrganizationalUnit = $SubOUs | ?{$_.Name -eq $Desktop.SubOU}
                    }
                    $VMHost.VMCount++
                }

                Write-Verbose 'Creating VM objects for the remaining hosts...'
                $HostPreference = $DataCenter.VMHosts | sort VMCount
                # Round up VMs per host
                $VMsPerHost = [int][Math]::Ceiling(($VMsPerDC - $LowestHosts.Count) / $HostsPerDC)
                # How many servers will have one less VM?
                If ([int]$VMsPerDC -ge $HostsPerDC)
                {
                    $OverFlow = $VMsPerHost * $HostsPerDC - ($VMsPerDC - $LowestHosts.Count)
                }
                else
                {
                    $OverFlow = $HostsPerDC - $VMsPerDC - $LowestHosts.Count
                }
                # Which host will receive more or less
                $HostMore = $HostPreference[0..($HostsPerDC - $OverFlow - 1)]
                $HostLess = $HostPreference[($HostsPerDC - $OverFlow)..($HostsPerDC - 1)]

                foreach ($VMHost in $HostPreference)
                {
                    If ($VMHost -in $HostMore)
                    {
                        $NewVMCount = $VMsPerHost
                    }
                    else
                    {
                        $NewVMCount = $VMsPerHost - 1
                    }
                    If ($NewVMCount -ne 0)
                    {
                        foreach ($VMnr in 1..$NewVMCount)
                        {
                            $VMnr = "{0:D3}" -f $VMnr
                            $VMName = $Desktop.Prefix + $VMHost.ShortName +  "-$VMnr"
                            If ($VMName -in $DivideVMs.VMName)
                            {
                                $VMnr = "{0:D3}" -f ([int]$VMnr + 1)
                                $VMName = $Desktop.Prefix + $VMHost.ShortName +  "-$VMnr"
                            }
                            Write-Verbose "Creating object for VM '$VMName'..."
                            If ($Desktop.Function -eq 'Productie')
                            {
                                $PVSDeviceCollection = "{0} RP{1}" -f $Desktop.Function,$VMHost.ResourcePool
                            }
                            else
                            {
                                $PVSDeviceCollection = $Desktop.Function
                            }
                            [pscustomobject]@{
                                VMHost = $VMHost.Name
                                VMName = $VMName
                                VMTemplate = $VMTemplates | ?{$_.Name -like "*DC$($DataCenter.DataCenter)"}
                                VMFolder = $VMFolders | ?{$_.Name -eq "DC$($DataCenter.DataCenter) - RP$($VMHost.ResourcePool)"}
                                PVSSite = $PVSSitePrefix + $DataCenter.DataCenter
                                PVSDeviceCollection = $PVSDeviceCollection
                                PVSDeviceType = $Desktop.Type
                                OrganizationalUnit = $SubOUs | ?{$_.Name -eq $Desktop.SubOU}
                            }
                        }
                        $VMHost.VMCount += $NewVMCount
                    } #end if
                } #end foreach VMHost
                Write-Verbose "Finished processing DataCenter $($DataCenter.DataCenter)..."
            } #end foreach Datacenter
            Write-Verbose "VM's for '$($Desktop.Function)' have been divided."
        }
        else
        {
            $VMHost = $DataCenters[0].VMHosts | sort VMCount | select -First 1
            $VMnr = '001'
            $VMName = $Desktop.Prefix + $VMHost.ShortName +  "-$VMnr"
            Write-Verbose "Creating object for VM '$VMName'..."
            If ($Desktop.Function -eq 'Productie')
            {
                $PVSDeviceCollection = "{0} RP{1}" -f $Desktop.Function,$VMHost.ResourcePool
            }
            else
            {
                $PVSDeviceCollection = $Desktop.Function
            }
            [pscustomobject]@{
                VMHost = $VMHost.Name
                VMName = $VMName
                VMTemplate = $VMTemplates | ?{$_.Name -like "*DC$($DataCenters[0].DataCenter)"}
                VMFolder = $VMFolders | ?{$_.Name -eq "DC$($DataCenters[0].DataCenter) - RP$($VMHost.ResourcePool)"}
                PVSSite = $PVSSitePrefix + $DataCenters[0].DataCenter
                PVSDeviceCollection = $PVSDeviceCollection
                PVSDeviceType = $Desktop.Type
                OrganizationalUnit = $SubOUs | ?{$_.Name -eq $Desktop.SubOU}
            }
            $VMHost.VMCount++
        }
    }
}

#endregion Functions

#region Main

If ($ImportFromXml)
{
    $DivideVMs = Import-Clixml $XMLFile -Verbose:$VerbosePreference -ErrorAction Stop
}
else
{
    $DivideVMs = Divide-VdiVMs -Desktops $Desktops -Verbose:$VerbosePreference
    $XMLParent = $XMLFile.Replace($XMLFile.Split('\')[-1],'')
    If (Test-Path -LiteralPath $XMLParent)
    {
        Write-Verbose "Parent path for XML file exists."
    }
    else
    {
        Write-Verbose "Creating parent path for XML file..."
        New-Item -Path $XMLParent -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
    $DivideVMs | Export-Clixml -Path $XMLFile -Verbose:$VerbosePreference
    If ($ExportOnly)
    {
        Write-Verbose 'Finished'
        return
    }
}
If ($Filter)
{
    $VMsFiltered = $DivideVMs | where $Filter
    $VMsFiltered | New-PVSVM -PVSServer $PVSServer -Verbose:$VerbosePreference
}
else
{
    $DivideVMs | New-PVSVM -PVSServer $PVSServer -Verbose:$VerbosePreference
}
#endregion Main

#region Cleanup

Write-Verbose 'Disconnecting from vCenter servers...'
$VISession | Disconnect-VIServer -Confirm:$false
Remove-Module VMware.VimAutomation.Core
Write-Verbose 'Finished!'

#endregion Cleanup
