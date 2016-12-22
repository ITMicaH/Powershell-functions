<#
.Synopsis
    Get installed software on (remote) computer
.DESCRIPTION
    Uses remote registry to query installed software on a local or remote computer.
.PARAMETER ComputerName
    Name of the computer to query software on.
.PARAMETER DisplayName
    Displayname of the software package. Wildcards are allowed.
.PARAMETER Publisher
    Name of the publisher of the software package. Wildcards are allowed.
.EXAMPLE
    Get-InstalledSoftware
    Gets all installed software on the local computer.
.EXAMPLE
    Get-InstalledSoftware -ComputerName PC001 -DisplayName *reader*
    Gets installed software with the word reader in the displayname from remote computer PC001.
.EXAMPLE
    Get-InstalledSoftware -ComputerName PC001,PC002 -Publisher Microsoft*
    Gets installed Microsoft software from remote computers PC001 and PC002.
#>
Function Get-InstalledSoftware
{

    [CmdletBinding()]
    Param
    (
        # Name of the computer to query software on
        [Parameter(Mandatory=$true,
                    ValueFromPipeline=$true,
                    ValueFromPipelineByPropertyName=$true,
                    Position=0)]
        [string[]]
        $ComputerName,

        # Displayname of the software package
        [Parameter(Mandatory=$false,
                    Position=1)]
        [string]
        $DisplayName,

        # Name of the publisher of the software package
        [Parameter(Mandatory=$false,
                    Position=2)]
        [string]
        $Publisher
    )

    Begin
    {
        $regGUID = "^(\{){0,1}[0-9a-fA-F]{8}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{12}(\}){0,1}$"
        $UninstallKeys = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\','SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\'
    }
    Process
    {
        $arrSoftware = @()
        foreach ($sComputer in $ComputerName) {

            Write-Verbose "Testing connection to '$sComputer'..."
            IF (Test-Connection $sComputer -Quiet -Count 1) {
        
                Write-Verbose 'Computer appears to be online.'
                $State = 'Online'

                #Connect remote registry
                try {
                    Write-Verbose 'Connecting with Remote Registry...'
                    $oReg = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $sComputer)
                }
                catch {
                    Write-Error "Unable to connect to Remote Registry on computer $sComputer."
                    break
                }
                Write-Verbose 'Connection established.'
        
                If ($oReg) { #Remote registry connected
                    
                    Write-Verbose 'Searching registry for installed software...'

                    #Create array
                    $Software = @()

                    foreach ($UninstallKey in $UninstallKeys) {
                        $arrKey = ''
                        $arrSubKeys = ''
                        $arrKey = $oReg.OpenSubKey($UninstallKey)
                        IF ($arrKey) {
                            $arrSubKeys = $arrKey.GetSubKeyNames() | ?{$_ -match $regGUID}
                
                            foreach ($SubKey in $arrSubKeys) {

                                #Get software data
                                $ProgKey = $arrKey.OpenSubKey($SubKey)

                                If ($DisplayName)
                                {
                                    If ($ProgKey.GetValue('DisplayName') -notlike $DisplayName)
                                    {
                                        continue
                                    }
                                }
                                If ($Publisher)
                                {
                                    If ($ProgKey.GetValue('Publisher') -notlike $Publisher)
                                    {
                                        continue
                                    }
                                }

                                #create object from data
                                $Properties = @{
                                    'ComputerName' = $sComputer;
                                    'DisplayName' = $ProgKey.GetValue('DisplayName');
                                    'DisplayVersion' = $ProgKey.GetValue('DisplayVersion');
                                    'Publisher' = $ProgKey.GetValue('Publisher');
                                    'InstallLocation' = $ProgKey.GetValue('InstallLocation');
                                    'UninstallString' = $ProgKey.GetValue('UninstallString');
                                    'State' = $State;
                                }
                                $Software += (New-Object –TypeName PSObject -Property $Properties)
                            }
                        }
                    }
                }
    
                #Display software list
                $Software
            }
            else
            {
                Write-Error "Computer '$sComputer' is not reachable."
            }
        }
    }
    End
    {
    }
}
