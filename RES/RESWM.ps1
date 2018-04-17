<#
.Synopsis
   Reset Ivanti Workspace Control agent on (remote) computer
.DESCRIPTION
   Reset Ivanti Workspace Control agent on (remote) computer
.EXAMPLE
   Reset-WMAgentCache -ComputerName PC001
.EXAMPLE
   Get-BrokerMachine -SummaryState Available | Reset-WMAgentCache | ogv -Title 'Resetting Workspace Cache for available desktops'
#>
function Reset-WMAgentCache
{
    [CmdletBinding()]
    [OutputType([psobject[]])]
    Param
    (
        # Name of remote computer
        [Parameter(ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        [Alias('HostedMachineName','DeviceName','Name','PSComputerName')]
        [string]
        $ComputerName = 'localhost'
    )
    Begin
    {
        $i = 1
        $ActiveJobIDs = Get-Job | select -ExpandProperty Id
    }
    Process
    {
        $null = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            $WMService = 'RES'
            switch ($env:PROCESSOR_ARCHITECTURE) {
                x86   {$RegPath = "HKLM:\SOFTWARE\RES\Workspace Manager"}
                AMD64 {$RegPath = "HKLM:\SOFTWARE\WOW6432Node\RES\Workspace Manager"}
            }
            $null = Test-Path $RegPath -ErrorAction Stop
            $Start = Get-Date
            $GlobalGUID = Get-ItemProperty -Path $RegPath\UpdateGUIDs -Name Global
            If ($GlobalGUID.Global)
            {
                Set-ItemProperty -Path $RegPath\UpdateGUIDs -Name Global -Value $null
            }
            Restart-Service $WMService
            Do
            {
                $GlobalGUID = Get-ItemProperty -Path $RegPath\UpdateGUIDs -Name Global
                If ($GlobalGUID.Global)
                {
                    $Time = (Get-Date) - $Start
                    $Output = [pscustomobject]@{
                        Success = $true
                        Time = $Time
                    }
                    return $Output
                }
                else
                {
                    $Time = (Get-Date) - $Start
                    sleep -Seconds 1
                }
            }
            Until ($Time.Minutes -eq 5)
            $Output = [pscustomobject]@{
                Success = $false
                Time = $Time
            }
            return $Output
        } -AsJob
    }
    End
    {
        $Jobs = Get-Job | Where Id -NotIn $ActiveJobIDs
        $Jobs | Receive-Job -Wait -AutoRemoveJob | select PSComputerName,Success,Time
    }
}
