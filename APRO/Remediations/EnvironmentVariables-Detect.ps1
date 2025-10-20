# UNC Paths to APRO shares
$UncPaths = @{
    APROPRD = "\\<Apro_Prod path>"
    APROACC = "\\<APRO-ACC path>"
    APROTST = "\\<APRO-test path>"
}

#Detect proper values
foreach ($Key in $UncPaths.Keys)
{
    $Value = [System.Environment]::GetEnvironmentVariable($Key,'User')
    if ($Value -ne $UncPaths[$Key])
    {
        Write-Host "Fail: $Key is not set to $($UncPaths[$Key]) or does not exist"
        exit 1
    }
}
exit 0
