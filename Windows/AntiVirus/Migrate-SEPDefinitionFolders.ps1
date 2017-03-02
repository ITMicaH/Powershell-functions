#Requires -Version 3

<#
.Synopsis
   Copies the Definitions folder from the C drive to an alternate location.
.DESCRIPTION
   This command copies the SEP Definitions folder from the C drive to an 
   alternate location. 
.PARAMETER CatalogName
   Name of the machine catalog. Wildcards (*) are permitted.
.PARAMETER DeliveryController
   Name of a XenDesktop Delivery Controller.
.PARAMETER VMname
   Name(s) of VM(s) to process.
.PARAMETER Destination
   Path to the destination folder.
.PARAMETER ThrottleLimit
   Number of concurrent VM's to process.
.PARAMETER Credential
   Credentials with appropriate XenDesktop privileges.
.PARAMETER SkipOffline
   Skip VM's that are offline.
.EXAMPLE
   Migrate-SEPDefinitionFolders -VMName XenVM01,XenVM02,XenVM03,XenVM04 -ThrottleLimit 2

   Copies the SEP Definitions folder to default destination folder
   D:\SEP on VM's XenVM01 through XenVM04 two at a time. VM's must be online.
.EXAMPLE
   Migrate-SEPDefinitionFolders -CatalogName XD7_TEST -DeliveryController XD7-CDC-001 -Credential DOMAIN\XDAdmin

   Retreives the VM's in catalog XD7_TEST from Delivery Controller XD7-CDC-001
   as user DOMAIN\XDAdmin. The online VM's will be processed first, after which
   the offline VM's will be powered on and processed with a maximum of 10 at a time.
.NOTES
   Author        : Michaja van der Zouwen
   Version       : 1.0
   Creation Date : 20-05-2015
.LINK
   http://itmicah.wordpress.com/
#>
[CmdletBinding(DefaultParameterSetName='Catalog')]
Param
(
    [Parameter(Mandatory=$true,
    HelpMessage = 'Name of the machine catalog. Wildcards (*) are permitted.',
    ParameterSetName = 'Catalog')]
    [string]
    $CatalogName,

    [Parameter(Mandatory=$true,
    HelpMessage = 'Name of a XenDesktop Delivery Controller',
    ParameterSetName = 'Catalog')]
    [string]
    $DeliveryController,

    [Parameter(Mandatory=$true,
    HelpMessage = "Name(s) of VM's to process",
    ParameterSetName = 'VMName')]
    [string[]]
    $VMname,

    # Path to the destination folder
    [Parameter(Mandatory=$false)]
    [string]
    $Destination = 'D:\SEP',

    # Number of concurrent VM's to process
    [Parameter(Mandatory=$false)]
    [int]
    $ThrottleLimit = 10,

    # Credentials with XenDesktop privileges
    [Parameter(Mandatory=$false)]
    $Credential,

    # Skip VM's that are offline
    [Parameter(Mandatory=$false)]
    [switch]
    $SkipOffline
)

#region Functions

function Copy-SEPFolders
{
    <#
    .Synopsis
       Copies the SEP definition folder to destination.
    .DESCRIPTION
       Copies the SEP definition folder to destination folder.
    .EXAMPLE
       Copy-SEPFolders -VMName XenVM01,XenVM02,XenVM03,XenVM04 -ThrottleLimit 2

       Copies all SEP definition files to default destination folder
       D:\SEP on VM's XenVM01 through XenVM04 two at a time.
    #>
    [CmdletBinding()]
    Param
    (
        # Name of the VM to migrate folders on
        [Parameter(Mandatory=$true,
                   ValueFromPipeline=$false,
                   Position=0)]
        [string[]]
        $VMname,

        # Path to the destination folder.
        [Parameter(Mandatory=$false,
                   ValueFromPipeline=$false,
                   Position=1)]
        $Destination,

        # Number of concurrent VMs to process
        [Parameter(ValueFromPipeline=$false,
                   Position=2)]
        [int]
        $ThrottleLimit = 10
    )

    # Scriptblock to execute on VM
    $ScriptBlock = {

        [CmdletBinding()]
        Param ($Destination)

        $VerbosePreference=$Using:VerbosePreference
        $Source = 'C:\ProgramData\Symantec\Symantec Endpoint Protection\CurrentVersion\Data\Definitions'

        If (Test-Path $Destination)
        {
            Write-Verbose "Directory $Destination already exists."
            $CheckContents = compare (dir $Source -Recurse) (dir "$Destination\Definitions" -Recurse)
            If ($CheckContents)
            {
                Write-Verbose "Directory $Destination needs additional files"
                $Migrated = $false
            }
            else
            {
                Write-Verbose "Directory $Destination contains all necessary files."
                $Migrated = $true
            }
        }
        else
        {
            Write-Verbose "Creating directory $destination."
            MD $Destination | Out-Null
        }
        If (!$Migrated) 
        {
            If (Test-Path "$Destination\Definitions")
            {
                Write-Verbose "Removing old folder '$Destination\Definitions'."
                rd "$Destination\Definitions" -Recurse
            }
            # Copy all files and folders to destination
            Try {
                Write-Verbose "Starting file copy."
                Copy-Item $Source $Destination -Recurse -ea 1
            }
            catch {
                Write-Verbose "File copy failed."
                $Migrated = $false
                $Exception = $_.Exception.Message
            }
            If (!$Exception) {
                Write-Verbose "File copy was successful."
                $Migrated = $true
            }
        }
        #Display result
        New-Object -TypeName psobject -Property @{
            'Migrated' = $Migrated
            'Error' = $Exception
        }
    } # end of scriptblock

    Write-Verbose "Run script on all VM's in $ThrottleLimit concurrent sessions"
    Invoke-Command -ComputerName $VMname -ScriptBlock $ScriptBlock -ArgumentList $Destination -ThrottleLimit $ThrottleLimit
}

function Start-BrokerMachine
{
    <#
    .Synopsis
       Starts the VM's in groups and runs the copy function
    .DESCRIPTION
       This command starts the XenDesktop VM's in groups, runs the Copy-SEPFolders 
       function and then moves on to the next group, until all VM's have been 
       processed.
    .EXAMPLE
       Start-BrokerMachine -VMName XenVM01,XenVM02,XenVM03 -DeliveryController XD-CDC-01 -ThrottleLimit 2 -Credential DOMAIN\XDAdminUser

       This command starts the VM's XenVM01 & XenVM02 using delivery controller
       XD-CDC-01 as user DOMAIN\XDAdminUser. Then it waits until they're up and
       runs the Copy-SEPFolders function on these VM's. After this it will do
       the same for XenVM03.
    #>

    [CmdletBinding()]
    Param
    (
        # Name of the VM to migrate folders on
        [Parameter(Mandatory=$true,
                   ValueFromPipeline=$false,
                   Position=0)]
        [string[]]
        $VMname,

        # Path to the destination folder.
        [Parameter(Mandatory=$false,
                   ValueFromPipeline=$false,
                   Position=1)]
        $Destination = 'D:\SEP',
        
        # Name of the delivery controller.
        [Parameter(Mandatory=$true,
                   Position=2)]
        [string]
        $DeliveryController,

        # Number of concurrent VMs to process
        [Parameter(ValueFromPipeline=$false,
                   Position=3)]
        [int]
        $ThrottleLimit = 10,

        # Credentials to connect to Delivery Controller
        [Parameter(Mandatory=$false)]
        $Credential
    )

    Write-Verbose "Starting up VM's in groups of $ThrottleLimit..."
    for ($i = 0; $i -lt $VMName.Count; $i+=$ThrottleLimit)
    {  
        If (($i + $ThrottleLimit) -lt $VMName.count)
        {
            $VMgroup = $VMName[$i..($i + $ThrottleLimit - 1)]
        }
        else
        {
            $VMgroup = $VMName[$i..($VMName.count - 1)]
        }
        Write-Verbose "New group contains:"
        $VMgroup | %{Write-Verbose "   * $_"}
        
        $ScriptBlock = {
            
            [CmdletBinding()]    
            Param ($VMgroup)
            
            $VerbosePreference=$Using:VerbosePreference
            
            Write-Verbose "Loading Citrix SnapIns."
            $snapins = Get-PSSnapin | ?{$_.Name -like "Citrix*"}
            if (!$snapins) {
                Get-PSSnapin -Registered "Citrix*" | Add-PSSnapin
            }
            $VMgroup | %{
                Write-Verbose "Starting VM $_."
                New-BrokerHostingPowerAction -MachineName $_ -Action TurnOn -ea 1 | Out-Null
            }
        } # End ScriptBlock
        
        Write-Verbose "Connecting to Delivery Controller $DeliveryController."
        $CmdArgs = @{
            'ComputerName' = $DeliveryController
            'ScriptBlock' = $ScriptBlock
            'ArgumentList' = (,$VMgroup)
        }
        If ($Credential) {$CmdArgs.Add('Credential',$Credential)}
        Invoke-Command @CmdArgs -ea 1

        Write-Verbose "Waiting for VM's to come online..."
        Do
        {
            sleep -s 5
            $AllUp = $VMgroup | % {
                If (Test-WSMan -ComputerName $_ -ea 0)
                {
                    $true
                }
                else
                {
                    $false
                }
            }
        }
        Until ($AllUp -notcontains $false)
        Write-Verbose "All VM's in this group are online."

        Write-Verbose "Running Definition Files copy script on current group..."
        Copy-SepFolders -VMname $VMgroup -Destination $Destination -ThrottleLimit $ThrottleLimit
        Write-Verbose "Finished running Definition Files copy script on current group."
    } # end For loop
}

#endregion Functions

#region Main script

If ($Credential) {
    Write-Verbose "Getting credentials."
    $Credential = Get-Credential $Credential
}

#Get VMs from CDC Catalogs
If ($DeliveryController) {

    Write-Verbose "Retreiving VM objects from Delivery Controller $DeliveryController from catalog $CatalogName..."
    $ScriptBlock = {
        param($CatalogName)
        $VerbosePreference=$Using:VerbosePreference

        Write-Verbose "Loading Citrix snapins."
        $snapins = Get-PSSnapin | ?{$_.Name -like "Citrix*"}
        if (!$snapins) {
            Get-PSSnapin -Registered "Citrix*" | Add-PSSnapin
        }

        Write-Verbose "Retreiving VM objects from catalog $CatalogName."
        $VMs = Get-BrokerMachine -CatalogName $CatalogName -MaxRecordCount 2147483647
        Write-Verbose "Retreived $($VMs.count) VM's."
        $VMs
    }
    $GetVMs = @{
        'ComputerName' = $DeliveryController
        'ScriptBlock' = $ScriptBlock
        'ArgumentList' = $CatalogName
    }
    If ($Credential) {$GetVMs.Add('Credential',$Credential)}
    $objVMs = Invoke-Command @GetVMs -ea 1
    Write-Verbose "All VM objects received."

    Write-Verbose "Processing online VM's..."
    $VMName = $objVMs | ?{$_.PowerState -eq 'On'} | select -ExpandProperty DNSName
    Copy-SepFolders -VMname $VMName -Destination $Destination -ThrottleLimit $ThrottleLimit
    Write-Verbose "Finished processing online VM's."

    If (!$SkipOffline)
    {
        Write-Verbose "Processing offline VM's..."
        $VMName = $objVMs | ?{$_.PowerState -ne 'On'} | select -ExpandProperty DNSName
        $StartVMs = @{
            'VMName' = $VMName
            'Destination' = $Destination
            'DeliveryController' = $DeliveryController
            'ThrottleLimit' = $ThrottleLimit
        }
        If ($Credential) {$StartVMs.Add('Credential',$Credential)}
        Start-BrokerMachine @StartVMs
        Write-Verbose "Finished processing offline VM's."
    }
}
else
{
    # Copy folders
    Copy-SEPFolders -VMname $VMName -Destination $Destination -ThrottleLimit $ThrottleLimit
}
Write-Verbose "All done!"

#endregion Main script
