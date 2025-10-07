#Write log in CMTrace format
function Write-Log 
{
    [Alias('Log')]
    Param (
        [Parameter(Mandatory)]
        [String]
        $Message,
 
        [Parameter()]
        [String]
        $Component = 'Script',
 
        [Parameter()]
        [ValidateSet('Information','Warning','Error')]
        [string]$Type,
        
        [Parameter()]
        [string]
        $LogFile = $LogFile
    )
    process
    {
        $Now = Get-Date
         switch ($Type){
            Information {$IntType = 1}
            Warning {$IntType = 2}
            Error {$IntType = 3}
        }
        $LogMessage = "<![LOG[$Message" + "]LOG]!><time=`"$($Now.ToString('HH:mm:ss.ffffff'))`" date=`"$($Now.ToString('MM-dd-yyyy'))`" component=`"$Component`" context=`"`" type=`"$IntType`" thread=`"`" file=`"`">"
        $LogMessage | Out-File -Append -Encoding UTF8 -FilePath $LogFile
    }
}
