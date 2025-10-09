using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

#region Main

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Setting inital Status Code: 
$StatusCode = [HttpStatusCode]::OK

Write-Host "Request from Device: $($Request.Headers.from)"
$Request | ConvertTo-Json -Depth 9

$UserName = $Request.Body.userName

Write-Host "UserName from Input: $UserName"
Try
{
    Connect-MgGraph -Identity -ErrorAction Stop
    $MemberOf = Get-MgUserMemberOf -UserId $UserName -ErrorAction Stop
    $APROGroups = $MemberOf.AdditionalProperties.mailNickname.Where{$_ -match 'APRO'}
}
catch
{
    $StatusCode = [HttpStatusCode]::BadRequest
}


$Data = @{
    PROD = @()
    ACC = @()
    TEST = @()
}
foreach ($Group in $APROGroups)
{
    switch ($Group.Split('_')[1])
    {
        ONT  {$Env = 'TEST'}
        ACC  {$Env = 'ACC'}
        PROD {$Env = 'PROD'}
    }
    switch -regex ($Group)
    {
        IMA {
            If ($Data[$Env] -notcontains 'IMA')
            {
                $Data[$Env] += 'IMA'
            }
        }
        Banking {
            If ($Data[$Env] -notcontains 'BANKING')
            {
                $Data[$Env] += 'BANKING'
            }
        }
        Enter   {
            If ($Data[$Env] -notcontains 'Enter')
            {
                $Data[$Env] += 'Enter'
            }
        }
    }
}

$body = $Data | ConvertTo-Json -Depth 9

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = $StatusCode
    Body = $body
})

#endregion Main 

