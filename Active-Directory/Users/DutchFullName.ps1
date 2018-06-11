<#
.Synopsis
   Translates a useraccount to a dutch full name
.DESCRIPTION
   In the Netherlands lots of name have a surname prefix (van,den,etc...). 
   Active Directory doesn't account for this, thus the surname property for a 
   user account is usually entered like this: surname, prefix. (E.G. <Zouwen, van der>)

   This function translates this back to the original form, thereby returning
   a user's full name (GivenName included):

   Account properties:

   Surname    : Zouwen, van der
   GivenName  : Michaja

   Output:

   Michaja van der Zouwen
.EXAMPLE
   Get-ADUser Account001 | Get-DutchFullName
.EXAMPLE
   $Members = Get-ADGroupMember Group001 | Get-ADUser
   Get-DutchFullName -ADUser $Members
#>
function Get-DutchFullName
{
    [CmdletBinding()]
    [OutputType([string])]
    Param
    (
        [Parameter(Mandatory=$true,
                   ValueFromPipeline=$true,
                   Position=0)]
        [Microsoft.ActiveDirectory.Management.ADUser[]]
        $ADUser
    )

    Begin
    {
        $Prefixes = @(
            'van',
            'de',
            'der',
            'den',
            "'d",
            'het',
            "'t",
            'te',
            'ter',
            'ten',
            'aan',
            'bij',
            'in',
            'onder',
            'op',
            'over'
            "'s",
            'tot',
            'uit',
            'uijt',
            'voor'
        )
    }
    Process
    {
        Foreach ($User in $ADUser)
        {
            If ($User.Surname -and $User.GivenName)
            {
                $String = $User.SurName -replace '\.|,',''
                $Array = $String -split '\s+'
                $NewArray = @(0..($Array.count-1))
                while ($Array[-1] -in $Prefixes)
                {
                    for ($i = 0; $i -lt $Array.Count; $i++)
                    {
                        $NewArray[$i] = $Array[($i-1)]
                    }
                    $Array = @($NewArray)
                }
                Write-Output "$($User.GivenName) $($Array -join ' ')"
            }
            elseif ($User.DisplayName)
            {
                Write-Output $User.DisplayName
            }
        }
    }
}
