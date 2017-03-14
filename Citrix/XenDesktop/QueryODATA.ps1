<#
.Synopsis
   Get information on a Citrix environment using the oDATA API.
.DESCRIPTION
   Uses the oDATA API to query information on a Citrix XenApp/XenDesktop environment.
   Output objects are supplied with ScriptMethods which allow you to navigate directly to
   related information objects (entities).
.PARAMETER Server
   The name of the Citrix server (Director) you want to use.
.PARAMETER Type
   The type of data you want to query.
.PARAMETER Name
   The name you want to filter the data on. E.G. If the type is User the name will be the username.
.PARAMETER Credential
   The credentials for retreiving director information.
.PARAMETER CustomURL
   Customized secundary URL section. The secundary URL section is the part of the URL that follows Data\.
   This parameter is mainly used for the ScriptMethods on the output object.
.PARAMETER Filter
   This parameter will allow you to filter the results based on one or more properties of an output object.
   You can also apply a filter to a method (see examples).
.PARAMETER UseTLS
   Switch parameter if you want to use TLS (https).
.PARAMETER UseV1
   If you run this function on a XenDesktop 7(.1) environment use this switch parameter.
.EXAMPLE
   $User = Get-CitrixODATAInformation -Server SVR-CDC-001 -Type User -Name TestUser01 -Credential CONTOSO\CTXAdmin
   Retreives information on user 'TestUser01' using credentials 'CONTOSO\CTXAdmin'. The user will be
   prompted for a password. The server 'SVR-CDC-001' is used to query the oDATA API.
.EXAMPLE
   $UserSessions = $User.GetSessions()
   Retreives all sessions initiated by the user of the previous example.
.EXAMPLE
   $UserSessions = $User.GetSessions("ConnectionState -ne 'Terminated'")
   Retreives sessions initiated by the user of the previous example where the ConnectionState property
   does not have a value of 'Terminated'.
.EXAMPLE
   Get-CitrixODATAInformation -Server SVR-CDC-001 -Type Session -Filter "StartDate -gt $((Get-Date).AddDays(-1))"
   Retreives all sessions started in the last day.
.EXAMPLE
   $UsedClients = $UserSessions[0..4].GetConnections().ClientName
   Retreives names of all the clients the user of the previous example has run his/hers first five sessions on.
.EXAMPLE
   $Machine = Get-CitrixODATAInformation -Server SVR-CDC-001 -Type Machine -Name VDI001
   PS C:\>$Machine.GetMachineHotfixLogs().GetHotfix()


   Displays all hotfixes installed on VM 'VDI001'.
.EXAMPLE
   $DesktopGroup = Get-CitrixODATAInformation -Server SVR-CDC-001 -Type DesktopGroup -Name 'My VDI'
   Retreives information on Desktop Group 'My VDI'.
.EXAMPLE
   $DesktopGroup.GetMachines()
   Retreives machines in the Desktop Group.
.NOTES
   Author : Michaja van der Zouwen
   Date   : 7-7-2016
   
   ChangeLog:
   ==========
   14-03-2017 : Added Filter parameter and removed Date (dynamic) parameter.
#>
function Get-CitrixODATAInformation
{
    [CmdletBinding(DefaultParameterSetName='Type')]
    Param
    (
        # Name of Citrix server (Director)
        [Parameter(Mandatory=$true,
                   ParameterSetName = 'Type',
                   HelpMessage = 'Please enter the name of a Citrix (Director) server',
                   Position=0)]
        [Parameter(Mandatory=$true,
                   ParameterSetName = 'CustomURL')]
        [string]
        $Server,

        # Type of data to query
        [Parameter(Mandatory=$true,
                   ParameterSetName = 'Type',
                   HelpMessage = "Please enter the type of data to query")]
        [ValidateSet('User','Machine','DesktopGroup','Catalog','Session')]
        [string]
        $Type,

        # Name to filter on
        [Parameter(Mandatory=$false,
                   ValueFromPipeline=$true,
                   ParameterSetName = 'Type')]
        [string]
        $Name,

        # Credential for retreiving director information
        $Credential,

        # Custom secundary URL
        [Parameter(Mandatory=$false,
                   ParameterSetName = 'CustomURL')]
        [string]
        $CustomURL,

        # Filter on specific properties
        [Parameter(Mandatory=$false)]
        [AllowNull()]
        [string]
        $Filter,

        # Use https instead of http
        [switch]
        $UseTLS,

        # Use version 1 (XD 7/7.1)
        [switch]
        $UseV1
    )

    Begin
    {
        $Params = @{
            Uri = ''
        }
        If ($PSBoundParameters.ContainsKey('Credential'))
        {
            If ($Credential -match '(?<UserName>.+);(?<Password>\w+)')
            {
                $Password = $Matches.Password | ConvertTo-SecureString
                $Credential = [System.Management.Automation.PSCredential]::new($Matches.UserName,$Password)
            }
            elseif ($Credential -isnot [PSCredential])
            {
                $Credential = Get-Credential $Credential -Message "Please provide credentials for oData connection"
                If (!$Credential)
                {
                    return
                }
            }
            $Params['Credential'] = $Credential
        }
        else
        {
            $Params['UseDefaultCredentials'] = $True
        }
        switch ($UseTLS)
        {
            $true  {$Prefix = 'https'}
            $false {$Prefix = 'http'}
        }
        switch ($UseV1)
        {
            $true  {$Version = 'v1'}
            $False {$Version = 'v2'}
        }
        Write-Verbose "Using '$Prefix' and '$Version'."
        $BaseURL = "$Prefix`://$Server/Citrix/Monitor/OData/$Version/Data"
        Write-Verbose 'Retreiving all enumeration values...'
        $MethodURL = "$Prefix`://$Server/Citrix/Monitor/OData/$Version/Methods"
        $Params.Uri = "$MethodURL/GetAllMonitoringEnums()"
        $Enums = Invoke-RestMethod @Params -Verbose:$VerbosePreference
        
        function Enumerate ($Type,$Value)
        {
            $EnumParams = @{}
            If ($Params.Credential)
            {
                $EnumParams['Credential'] = $Credential
            }
            else
            {
                $EnumParams['UseDefaultCredentials'] = $True
            }
            $EnumType = $Enums.content.properties.typename -match $Type
            If (!$EnumType)
            {
                $EnumType = $Enums.content.properties.typename | where {$Type -match $_}
            }
            If ($EnumType)
            {
                Write-Verbose "`tEnumerating value for property '$($Type)'..."
                $EnumParams['Uri'] = "$MethodURL/GetAllMonitoringEnums('$EnumType')/Values"
                $EnumValues = Invoke-RestMethod @EnumParams -Verbose:$False
                If ($Value -match '^\d{1,2}$')
                {
                    $EnumValues[$Value].content.properties.Name
                }
                else
                {
                    $EnumValue = $EnumValues | where {$_.content.properties.Name -eq $Value}
                    If ($EnumValue)
                    {
                        $EnumValue.content.properties.Value.InnerText
                    }
                    else
                    {
                        Write-Verbose "Unable to find value '$Value' for type '$Type'."
                        $Value
                    }
                }
            }
            else
            {
                Write-Verbose "Unable to find enumeration type '$Type'."
                $Value
            }
        }
    }
    Process
    {
        If ($PSBoundParameters.ContainsKey('Credential'))
        {
            If (!$Credential)
            {
                return "Cancelled by user."
            }
        }
        If ($PSBoundParameters.ContainsKey('Name'))
        {
            Switch ($Type)
            {
                'User'    {$URLFilter = "?`$filter=UserName eq '$Name'"}
                'Machine' {$URLFilter = "?`$filter=HostedMachineName eq '$Name'"}
                'Session'{throw "Parameter 'Name' can't be used for type 'Sessions'."}
                default   {$URLFilter = "?`$filter=Name eq '$Name'"}
            }
        }
        If ($PSBoundParameters.ContainsKey('CustomURL'))
        {
            Write-Verbose "Using Custom URL '$CustomURL'."
            $ObjectType = ($CustomURL.Split('/')[-1]).TrimEnd('s')
            $Params['Uri'] = "$BaseURL/$CustomURL"
        }
        else
        {
            $ObjectType = $Type
            $Params['Uri'] = "$BaseURL/$Type`s()$URLFilter"
        }
        If ($PSBoundParameters.ContainsKey('Filter') -and $Filter -ne '')
        {
            Write-Verbose "Processing filter '$Filter'."
            If ($Filter -match '\(|\.')
            {
                Write-Warning "Filter might contain non-string elements."
            }
            $Filter = $Filter.Replace('-','')
            foreach ($Item in ($Filter -split 'and|or').Trim())
            {
                $EnumerationType = $Item.Split(' ')[0]
                $ValueToEnumerate = $Item.Split(' ')[2..($Item.Split(' ').Count-1)] -join ' '
                try{
                    $Date = Get-Date ([datetime]$ValueToEnumerate.Trim("'")).ToUniversalTime() -Format s
                    Write-Verbose 'Filter contains a date.'
                    $Enumerated = "DateTime'$Date'"
                }
                catch{
                    $Enumerated = Enumerate $EnumerationType $ValueToEnumerate.Trim("'")
                }
                If ($Enumerated -ne $ValueToEnumerate.Trim("'"))
                {
                    $Filter = $Filter -replace $ValueToEnumerate,$Enumerated
                }
            }
            
            If ($Params.Uri -match 'filter=')
            {
                $Params['Uri'] = $Params['Uri'] + " and $Filter"
            }
            else
            {
                $Params['Uri'] = $Params['Uri'] + "?`$filter=$Filter"
            }
        }
        Write-Verbose "Querying oDATA information..."
        try
        {
            $Info = Invoke-RestMethod @Params -Verbose:$VerbosePreference
        }
        catch
		{
            $Message = $_.Exception.Message
            If ($_.ErrorDetails.Message -match 'access denied')
            {
                $Message = 'Access Denied. Please check your Citrix administrator Role and Scope.'
            }
            If ($_.Exception.Message -match '\(401\) Unauthorized')
            {
                $Message = 'Unable to retreive data. Credentials may be invalid.'
            }
            throw $Message
        }
        Foreach ($Objects in $Info)
        {
            If ($Objects.entry)
            {
                $Objects = $Objects.entry
                Write-Verbose "Object has $($Objects.count) entries."
            }
            Foreach ($Object in $Objects)
            {
                Write-Verbose "Creating new $ObjectType object.."
                $Output = [pscustomobject]@{}

                #region Properties
                Write-Verbose "Adding properties to $ObjectType object..."
                $Properties = $Object.content.properties
                $Members = $Properties | Get-Member -MemberType Property
                Foreach ($Member in $Members)
                {
                    $MemberParams = @{
                        InputObject = $Output
                        MemberType = 'NoteProperty'
                        Name = $Member.Name
                        Value = $Properties.$($Member.Name)
                    }
                    switch -Regex ($Member.Definition)
                    {
                        Date       {If ($Properties.$($Member.Name).innertext)
                                       {$MemberParams['Value'] = (Get-Date $Properties.$($Member.Name).innertext).ToLocalTime();break}}
                        XmlElement {$MemberParams['Value'] = $Properties.$($Member.Name).innertext;break}
                    }
                    If ($MemberParams.Value -match '^\d{1,2}$')
                    {
                        Write-Verbose "`tEnumerating value for property '$($Member.Name)'..."
                        $MemberParams.Value = Enumerate $Member.Name $MemberParams.Value
                    }
                    Write-Verbose "`tAdding property '$($Member.Name)'..."
                    Add-Member @MemberParams -Verbose:$VerbosePreference
                }
                Write-Verbose "Finished adding properties."
                #endregion Properties

                #region Methods
                Write-Verbose "Adding methods to $ObjectType object..."
                Foreach ($Link in $Object.link)
                {
                    If ($Link.rel -ne 'edit')
                    {
                        If ($Credential)
                        {
                            $CredString = "$($Credential.UserName);$($Credential.Password | ConvertFrom-SecureString)"
                            $Command = "Param([string]`$Filter);Get-CitrixODATAInformation -Server $Server -CustomURL `"$($Link.href)`" -Filter `$Filter -Credential '$CredString' -UseTLS:`$$UseTLS -UseV1:`$$UseV1"
                        }
                        else
                        {
                            $Command = "Param([string]`$Filter);Get-CitrixODATAInformation -Server $Server -CustomURL `"$($Link.href)`" -Filter `$Filter -UseTLS:`$$UseTLS -UseV1:`$$UseV1"
                        }
                        $ScriptBlock = [Scriptblock]::Create($Command)

                        Write-Verbose "`tAdding method 'Get$($Link.Title)'..."
                        $Output | Add-Member -MemberType ScriptMethod -Name "Get$($Link.Title)" -Value $ScriptBlock -Verbose:$VerbosePreference
                    }
                }
                Write-Verbose 'Finished adding methods.'
                #endregion Methods

                Write-Verbose "Returning $ObjectType object."
                $Output
            }
        }
    }
    End
    {
        Write-Verbose 'Finished oDATA query.'
    }
}
