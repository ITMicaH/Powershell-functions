# QueryODATA.ps1
## Functions
### Get-CitrixODATAInformation
Uses the oDATA API to query information on a Citrix XenApp/XenDesktop environment.
Output objects are supplied with ScriptMethods which allow you to navigate directly to
related information objects (entities).

## ChangeLog
07-07-2016 : v1.0
14-03-2017 : Added Filter parameter and removed Date (dynamic) parameter.

## Examples
EXAMPLE:

`PS\> $User = Get-CitrixODATAInformation -Server SVR-CDC-001 -Type User -Name TestUser01 -Credential CONTOSO\CTXAdmin`

 Retreives information on user 'TestUser01' using credentials 'CONTOSO\CTXAdmin'. The user will be
 prompted for a password. The server 'SVR-CDC-001' is used to query the oDATA API.
 
EXAMPLE:

`PS\> $UserSessions = $User.GetSessions()`

Retreives all sessions initiated by the user of the previous example.

EXAMPLE:

`PS\> $UsedClients = $UserSessions[0..4].GetConnections().ClientName`

Retreives names of all the clients the user of the previous example has run his/hers first five sessions on.

EXAMPLE:

`PS\> $UserSessions = $User.GetSessions("ConnectionState -ne 'Terminated'")`

Retreives sessions initiated by the user of the previous example where the ConnectionState property does not have a value of 'Terminated'.

EXAMPLE:

`PS\> Get-CitrixODATAInformation -Server SVR-CDC-001 -Type Session -Filter "StartDate -gt $((Get-Date).AddDays(-1))"`

Retreives all sessions started in the last day.

# UpdateMachineId.ps1
## Functions
### Update-HostedMachineId
Machines in Desktop Studio or Desktop Director display a Power State of 'Unknown'.
This can be caused by changes made on the hypervisor to VM metadata. If the VM's 
unique ID has changed then the XenDesktop database may be unaware of this UID mismatch.
This function will verify the UID known to XenDesktop for the VMs and compare against
the UID provided by the hypervisor. If there's a mismatch the ID will be updated 
in the database.

## ChangeLog
29-06-2018 : v1.0

## Examples

EXAMPLE:
    
`PS\> Get-BrokerMachine -PowerState Unknown | Update-HostedMachineId`
    
Update Machine IDs using local Delivery Controller.
    
EXAMPLE:

`PS\> Get-BrokerMachine -PowerState Unknown | Update-HostedMachineId -Controller srv-cdc-001 -Restart`
    
Update Machine IDs using Delivery Controller srv-cdc-001 and restart the repaired VMs.
