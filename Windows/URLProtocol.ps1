
<#
.Synopsis
   Create an URL protocol
.DESCRIPTION
   Create an URL protocol for a toast action or website
.EXAMPLE
   New-URLProtocol -URL Reboot -Command 'shutdown.exe /r /f /t 0' -Force
   Creates a protocol that will reboot the computer by running Reboot:
#>
function New-URLProtocol
{
    [CmdletBinding()]
    Param(
        #Name of the URL
        [Parameter(mandatory)]
        [string]
        $URL,

        #Command that will be executed
        [Parameter(mandatory)]
        [string]
        $Command,

        #Machine or User scope
        [ValidateSet('Machine','User')]
        [string]
        $Scope = 'User',

        #Return created registry key
        [switch]
        $PassThru,

        #Overwrite existing protocol
        [switch]
        $Force
    )
    switch ($Scope)
    {
        Machine {$Prefix = 'HKLM:'}
        User {$Prefix = 'HKCU:'}
    }
    $RootKey = "$Prefix\Software\Classes\$URL"
    If (!(Test-Path $RootKey) -or $PSBoundParameters.Force)
    {
        Write-Verbose "Creating URL protocol $URL in $Scope scope"
        $null = New-Item $RootKey -Value "URL:$URL" -Force
        $null = New-ItemProperty -Path $RootKey -Name 'URL Protocol' -Value '' -Force
        $Output = New-Item $RootKey\shell\open\command -Value $Command -Force
    }
    else
    {
        Write-Error "URL Protocol $URL already exists. Use -Force to overwrite." -Category ResourceExists -TargetObject $URL
    }
    If ($PSBoundParameters.PassThru)
    {
        return $Output
    }
}
