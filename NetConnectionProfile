<#
.Synopsis
   Gets the category for network connections
.DESCRIPTION
   Gets the category for network connections for the local computer.
.EXAMPLE
   Get-NetConnectionProfile
   This will get the category for all network connections:

   IsConnectedToInternet : False
   Category              : Public
   Description           : Unknown network
   Name                  : Unknown network
   IsConnected           : True

   IsConnectedToInternet : True
   Category              : Domain
   Description           : DOMAIN.LOCAL
   Name                  : DOMAIN
   IsConnected           : True
.EXAMPLE
   Get-NetConnectionProfile -NetworkCategory Public
   This will get the category for all public network connections:

   IsConnectedToInternet : False
   Category              : Public
   Description           : Unknown network
   Name                  : Unknown network
   IsConnected           : True
.NOTES
   Author: Michaja van der Zouwen
   Date  : 17-02-2016
.LINK
   https://itmicah.wordpress.com
.LINK
   Set-NetConnectionProfile
#>
function Get-NetConnectionProfile
{
    [CmdletBinding()]
    [OutputType([psobject])]
    Param
    (
        # Name of the network connection
        [Parameter(Mandatory=$false, 
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true, 
                   ValueFromRemainingArguments=$false, 
                   Position=0)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [string]
        $Name,

        # Network Category type
        [Parameter(Mandatory=$false, 
                   Position=1)]
        [ValidateSet('Public','Private','Domain')]
        $NetworkCategory
    )

    Begin
    {
        Write-Verbose 'Creating Network List Manager instance.'
        $NLMType = [Type]::GetTypeFromCLSID('DCB00C01-570F-4A9B-8D69-199FDBA5723B')
        $NetworkListManager = [Activator]::CreateInstance($NLMType)
        $Categories = @{
            0 = 'Public'
            1 = 'Private'
            2 = 'Domain'
        }
        Write-Verbose 'Retreiving network connections.'
        $Networks = $NetworkListManager.GetNetworks(1)
        If ($NetworkCategory)
        {
            Write-Verbose "Filtering results to match category '$NetworkCategory'."
            $Networks = $Networks | ?{$Categories[$_.GetCategory()] -eq $NetworkCategory}
        }
    }
    Process
    {
        If ($Name)
        {
            Write-Verbose "Filtering results to match name '$Name'."
            $Networks = $Networks | ?{$_.GetName() -eq $Name}
        }
        foreach ($Network in $Networks)
        {
            Write-Verbose "Creating output object for network $($Network.GetName())."
            New-Object -TypeName psobject -Property @{
                Category = $Categories[($Network.GetCategory())]
                Description = $Network.GetDescription()
                Name = $Network.GetName()
                IsConnected = $Network.IsConnected
                IsConnectedToInternet = $Network.IsConnectedToInternet
            }
        }
    }
    End
    {
    }
}

<#
.Synopsis
   Sets the category for network connections
.DESCRIPTION
   Sets the category for network connections for the local computer.
.EXAMPLE
   Set-NetConnectionProfile -Name 'LAN1' -NetworkCategory Private
   Sets the network category of the 'LAN1' connection to Private.
.EXAMPLE
   Get-NetConnectionProfile -NetworkCategory Public | Set-NetConnectionProfile -NetworkCategory Private
   Sets the network category for all Public connections to Private
.NOTES
   Author: Michaja van der Zouwen
   Date  : 17-02-2016
.LINK
   https://itmicah.wordpress.com
.LINK
   Get-NetConnectionProfile
#>
function Set-NetConnectionProfile
{
    [CmdletBinding(SupportsShouldProcess=$true, 
                  PositionalBinding=$false,
                  HelpUri = 'https://itmicah.wordpress.com/',
                  ConfirmImpact='Medium')]
    [Alias()]
    [OutputType([String])]
    Param
    (
        # Param1 help description
        [Parameter(Mandatory=$false, 
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true, 
                   ValueFromRemainingArguments=$false, 
                   Position=0)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [string]
        $Name,

        [Parameter(Mandatory=$true, 
                   Position=1)]
        [ValidateSet('Public','Private','Domain')]
        $NetworkCategory

    )

    Begin
    {
        Write-Verbose 'Creating Network List Manager instance.'
        $NLMType = [Type]::GetTypeFromCLSID('DCB00C01-570F-4A9B-8D69-199FDBA5723B')
        $NetworkListManager = [Activator]::CreateInstance($NLMType)
        $Categories = @{
            'Public' = 0x00
            'Private' = 0x01
            'Domain' = 0x02
        }
        $ReverseCategories = @{
            0 = 'Public'
            1 = 'Private'
            2 = 'Domain'
        }
        Write-Verbose 'Retreiving network connections.'
        $AllNetworks = $NetworkListManager.GetNetworks(1)
    }
    Process
    {
        If ($Name)
        {
            Write-Verbose "Filtering results to match name '$Name'."
            $Networks = $AllNetworks | ?{$_.GetName() -eq $Name}
        }
        else
        {
            $Networks = $AllNetworks
        }
        foreach ($Network in $Networks)
        {
            $Name = $Network.GetName()
            Write-Verbose "Processing network connection '$Name'."
            $CurrentCategory = $ReverseCategories[$Network.GetCategory()]
            Write-Verbose "Current category is '$CurrentCategory'."
            If ($NetworkCategory -eq $CurrentCategory)
            {
                Write-Warning "Skipping network connection '$Name': category is correct."
                continue
            }
            if ($pscmdlet.ShouldProcess($Name, "Set Network Category to $NetworkCategory"))
            { 
                Write-Verbose "Changing network category to '$NetworkCategory'."
                $Network.SetCategory($Categories[$NetworkCategory])
                Write-Verbose "Creating output object for network '$Name'."
                New-Object -TypeName psobject -Property @{
                    Category = $ReverseCategories[($Network.GetCategory())]
                    Description = $Network.GetDescription()
                    Name = $Network.GetName()
                    IsConnected = $Network.IsConnected
                    IsConnectedToInternet = $Network.IsConnectedToInternet
                }
            }
        }
    }
    End
    {
    }
}
