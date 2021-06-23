#region helper functions

# Check 64-bit environment requirement
function CheckEnvironment
{
    if (![environment]::Is64BitProcess)
    {
        switch -w ([environment]::CommandLine)
        {
            *\powershell_ise.exe {$Program = 'PowerShell_ISE'}
            *\powershell.exe     {$Program = 'PowerShell'}
        }
        $title    = "64-bit $($Program.Replace('_',' ')) required"
        $question = "Do you want to start a 64-bit $($Program.Replace('_',' '))?"
        $choices  = '&Yes', '&No'

        $decision = $Host.UI.PromptForChoice($title, $question, $choices, 1)
        if ($decision -eq 0) {
            Start-Process -FilePath "C:\Windows\sysnative\WindowsPowerShell\v1.0\$Program.exe" -Verb RunAs
        }
        return $false
    }
    else
    {
        return $true
    }
}

# Invoke pktmon.exe with arguments
function Invoke-PktMon
{
    Param(
        [Parameter(mandatory,ValueFromRemainingArguments)]
        [string[]]
        $Arguments
    )
    If (CheckEnvironment)
    {
        Invoke-Expression -Command "pktmon $($Arguments -join ' ')"
    }
}

#endregion helper functions

#region functions

<#
.Synopsis
    Get active packet filters
.DESCRIPTION
    Get a list of active packet filters
.EXAMPLE
    Get-PktFilter
    Shows a list of all active packet filters
.EXAMPLE
    Get-PktFilter -Name VLAN*
    Shows package filters with names that start with VLAN
#>
function Get-PktFilter
{
    [CmdletBinding(DefaultParameterSetName='Index')]
    [OutputType([PktFilter])]
    Param
    (
        # Index(es) of the filter(s)
        [Parameter(ParameterSetName='Index')]
        [int[]]
        $Index,

        # Name of the filter
        [Parameter(ParameterSetName='Name')]
        [SupportsWildcards()]
        [string]
        $Name
    )

    $List = Invoke-PktMon -Arguments 'filter','list'
    $Headers = @{
        Index = $List[1].IndexOf('#')
        Name = $List[1].IndexOf('Name')
        MACAddress = $List[1].IndexOf('MAC Address')
        VLAN = $List[1].IndexOf('Vlan ID')
        EtherType = $List[1].IndexOf('EtherType')
        Protocol = $List[1].IndexOf('Protocol')
        IPAddress = $List[1].IndexOf('IP Address')
        Port = $List[1].IndexOf('Port')
        Encapsulation = $List[1].IndexOf('Encapsulation')
        VXLANPort = $List[1].IndexOf('VXLAN Port')
    }.GetEnumerator().where{$_.Value -ge 0} | sort value
    $NameIndex = $Headers.where{$_.Key -eq 'Name'}.Value
    
    $Output = [Collections.Arraylist]::new()
    $Filter = @{}
    for ($i = 3; $i -lt $List.Count; $i++)
    { 
        $Line = $List[$i]
        $NewName = $Line.Substring($NameIndex,1)
        if ($NewName -ne ' ')
        {
            If ($Filter.Count)
            {
                $null = $Output.Add([PktFilter]$Filter)
            }
            $Filter = @{}
        }
        for ($y = 0; $y -lt $Headers.Count; $y++)
        { 
            $HeaderName = $Headers[$y].Key
            If ($y -eq $Headers.Count - 1)
            {
                $Value = $Line.Substring($Headers[$y].Value)
            }
            else
            {
                $Value = $Line.Substring($Headers[$y].Value).replace($Line.Substring($Headers[$y+1].Value),'').Trim()
            }
            if ($Value -and $Value -notmatch '^\s+$')
            {
                If ($Filter.$HeaderName)
                {
                    $Filter.$HeaderName = $Filter.$HeaderName,$Value
                }
                else
                {
                    $Filter.Add($HeaderName,$Value)
                }
            }
        }
    }
    if ($Filter.Count)
    {
        $null = $Output.Add([PktFilter]$Filter)
    }

    If ($PSBoundParameters.Index)
    {
        $Output | where {$_.Index -in $Index}
    }
    elseIf ($PSBoundParameters.Name)
    {
        $Output | where {$_.Name -Like $Name}
    }
    else
    {
        $Output
    }
}

<#
.Synopsis
   Add a packet filter
.DESCRIPTION
   Add a packet filter to control which packets are reported.
.EXAMPLE
   New-PktFilter -Name MyPing -IPAddress 10.10.10.10 -Protocol ICMP
   Creates a ping filter
.EXAMPLE
   New-PktFilter -Name MySmbSyn -IPAddress 10.10.10.10 -Protocol TCP -TCPFilter SYN -Port 445
   Creates a TCP SYN filter for SMB traffic
.EXAMPLE
   New-PktFilter -Name MySubnet -IPAddress 10.10.10.0/24
   Creates a subnet filter
#>
function New-PktFilter
{
    [CmdletBinding()]
    [OutputType([PktFilter])]
    Param
    (
        # Name of the packet filter.
        [string]
        $Name,

        # Match source or destination MAC address.
        [string[]]
        $MACAddress,

        # Match by VLAN Id (VID) in the 802.1Q header.
        [int]
        $VLAN,

        #  Match by data link (layer 2) protocol. Can be IPv4, IPv6, ARP, or a protocol number.
        [ValidateScript({
            If ($_ -match '^(IPv[4,6]{1}|ARP|\d+)$')
            {
                return $true
            }
            else
            {
                Write-Error -Message 'EtherType parameter can be IPv4, IPv6, ARP, or a protocol number'
            }
        })]
        [string]
        $EtherType,

        # Match by transport (layer 4) protocol. Can be TCP, UDP, ICMP, ICMPv6, or a protocol number.
        [ValidateScript({
            If ($_ -match '^(TCP|UDP|ICMP(v6)?|\d+)( \(\w+\))?$')
            {
                return $true
            }
            else
            {
                Write-Error -Message 'Protocol parameter can be TCP, UDP, ICMP, ICMPv6, or a protocol number'
            }
        })]
        [string]
        $Protocol,

        [ValidateSet('FIN','SYN','RST','PSH','ACK','URG','ECE','CWR')]
        [string]
        $TCPFilter,

        # Match source or destination IP address
        [ValidateScript({
            $Check = foreach ($IP in $_)
            {
                $IP -match '^(?:[0-9]{1,3}\.){3}[0-9]{1,3}(/\d{1,2})?$'
            }
            If (($Check | select -Unique) -eq $true)
            {
                return $true
            }
            else
            {
                Write-Error -Message 'One or more IP adresses are incorrect.'
            }
        })]
        [string[]]
        $IPAddress,

        # Match source or destination port number.
        [int[]]
        $Port,

        # Match RCP heartbeat messages over UDP port 3343.
        [switch]
        $HeartBeat,

        # Apply filtering parameters to both inner and outer encapsulation headers.
        [switch]
        $Encapsulation,

        # Custom VXLAN port is optional, and defaults to 4789.
        [int]
        $VXLANPort
    )
    $Arguments = [Collections.Arraylist]::new(@('filter','add'))
    switch ($PSBoundParameters.Keys)
    {
        Name          {$null = $Arguments.Insert(2,$Name)}
        MACAddress    {$null = $Arguments.Add("-m $($MACAddress -join ' ')")}
        VLAN          {$null = $Arguments.Add("-v $VLAN")}
        EtherType     {$null = $Arguments.Add("-d $EtherType")}
        Protocol      {
                        If ($Protocol -match 'TCP \((\w+)\)'){
                            $Protocol = 'TCP'
                            $TCPFilter = $Matches[1]
                        }
                       $null = $Arguments.Add("-t $Protocol $TCPFilter")}
        IPAddress     {$null = $Arguments.Add("-i $($IPAddress -join ' ')")}
        Port          {$null = $Arguments.Add("-p $($Port -join ' ')")}
        Encapsulation {$null = $Arguments.Add("-e $VXLANPort")}
        HeartBeat     {$null = $Arguments.Add("-b")}
    }
    $Result = Invoke-PktMon -Arguments $Arguments
    if ($Result -eq 'Filter added.')
    {
        Get-PktFilter | select -Last 1
    }
    else
    {
        Write-Error "Unable to create packet filter: $($Result[0].Substring(9))"
    }
}

<#
.Synopsis
   Remove packet filter(s)
.DESCRIPTION
   Remove packet filter(s)
.EXAMPLE
   Remove-PktFilter
   Removes all packet filters
.EXAMPLE
   Remove-PktFilter -Name VLAN*
   Removes packet filters with a name that starts with VLAN
.EXAMPLE
   Get-PktFilter -Index 1,2 | Remove-PktFilter -PassThru
   Removes filters with Index 1 and 2 and displays the remaining active filters
#>
function Remove-PktFilter
{
    [CmdletBinding(DefaultParameterSetName='Object', 
                  SupportsShouldProcess,
                  ConfirmImpact='High')]
    Param
    (
        # Index of the filter to remove
        [Parameter(ParameterSetName='Index')]
        [int]
        $Index,

        # Name of the filter to remove
        [Parameter(ParameterSetName='Name')]
        [SupportsWildcards()]
        [string]
        $Name,

        # Object of the filter to remove
        [Parameter(ValueFromPipeline,ParameterSetName='Object')]
        [PktFilter]
        $InputObject,

        # Return resulting active filter list
        [switch]
        $PassThru
    )

    Begin
    {
        $Filters = Get-PktFilter
        $ToRemove = @()
    }
    Process
    {
        If (!$PSBoundParameters.Name -and 
            !$PSBoundParameters.Index -and 
            !$PSBoundParameters.InputObject)
        {
            if ($pscmdlet.ShouldProcess("All", "Remove packet filter"))
            {
                $null = Invoke-PktMon filter remove
                return
            }
        }
        if ($PSBoundParameters.Index)
        {
            $InputObject = Get-PktFilter -Index $Index
        }
        if ($PSBoundParameters.Name)
        {
            $InputObject = Get-PktFilter -Name $Name
        }
        if ($pscmdlet.ShouldProcess("$InputObject", "Remove packet filter"))
        {
            $null = Invoke-PktMon filter remove
            $ToRemove += $InputObject.Index
        }
    }
    End
    {
        if ($ToRemove.Count)
        {
            $Restore = $Filters | where Index -NotIn $ToRemove
            foreach ($Filter in $Restore)
            {
                $UsedProps = $Filter.GetType().GetProperties().Name.where{$Filter.$_ -and $_ -ne 'Index'}
                $Params = @{}
                $UsedProps.foreach{
                    $Params.Add($_,$Filter.$_)
                }
                $null = New-PktFilter @Params
            }
        }
        if ($PSBoundParameters.PassThru)
        {
            Get-PktFilter
        }
    }
}

<#
.Synopsis
   Start package capture
.DESCRIPTION
   Start package capture and event collection
.EXAMPLE
   Start-PktCapture -Capture
   Starts packet capture
.EXAMPLE
   Start-PktCapture -CountersOnly
   Starts packet capture counters only
.EXAMPLE
   Start-PktCapture -EventProvider Microsoft-Windows-TCPIP,Microsoft-Windows-NDIS
   Starts event logging
.EXAMPLE
   Start-PktCapture -Capture -EventProvider Microsoft-Windows-TCPIP -EventMask 0xFF -EventLogLevel 4
   Starts packet capture with event logging
#>
function Start-PktCapture
{
    [CmdletBinding()]
    Param
    (
        # Enable packet capture and packet counters.
        [switch]
        $Capture,

        # Select components to capture packets on. Can be ALL, NICs, or a comma seperated list of component Ids. Default is ALL.
        [ValidateScript({
            If ($_ -match '^(ALL|NICs|[\d,]+)$')
            {
                return $true
            }
            else
            {
                Write-Error -Message 'Components parameter can be ALL, NICs, or a comma seperated list of component Ids'
            }
        })]
        [string]
        $Components,

        # Select which packets to capture. Default is ALL.
        [ValidateSet('All','Flow','Drop')]
        [string]
        $Type,

        # Number of bytes to log from each packet. To always log the entire packet set this to 0. Default is 128 bytes.
        [int]
        $PacketSize,

        # Hexadecimal bitmask that controls information logged during packet capture. Default is 0x012.
        [ValidateSet('0x001','0x002','0x004','0x008','0x010')]
        [string]
        $Flags,

        # Collect packet counters only. No packet logging.
        [switch]
        $CountersOnly,

        # Event provider name(s) or GUID(s).
        [string[]]
        $EventProvider,

        # Hexadecimal bitmask that controls which events are logged for the corresponding provider. Default is 0xFFFFFFFF.
        [string]
        $EventMask,

        # Logging level for the corresponding provider. Default is 4 (info level).
        [int]
        $EventLogLevel,

        # Log file name. Default is PktMon.etl.
        [string]
        $FileName,

        # Maximum log file size in megabytes. Default is 512 MB.
        [int]
        $FileSize,

        # Logging mode. Default is circular.
        [ValidateSet('Circular','Multi-file','Memory','Real-time')]
        [string]
        $Mode,

        # Generate no Output
        [switch]
        $Quiet
    )

    $Arguments = [Collections.Arraylist]::new(@('start'))
    switch ($PSBoundParameters.Keys)
    {
        Capture       {$null = $Arguments.Add("-c")}
        Components    {$null = $Arguments.Add("--comp $($Components.Replace(',',' '))")}
        Type          {$null = $Arguments.Add("--type $Type")}
        PacketSize    {$null = $Arguments.Add("--pkt-size $PacketSize")}
        Flags         {$null = $Arguments.Add("--flags $Flags")}
        CountersOnly  {$null = $Arguments.Add("-o")}
        EventProvider {$null = $Arguments.Add("-t $($EventProvider.ForEach{"-p $_"})")}
        EventMask     {$null = $Arguments.Add("-k $EventMask")}
        EventLogLevel {$null = $Arguments.Add("-l $EventLogLevel")}
        FileName      {$null = $Arguments.Add("-f $FileName")}
        FileSize      {$null = $Arguments.Add("-s $FileSize")}
        Mode          {$null = $Arguments.Add("-m $Mode")}
    }
    $Result = Invoke-PktMon -Arguments $Arguments
    if (!$PSBoundParameters.Quiet)
    {
        $Result
    }
}

<#
.Synopsis
   Stop data collection
.DESCRIPTION
   Stop data collection. Returns the generated etl file.
.EXAMPLE
   Stop-PktCapture
   Stops data collection and returns the generated etl file
#>
function Stop-PktCapture
{
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    Param()

    $Regex = '^Log\sfile\:\s(?<File>[^\(]+)\s\((?<Events>.+)\)$'
    switch -regex (Invoke-PktMon stop)
    {
        $Regex  {
                    Write-Verbose $Matches.Events
                    Get-Item $Matches.File
                }
        Default {Write-Verbose $_}
    }
}

<#
.Synopsis
   Convert ETL log file.
.DESCRIPTION
   Convert ETL log file to text or pcapng format.
.EXAMPLE
   Convert-PktEtlLog -EtlFile C:\Windows\System32\PktMon.etl -Pcapng
   Convert ETL file to pcapng format
.EXAMPLE
   Another example of how to use this cmdlet
#>
function Convert-PktEtlLog
{
    [CmdletBinding(DefaultParameterSetName='pcap')]
    [OutputType([System.IO.FileInfo])]
    Param
    (
        # ETL file to convert.
        [Parameter(mandatory)]
        [string]
        $EtlFile,

        # Path of the formatted file.
        [string]
        $FilePath,

        # Convert to text format.
        [Parameter(mandatory,ParameterSetName='text')]
        [switch]
        $Text,

        # Convert to pcapng format.
        [Parameter(mandatory,ParameterSetName='pcap')]
        [switch]
        $Pcapng,

        # Convert dropped packets only.
        [Parameter(ParameterSetName='pcap')]
        [switch]
        $DroppedOnly,

        # Filter packets by a specific component ID.
        [Parameter(ParameterSetName='pcap')]
        [int]
        $ComponentID,

        # Display log file statistical information.
        [Parameter(ParameterSetName='text')]
        [switch]
        $StatsOnly,

        # Use timestamp only prefix for events and packets.
        [Parameter(ParameterSetName='text')]
        [switch]
        $TimeStamp,

        # Print event metadata, such as logging level and keywords.
        [Parameter(ParameterSetName='text')]
        [switch]
        $MetaData,

        # Path to TMF files for decoding WPP traces.
        [Parameter(ParameterSetName='text')]
        [string[]]
        $TmfPath,

        # Use abbreviated packet format.
        [Parameter(ParameterSetName='text')]
        [switch]
        $Brief,

        # Verbosity level from 1 to 3.
        [Parameter(ParameterSetName='text')]
        [ValidateRange(1,3)]
        [int]
        $VerboseLvl,

        # Include hexadecimal format.
        [Parameter(ParameterSetName='text')]
        [switch]
        $IncludeHex,

        # Don't print ethernet header.
        [Parameter(ParameterSetName='text')]
        [switch]
        $NoEthernet,

        # Custom VXLAN port.
        [Parameter(ParameterSetName='text')]
        [int]
        $VXLANPort

    )

    $Arguments = [Collections.Arraylist]::new()
    switch ($PSBoundParameters.Keys)
    {
        Text        {$null = $Arguments.Insert(0,'etl2txt')}
        Pcapng      {$null = $Arguments.Insert(0,'etl2pcap')}
        EtlFile     {
                        If ($Arguments.Count -gt 0)
                        {
                            $null = $Arguments.Insert(1, $EtlFile)
                        }
                        else
                        {
                            $null = $Arguments.Add($EtlFile)
                        }
                    }
        FilePath    {$null = $Arguments.Add("-o $FilePath")}
        DroppedOnly {$null = $Arguments.Add("-d")}
        ComponentID {$null = $Arguments.Add("-c $ComponentID")}
        StatsOnly   {$null = $Arguments.Add("-s")}
        TimeStamp   {$null = $Arguments.Add("-t")}
        MetaData    {$null = $Arguments.Add("-m")}
        TmfPath     {$null = $Arguments.Add("-p $($TmfPath -join ';')")}
        Brief       {$null = $Arguments.Add("-b")}
        VerboseLvl  {$null = $Arguments.Add("-v")}
        IncludeHex  {$null = $Arguments.Add("-x")}
        NoEthernet  {$null = $Arguments.Add("-e")}
        VXLANPort   {$null = $Arguments.Add("-l")}
    }
    $Result = Invoke-PktMon -Arguments $Arguments
    if ($PSBoundParameters.StatsOnly)
    {
        return $Result
    }
    else
    {
        $Result | foreach{
            if ($_ -like 'packet*')
            {
                Write-Verbose $_
            }
            elseif ($_ -match 'Formatted file\:\s+(?<File>.+)')
            {
                Get-Item $Matches.File
            }
        }
    }
}

<#
.Synopsis
   Lists all active networking components that can be monitored
.DESCRIPTION
   Lists all active networking components that can be monitored,
   allowing you to examine the networking stack layout. The command
   shows networking components (drivers) arranged by adapters bindings.
.EXAMPLE
   Get-PktComponents
   Shows network adapters only.
.EXAMPLE
   Get-PktComponents -All
   Shows all networking components
.EXAMPLE
   Get-PktComponents -PoSH
   Shows all networking components, including hidden components.
   Output is PowerSHell objects.
#>
function Get-PktComponents
{
    [CmdletBinding(DefaultParameterSetName='default')]
    Param
    (
        # Show all component types.
        [Parameter(ParameterSetName='default')]
        [switch]
        $All,

        # Show components that are hidden by default.
        [Parameter(ParameterSetName='default')]
        [switch]
        $Hidden,

        # Output in json format. Implies -All and -Hidden.
        [Parameter(ParameterSetName='json')]
        [switch]
        $Json,

        # Output in PowerShell objects. Implies -All and -Hidden.
        [Parameter(ParameterSetName='posh')]
        [switch]
        $PoSH
    )

    $Arguments = [Collections.Arraylist]::new(@("list"))
    switch ($PSBoundParameters.Keys)
    {
        All    {$null = $Arguments.Add("-a")}
        Hidden {$null = $Arguments.Add("-i")}
        Json   {$null = $Arguments.Add("--json")}
        PoSH   {$null = $Arguments.Add("--json")}
    }
    $Result = Invoke-PktMon -Arguments $Arguments
    If ($PSBoundParameters.PoSH)
    {
        $Result | ConvertFrom-Json
    }
    else
    {
        return $Result
    }
}

#endregion functions

#region Classes

class PktFilter
{
   [int]           $Index
   [string]        $Name
   [string[]]      $IPAddress
   [string[]]      $MACAddress
   [int[]]         $Port
   [Nullable[int]] $VLAN
   [string]        $EtherType
   [string]        $Protocol
   [bool]          $Encapsulation
   [Nullable[int]] $VXLANPort
   

   PktFilter ([hashtable] $F)
   {
       foreach ($Prop in $F.Keys)
       {
            $this.$Prop = $F.$Prop
       }
       if ($this.Name -eq '<empty>')
       {
            $this.Name = ''
       }
   }
   
   PktFilter ([string] $s)
   {
       $Props = $s.Split(';').Trim()
       $Props.ForEach{
            $Prop = $_.Split(':')
            $this.($Prop[0]) = $Prop[1]
       }
   }

   [string] ToString()
   {
        $Properties = $this.GetType().GetProperties().Name.where{$this.$_}
        $array = $Properties.foreach{
            "$_`:$($this.$_ -join ',')"
        }
        return ($array -join '; ')
   }
}
