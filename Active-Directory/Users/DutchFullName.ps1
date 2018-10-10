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
        $ADUser,

        [switch]
        $SurnameOnly
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
            If ((Get-Member -InputObject $User -MemberType Property).Name -notcontains 'DisplayName')
            {
                Write-Warning "User object $($User.SamAccountName) does not have the property [DisplayName]"
            }
            If ($User.Surname -and $User.GivenName)
            {
                $Array = $User.SurName -replace '\.|,','' -split '\s+'
                $SurnameCheck = compare $Array $Prefixes -IncludeEqual
                $DisplayNameCheck = compare ($User.DisplayName -Split ' ') $Prefixes -IncludeEqual
                If ($SurnameCheck.SideIndicator -contains '==')
                {
                    $FullSurname = $SurnameCheck.Where({$_.SideIndicator -ne '=>'}).InputObject -join ' '
                }
                elseif ($DisplayNameCheck.SideIndicator -contains '==')
                {
                    $FullSurname = "$($DisplayNameCheck.Where({$_.SideIndicator -eq '=='}).InputObject -join ' ') $($User.Surname)"
                }
                else
                {
                    Write-Verbose "No prefixes"
                    $FullSurname = $User.Surname
                }
                If ($PSBoundParameters['SurnameOnly'])
                {
                    Write-Output $FullSurname
                }
                else
                {
                    Write-Output "$($User.GivenName) $FullSurname"
                }
            }
            elseif ($User.DisplayName)
            {
                $User.DisplayName
            }
        }
    }
}
