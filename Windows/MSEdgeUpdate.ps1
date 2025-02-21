<#
.Synopsis
   Display Microsoft Edge update history
.DESCRIPTION
   Gets the update history from Microsoft Edge from the log file.
.EXAMPLE
   Get-MSEdgeUpdateHistory
.EXAMPLE
   Get-MSEdgeUpdateHistory -LogPath 'H:\MicrosoftEdgeUpdate.log'
#>
function Get-MSEdgeUpdateHistory
{
    Param(
        #Path to MicrosoftEdgeUpdate.log
        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string]
        $LogPath = "$env:ALLUSERSPROFILE\Microsoft\EdgeUpdate\Log\MicrosoftEdgeUpdate.log"
    )
    $Output = [Collections.Arraylist]::new()
    switch -Regex (Get-Content $LogPath)
    {
        '\[(?<Date>\d{2}/\d{2}/\d{2})\s.+Running\sinstaller.+MicrosoftEdge_X64_(?<Version>.+).exe\]' {
            $Attempt = [pscustomobject]@{
                Date = [datetime]::ParseExact($Matches.Date,'M/d/yy',$null).ToShortDateString()
                Version = $Matches.Version
            }
        }
        'InstallApp\sreturned.+code:\s(?<Code>\d+)' {
            If ($Attempt)
            {
                If ($Matches.Code -eq '2')
                {
                    $null = $Output.Add($Attempt)
                }
                Remove-Variable Attempt
            }
        }
    }
    $Output | select * -Unique
}
