<#
.Synopsis
   Get graph permissions and modules required to run a script
.DESCRIPTION
   Get graph permissions and modules required to run a script. This can be a scriptfile or the script in your current ISE tab.
.EXAMPLE
   Get-MgScriptPermissions -FilePath C:\Script.ps1
   Displays permissions and modules necessary for C:\Script.ps1
.EXAMPLE
   perms
   Displays permissions and modules necessary for the script in the current ISE tab
#>
function Get-MgScriptPermissions
{
    [CmdletBinding()]
    [Alias("Perms")]
    Param(
        # Path to the scriptfile
        [string]
        $FilePath
    )
    If ($PSBoundParameters.FilePath)
    {
        $Commands = [regex]::Matches((Get-Content $FilePath),'\w+-Mg\w+').value
    }
    elseif ($psISE)
    {
        $Commands = [regex]::Matches($psISE.CurrentFile.Editor.Text.Split("`n"),'\w+-Mg\w+').value
    }
    else
    {
        throw 'No path to a scriptfile was given'
    }
    $Commands.foreach{
        If ($MgCommand = Find-MgGraphCommand $_ -ea 0 | select -Last 1)
        {
            [pscustomobject]@{
                Command = $_
                Module = "Microsoft.Graph.$($MgCommand.Module)"
                Permissions = ($MgCommand.Permissions.Name | select -Unique) -join "`n"
            }
        }
    } | Format-List
}
