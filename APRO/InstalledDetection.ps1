Param(
    [ValidateSet('PROD','ACC','TEST')]
    [string]
    $Environment = 'PROD',

    [bool]
    $ViewerOnly = $true
)

#region Constants

$ProgramFolder = "$env:ProgramW6432\APRO"

#endregion Constants

#region Main

If ($ViewerOnly)
{
    if (Get-ChildItem "$ProgramFolder\$Environment" -Filter *facturen.exe -Recurse)
    {
        Write-Output 'Viewer Detected'
        exit 0
    }
    else
    {
        exit 1
    }
}
elseif (Get-ChildItem "$ProgramFolder\$Environment" -Filter APRO*.exe -Recurse)
{
    Write-Output 'Detected'
    exit 0
}
else
{
    exit 1
}

#endregion Main
