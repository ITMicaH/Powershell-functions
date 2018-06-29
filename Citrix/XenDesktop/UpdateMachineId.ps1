<#
.Synopsis
   Update HostedMachineId property
.DESCRIPTION
   Machines in Desktop Studio or Desktop Director display a Power State of 'Unknown'.
   This can be caused by changes made on the hypervisor to VM metadata. If the VM's 
   unique ID has changed then the XenDesktop database may be unaware of this UID mismatch.
   This function will verify the UID known to XenDesktop for the VMs and compare against
   the UID provided by the hypervisor. If there's a mismatch the ID will be updated 
   in the database.
.EXAMPLE
   Get-BrokerMachine -PowerState Unknown | Update-HostedMachineId
   Update Machine IDs using local Delivery Controller.
.EXAMPLE
   Get-BrokerMachine -PowerState Unknown | Update-HostedMachineId -Controller srv-cdc-001 -Restart
   Update Machine IDs using Delivery Controller srv-cdc-001 and restart the updated VMs.
.NOTES
   Author : Michaja van der Zouwen
.LINK
   https://support.citrix.com/article/CTX131267#Solution%201
   https://github.com/ITMicaH/Powershell-functions/blob/master/Citrix/XenDesktop/Readme.md#updatemachineidps1
#>
function Update-HostedMachineId
{
    [CmdletBinding(SupportsShouldProcess=$true, 
                  PositionalBinding=$false,
                  HelpUri = 'https://github.com/ITMicaH/Powershell-functions/blob/master/Citrix/XenDesktop/Readme.md#updatemachineidps1',
                  ConfirmImpact='Medium')]
    Param
    (
        # BrokerMachine to update
        [Parameter(Mandatory=$true, 
                   ValueFromPipeline=$true,
                   Position=0)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [Citrix.Broker.Admin.SDK.Machine]
        $BrokerMachine,

        # Name of a delivery controller
        [string]
        $Controller = 'localhost',

        # Restart the VM if updated
        [switch]
        $Restart
    )

    Begin
    {
        If (!(Test-Path XDHyp: -Verbose:$false))
        {
            Write-Verbose "Adding Citrix Host Admin snapin"
            Add-PSSnapin Citrix.Host.Admin.V2 -Verbose:$false -ErrorAction Stop
        }
        Write-Verbose "Checking controller existance"
        $XDHyp = Get-PSDrive XDHyp -ErrorAction Stop
        switch ($Controller)
        {
             localhost {$DNSName = "$env:COMPUTERNAME.*"}
             Default   {$DNSName = "$Controller.*"}
        }
        If (Get-BrokerController -DNSName $DNSName)
        {
            Write-Verbose "Controller $Controller exists"
            $XDHyp.AdminAddress = $Controller
        }
        else
        {
            Write-Error -Message "Server '$Controller' is not a registered Delivery Controller" -Category InvalidArgument -ErrorAction Stop
        }
    }
    Process
    {
        Write-Verbose "Processing VM $($BrokerMachine.HostedMachineName)"
        $XDHypVM = Get-Item -Path XDHyp:\Connections\$($BrokerMachine.HypervisorConnectionName)\*\*\$($BrokerMachine.HostedMachineName).vm -Verbose:$false
        If ($XDHypVM.Id -ne $BrokerMachine.HostedMachineId)
        {
            Write-Verbose "Correcting HostedMachineId"
            if ($pscmdlet.ShouldProcess($BrokerMachine.HostedMachineName, "Correct [HostedMachineId]"))
            {
                $BrokerMachine | Set-BrokerMachine -HostedMachineId $XDHypVM.Id -PassThru
                If ($PSBoundParameters.Restart)
                {
                    Restart-Computer $BrokerMachine.HostedMachineName
                }
            }
            $Action = 'Updated'
        }
        else
        {
            Write-Verbose "Property [HostedMachineId] is correct."
            $Action = 'Skipped'
        }
        [PSCustomObject]@{
            Action = $Action
            BrokerMachine = $BrokerMachine | Add-Member ScriptMethod -Name ToString -Value {$this.HostedMachineName} -Force -PassThru
        }
    }
}
