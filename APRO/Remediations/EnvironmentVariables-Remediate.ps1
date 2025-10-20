# UNC Paths to APRO shares
$UncPaths = @{
    APROPRD = "\\<Apro_Prod path>"
    APROACC = "\\<APRO-ACC path>"
    APROTST = "\\<APRO-test path>"
}

# Set environment variable
foreach ($Key in $UncPaths.Keys)
{
    [System.Environment]::SetEnvironmentVariable($Key,$UncPaths[$Key],'User')
}

#If APRO is installed sync all enviroments
if (Get-ScheduledTask -TaskName APROSync -TaskPath \ -ErrorAction SilentlyContinue)
{
    Start-ScheduledTask -TaskName APROSync
}
