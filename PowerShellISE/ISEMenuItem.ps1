<#
.Synopsis
   Add menu item to Powershell ISE
.DESCRIPTION
   Adds a custom menu item to PowerShell ISE in the Add-ons menu
.EXAMPLE
   New-ISEMenuItem -DisplayName 'Custom menu'
   Create a menu item called Custom menu in de Add-ons menu
.EXAMPLE
   Get-ISEMenuItem -DisplayName 'Custom menu' | New-ISEMenuItem -DisplayName 'Show variables' -Action {Get-Variable | Out-Gridview -Title 'Current variables'} -ShortCut 'Alt+V'
   This will create a menu subitem in the 'Custom menu' item from the previous example that displays all variables in a gridview when clicked or when the keyboard shortcut Alt+V is used
#>
function New-ISEMenuItem
{
    [CmdletBinding()]
    Param
    (
        # DisplayName for the menu item
        [Parameter(Mandatory)]
        [string]
        $DisplayName,

        # ScriptBlock with an action
        [ScriptBlock]
        $Action,

        # Keyboard shortcut (I.E. 'Alt+V')
        [System.Windows.Input.KeyGesture]
        $Shortcut = $null,

        # Parent menu item
        [Parameter(ValueFromPipeline)]
        [Microsoft.PowerShell.Host.ISE.ISEMenuItem]
        $Parent,

        # return the menu item object
        [switch]
        $PassThru
    )

    Process
    {
        If ($PSBoundParameters['Parent'])
        {
            Write-Verbose "Using parent '$($Parent.DisplayName)'"
            $Root = $Parent
        }
        else
        {
            Write-Verbose "Using root menu"
            $Root = $psISE.CurrentPowerShellTab.AddOnsMenu
        }
        Write-Verbose "Creating menu item '$DisplayName'"
        $MenuItem = $Root.Submenus.Add($DisplayName,$Action,$Shortcut)
        If ($MenuItem -and $PSBoundParameters['PassThru'])
        {
            return $MenuItem
        }
    }
}

<#
.Synopsis
   Get custom PowerShell ISE menu items
.DESCRIPTION
   Get custom PowerShell ISE menu items
.EXAMPLE
   Get-ISEMenuItem
   Get all custom menu items
.EXAMPLE
   Get-ISEMenuItem -DisplayName Load*
   Get custom menu items that start with Load
#>
function Get-ISEMenuItem
{
    [CmdletBinding()]
    [OutputType([Microsoft.PowerShell.Host.ISE.ISEMenuItem])]
    Param
    (
        # Displayname of the menu item
        [string]
        $DisplayName
    )
    function GetSubmenu($Parent){
        $Subs = $Parent.Submenus
        $Subs.ForEach{
            $_
            If ($_.Submenus.Count -gt 0)
            {
                GetSubmenu $_
            }
        }
    }
    If ($DisplayName)
    {
        GetSubmenu $psISE.CurrentPowerShellTab.AddOnsMenu | where DisplayName -Like $DisplayName
    }
    else
    {
        GetSubmenu $psISE.CurrentPowerShellTab.AddOnsMenu
    }
}

<#
.Synopsis
   Remove ISE Menu Item
.DESCRIPTION
   Remove ISE Menu Item
.EXAMPLE
   Remove-ISEMenuItem
   Remove all custom menu items from ISE
.EXAMPLE
   Get-ISEMenuItem test* | Remove-ISEMenuItem
   Remove items that start with Test from ISE
#>
function Remove-ISEMenuItem
{
    [CmdletBinding()]
    Param
    (
        # Menu item to be removed
        [Parameter(ValueFromPipeline)]
        [Microsoft.PowerShell.Host.ISE.ISEMenuItem]
        $MenuItem
    )

    Process
    {
        If ($PSBoundParameters['MenuItem'])
        {
            $Parent = Get-ISEMenuItem | where Submenus -Contains $MenuItem
            $null = $Parent.Submenus.Remove($MenuItem)
        }
        else
        {
            $psISE.CurrentPowerShellTab.AddOnsMenu.Submenus.Clear()
        }
    }
}
