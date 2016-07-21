# NetConnectionProfiles.ps1
## Functions
### Get-NetConnectionProfile
Gets the category for network connections for the local computer.

Example:

`PS\> Get-NetConnectionProfile -NetworkCategory Public`

This will get the category for all public network connections:

```
IsConnectedToInternet : False
Category              : Public
Description           : Unknown network
Name                  : Unknown network
IsConnected           : True
```

### Set-NetConnectionProfile
Sets the category for network connections for the local computer.

Example:

`PS\> Get-NetConnectionProfile -NetworkCategory Public | Set-NetConnectionProfile -NetworkCategory Private`

Sets the network category for all Public connections to Private
