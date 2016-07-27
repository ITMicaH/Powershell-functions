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
   $UsedClients = $UserSessions[0..4].GetConnections($true).ClientName
   Retreives names of all the clients the user of the previous example has run his/hers first five sessions on 
   and shows verbose information..
.EXAMPLE
   $Machine = DesktopGroupMachine -Name VDI001
   PS C:\>$Machine.GetMachineHotfixLogs().GetHotfix()


   Displays all hotfixes installed on VM 'VDI001'.
.EXAMPLE
   $DesktopGroup = Get-CitrixODATAInformation -Server SVR-CDC-001 -Type DesktopGroup -Name 'My VDI'
   Retreives information on Desktop Group 'My VDI'.
.EXAMPLE
   $DesktopGroup.GetMachines($true)
   Retreives machines in the Desktop Group and displays verbose information.
.NOTES
   Author : Michaja van der Zouwen
   Date   : 7-7-2016
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
                   ParameterSetName = 'CustomURL',
                   Position=0)]
        [string]
        $Server,

        # Type of data to query
        [Parameter(Mandatory=$true,
                   ParameterSetName = 'Type',
                   HelpMessage = "Please enter the type of data you'd like to query",
                   Position=1)]
        [ValidateSet('User','Machine','DesktopGroup','Catalog')]
        [string]
        $Type,

        # Name to filter on
        [Parameter(Mandatory=$false,
                   ParameterSetName = 'Type',
                   Position=2)]
        [string]
        $Name,

        # Credential for retreiving director information
        $Credential,

        # Custom secundary URL
        [Parameter(Mandatory=$false,
                   ParameterSetName = 'CustomURL')]
        [string]
        $CustomURL,

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
        If ($Credential)
        {
            If ($Credential -match '(.+);(\w+)')
            {
                $Password = $Matches[2] | ConvertTo-SecureString
                $Credential = [System.Management.Automation.PSCredential]::new($Matches[1],$Password)
            }
            else
            {
                $Credential = Get-Credential $Credential -Message "Please provide credentials for oData connection"
            }
            $Params.Add('Credential',$Credential)
        }
        else
        {
            $Params.Add('UseDefaultCredentials',$True)
        }
    }
    Process
    {
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
        Write-Verbose "Using '$Prefix'."
        $BaseURL = "$Prefix`://$Server/Citrix/Monitor/OData/$Version/Data"
        Write-Verbose 'Retreiving all enumeration values...'
        $MethodURL = "$Prefix`://$Server/Citrix/Monitor/OData/$Version/Methods"
        $Params.Uri = "$MethodURL/GetAllMonitoringEnums()"
        $Enums = Invoke-RestMethod @Params -Verbose:$VerbosePreference
        If ($Name)
        {
            Switch ($Type)
            {
                'User'    {$Filter = "?`$filter=UserName eq '$Name'"}
                'Machine' {$Filter = "?`$filter=HostedMachineName eq '$Name'"}
                default   {$Filter = "?`$filter=Name eq '$Name'"}
            }
        }
        If ($CustomURL)
        {
            $ObjectType = ($CustomURL.Split('/')[-1]).TrimEnd('s')
            $Params['Uri'] = "$BaseURL/$CustomURL"
        }
        else
        {
            $ObjectType = $Type
            $Params['Uri'] = "$BaseURL/$Type`s()$Filter"
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
                                       {$MemberParams['Value'] = [datetime]$Properties.$($Member.Name).innertext;break}}
                        XmlElement {$MemberParams['Value'] = $Properties.$($Member.Name).innertext;break}
                    }
                    If ($MemberParams.Value -match '^\d{1,2}$')
                    {
                        $EnumType = $Enums.content.properties.typename -match $Member.Name
                        If (!$EnumType)
                        {
                            $EnumType = $Enums.content.properties.typename | ?{$Member.Name -match $_}
                        }
                        If ($EnumType)
                        {
                            Write-Verbose "`tEnumerating value for property '$($Member.Name)'..."
                            $Params.Uri = "$MethodURL/GetAllMonitoringEnums('$EnumType')/Values"
                            $EnumValues = Invoke-RestMethod @Params -Verbose:$False
                            $MemberParams.Value = $EnumValues[$MemberParams.Value].content.properties.Name
                        }
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
                            $Command = "Param([bool]`$Verbose);Get-CitrixODATAInformation -Server $Server -CustomURL `"$($Link.href)`" -Credential '$CredString' -UseTLS:`$$UseTLS -UseV1:`$$UseV1 -Verbose:`$Verbose"
                        }
                        else
                        {
                            $Command = "Param([bool]`$Verbose);Get-CitrixODATAInformation -Server $Server -CustomURL `"$($Link.href)`" -UseTLS:`$$UseTLS -UseV1:`$$UseV1 -Verbose:`$Verbose"
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
