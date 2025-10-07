#region constants

$GraphAppId = "00000003-0000-0000-c000-000000000000"

#endregion constants

#region Connection

if (!(Get-MgContext))
{
    Connect-MgGraph -Identity -Scopes User.Read.All,Directory.Read.All,DeviceManagementManagedDevices.Read.All,Device.Read.All,DeviceManagementConfiguration.Read.All
}

#endregion Connection

#region Main

$Users = Get-MgUser -ExpandProperty RegisteredDevices -All
$Duplicates = Get-MgDevice -All | 
    where OperatingSystem -match Android | 
    where Model -NotMatch poly | 
    where DeviceOwnership -eq Company |
    group DisplayName | where count -gt 1 |
    where {$_.group.IsCompliant -contains $false}


Write-Warning "$($Duplicates.Name.Count) duplicate android phones found"
$Duplicates.Group | where IsCompliant -eq $false | foreach {
    Remove-MgDevice -InputObject $_ -WhatIf
}

#Overzicht van laatste 30 dagen voor Remko
$LastMonth = foreach ($Duplicate in $Duplicates)
{
    $Compliant = $Duplicate.Group.where{$_.IsCompliant}
    if ($Compliant.RegistrationDateTime -ge (Get-Date 0:00).adddays(-30))
    {
        $mDevice = Get-MgDeviceManagementManagedDevice -Filter "AzureAdDeviceId eq '$($Compliant.DeviceId)'"
        [pscustomobject]@{
            User = $mDevice.UserPrincipalName
            Device = "$($mDevice.Manufacturer) $($mDevice.Model)"
            MDMDeviceId = $mDevice.Id
            OperatingSystem = "$($mDevice.OperatingSystem) $($mDevice.OSVersion)"
            SerialNumber = $mDevice.SerialNumber
            RegistrationDateTime = $Compliant.RegistrationDateTime
            EnrollmentDateTime = $mDevice.EnrolledDateTime
        }
    }
}
$LastMonth | clip

#endregion Main


