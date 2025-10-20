# UNC Paths to APRO shares
$UncPaths = @{
    APROPRD = "\\vsw-apl-021\apro$\Apro_Prod"
    APROACC = "\\tst-vsw-apl-058\apro$\APRO-acceptatie"
    APROTST = "\\tst-vsw-apl-058\apro$\APRO-test"
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
