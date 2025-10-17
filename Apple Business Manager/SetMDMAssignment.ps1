#Assign or Unassign a device from a MDM Service (requires ABMPS module)
function Set-AppleBusinessManagerDeviceMDMAssignment
{
    [CmdletBinding()]
    Param(
        #Organization Device object
        [Parameter(mandatory,ValueFromPipeline)]
        [ValidateScript({$_.type -eq 'orgDevices'})]
        [psobject]
        $OrgDevice,

        #Device Management Service object
        [Parameter(mandatory)]
        [ValidateScript({$_.type -eq 'mdmServers'})]
        [psobject]
        $MDMServer,

        #Activity (Assign or Unassign)
        [ValidateSet('ASSIGN_DEVICES','UNASSIGN_DEVICES')]
        [string]
        $ActivityType = 'ASSIGN_DEVICES'
    )
    Begin
    {
        Write-Verbose 'Creating request body'
        $Body = @{
            data = @{
                type = 'orgDeviceActivities'
                attributes = @{
                    activityType = $ActivityType
                }
                relationships = @{
                    mdmServer = @{
                        data = @{
                            type = 'mdmServers'
                            id = $MDMServer.id
                        }
                    }
                    devices = @{
                        data = [System.Collections.ArrayList]::new()
                    }
                }
            }
        }
    }
    Process
    {
        Write-Verbose "Adding $($OrgDevice.Id) to the request body"
        $Body.data.relationships.devices.data.Add(@{
            type = 'orgDevices'
            id = $OrgDevice.id
        })
    }
    End
    {
        $Params = @{
            Uri = 'https://api-business.apple.com/v1/orgDeviceActivities'
            Method = 'Post'
            Authentication = 'Bearer'
            Token = 'Get-AppleBusinessManagerBearerToken'
            ContentType = 'application/json' 
            Body = $Body | ConvertTo-Json -Depth 5
        }
        Invoke-RestMethod @Params -ErrorAction Stop
    }
}
