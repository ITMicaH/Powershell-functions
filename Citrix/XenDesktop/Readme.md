# QueryODATA.ps1
## Functions
### Get-CitrixODATAInformation
Uses the oDATA API to query information on a Citrix XenApp/XenDesktop environment.
Output objects are supplied with ScriptMethods which allow you to navigate directly to
related information objects (entities).

EXAMPLE:

`PS\> $User = Get-CitrixODATAInformation -Server SVR-CDC-001 -Type User -Name TestUser01 -Credential CONTOSO\CTXAdmin`

 Retreives information on user 'TestUser01' using credentials 'CONTOSO\CTXAdmin'. The user will be
 prompted for a password. The server 'SVR-CDC-001' is used to query the oDATA API.
 
EXAMPLE:

`PS\> $UserSessions = $User.GetSessions()`

Retreives all sessions initiated by the user of the previous example.

EXAMPLE:

`PS\> $UsedClients = $UserSessions[0..4].GetConnections($true).ClientName`

Retreives names of all the clients the user of the previous example has run his/hers first five sessions on.
