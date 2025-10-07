$AppRegName = '<Name of App Registration>'
$Permissions = '<Arary of permissions>'

$GraphAppId = "00000003-0000-0000-c000-000000000000"

$AppReg = Get-MgApplication -Filter "displayName eq '$AppRegName'"
$GraphServicePrincipal = Get-MgServicePrincipal -Filter "appId eq '$GraphAppId'"
$AppRoles = $GraphServicePrincipal.AppRoles.where{$_.Value -in $Permissions -and $_.AllowedMemberTypes -contains "Application"}

Update-MgApplication -ApplicationId $AppReg.Id -AppRoles $AppRoles
