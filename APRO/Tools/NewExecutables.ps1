$Launcher = "\\<Path To>\Launcher.ps1"
$Sync = "\\<Path To>\Sync.ps1"
$Helper = "\\<Path To>\FSHelper.ps1"
$Path = "\\<Path To>\Intune\APRO" # Path to save executables

& "O:\Portable Apps\PS2Exe\ps2exe.ps1" -inputFile $Launcher -outputFile $Path\APRO_Launcher.exe -x64 -title 'APRO Launcher' -copyright 'Michaja van der Zouwen' -version 1.0 -STA -noConsole -DPIAware 
& "O:\Portable Apps\PS2Exe\ps2exe.ps1" -inputFile $Sync -outputFile $Path\APRO_Sync.exe -x64 -title 'APRO Sync tool' -copyright 'Michaja van der Zouwen' -version 1.0 -MTA -noConsole -noVisualStyles -noOutput
& "O:\Portable Apps\PS2Exe\ps2exe.ps1" -inputFile $Helper -outputFile $Path\APRO_FSHelper.exe -x64 -title 'APRO FileSystem Helper' -copyright 'Michaja van der Zouwen' -version 1.0 -MTA -noConsole -noVisualStyles -noOutput
