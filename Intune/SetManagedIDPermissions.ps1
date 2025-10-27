#region Variables

$Permissions = 'Group.Read.All','GroupMember.Read.All','Mail.Send','ServiceMessage.Read.All'
$ManagedIdentity = 'pwexpirationdate'
$Type = 'Graph' #or Exchange

#endregion Variables

#region constants

$GraphAppId = "00000003-0000-0000-c000-000000000000"
$ExchangeAppId = "00000002-0000-0ff1-ce00-000000000000"

#endregion constants

#region Connection

if (!(Get-MgContext))
{
    if ($psISE)
    {
        Connect-TKGraph
    }
    else
    {
        Connect-MgGraph -Identity 
    }
}

#endregion Connection

#region Main
switch ($Type)
{
    Graph    {$AppID = $GraphAppId}
    Exchange {$AppID = $ExchangeAppId}
}
$ManagedID = Get-MgServicePrincipal -Filter "displayName eq '$ManagedIdentity'"
$ServicePrincipal = Get-MgServicePrincipal -Filter "appId eq '$AppId'"
$AppRoles = $ServicePrincipal.AppRoles.where{$_.Value -in $Permissions -and $_.AllowedMemberTypes -contains "Application"}

$Params = @{
    ServicePrincipalId = $ManagedID.Id
    PrincipalId = $ManagedID.Id
    ResourceId  = $ServicePrincipal.Id
    AppRoleId   = ''
}

foreach ($AppRole in $AppRoles)
{
    $Params.AppRoleId = $AppRole.Id
    New-MgServicePrincipalAppRoleAssignment @Params
}

#endregion Main
