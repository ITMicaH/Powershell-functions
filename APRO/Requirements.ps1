[System.Environment]::GetEnvironmentVariables('User').Keys.Where{$_ -like 'APRO*'}.count -ge 4
