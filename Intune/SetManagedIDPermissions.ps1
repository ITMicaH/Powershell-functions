#region Variables

$Permissions = 'Group.Read.All','GroupMember.Read.All','Mail.Send','ServiceMessage.Read.All'
$ManagedIdentity = '<Name of the Managed ID>'

#endregion Variables

#region constants

$GraphAppId = "00000003-0000-0000-c000-000000000000"

#endregion constants

#region Connection

if (!(Get-MgContext))
{
    Connect-MgGraph -Identity -Scopes Directory.Read.All,AppRoleAssignment.ReadWrite.All,Application.Read.All
}

#endregion Connection

#region Main

$ManagedID = Get-MgServicePrincipal -Filter "displayName eq '$ManagedIdentity'"
$GraphServicePrincipal = Get-MgServicePrincipal -Filter "appId eq '$GraphAppId'"
$AppRoles = $GraphServicePrincipal.AppRoles.where{$_.Value -in $Permissions -and $_.AllowedMemberTypes -contains "Application"}

$Params = @{
    ServicePrincipalId = $ManagedID.Id
    PrincipalId = $ManagedID.Id
    ResourceId  = $GraphServicePrincipal.Id
    AppRoleId   = ''
}

foreach ($AppRole in $AppRoles)
{
    $Params.AppRoleId = $AppRole.Id
    New-MgServicePrincipalAppRoleAssignment @Params
}

#endregion Main
