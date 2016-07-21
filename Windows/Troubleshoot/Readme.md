# WERUserModeDumps.ps1
## Functions
### Enable-WERUserModeDumps
Enables User-Mode (Application Crash) dumps using Windows Error Reporting on a local or remote computer.
Requires to be run under an account with admin rights on the computer.

Example:

`PS\> Enable-WERUserModeDumps -ComputerName PC001,PC002 -Process iexplore.exe -DumpFolder D:\Dumps -DumpType FullDump`

Enables User-Mode dumps on PC001 and PC002 using default values:
10 full dump maximum in folder 'D:\Dumps' for application Internet Explorer (iexplorer.exe)

### Disable-WERUserModeDumps
Disables User-Mode (Application Crash) dumps on a local or remote computer.
Requires to be run under an account with admin rights on the computer.

Example:

`PS\> Disable-WERUserModeDumps -ComputerName PC001,PC002`

Enables User-Mode dumps on PC001 and PC002.
