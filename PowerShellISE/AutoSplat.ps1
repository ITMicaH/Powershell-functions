<#
.Synopsis
   Converts a single line command into a splatted command
.DESCRIPTION
   This function converts a command with parameters and their values into a splatted version of the same command.
   The command can either be provided as text input for the Command parameter, in which case the splatted command will 
   be output to the console, or it can be provided by selecting it in PowerShell ISE, in which case the splatted command will
   replace the selected command in the editor.
.EXAMPLE
   ConvertTo-SplatCommand -Command '$Logs = Get-ChildItem -Path C:\Windows\Logs -Filter *.log' -verbose
   Converts the command [$Logs = Get-ChildItem -Path C:\Windows\Logs -Filter *.log] to a splatted command
   
   Output:

   $Params = @{
	      Path = 'C:\Windows\Logs'
	      Filter = '*.log'
    }
    $Logs = Get-ChildItem @Params
.EXAMPLE
   ConvertTo-SplatCommand Get-ChildItem -Path C:\Windows -Filter *.exe -Recurse -Depth 2
   Converts the command [Get-ChildItem -Path C:\Windows -Filter *.exe -Recurse -Depth 2] to a splatted command
   
   Output:

   $Params = @{
	      Path = 'C:\Windows'
	      Filter = '*.exe'
	      Recurse = $true
	      Depth =  2
    }
    Get-ChildItem @Params
.EXAMPLE
   ConvertTo-SplatCommand
   Converts the command selected in ISE to a splatted command. The splatted command replaces the selected command directly in the editor.
#>
function ConvertTo-SplatCommand
{
    [CmdletBinding()]
    [Alias('splat')]
    Param(
        [Parameter(ValueFromRemainingArguments)]
        [string]
        $Command
    )

    If (!$PSBoundParameters.Command)
    {
        if ($psISE -and $psISE.CurrentFile.Editor.SelectedText)
        {
            Write-Verbose "Retreiving command from selected text"
            $Command = $psISE.CurrentFile.Editor.CaretLineText
        }
        else
        {
            Write-Error -Exception 'No command specified or selected in ISE' -Category NotSpecified -ErrorAction Stop
        }
    }
    [regex]$ParamPattern = '(\B-(?<Parameter>\S+))(?<Value>\s''[^'']+''|\s"[^"]+"|\s\S(?<!-)\S*)*'
    if ($Matches = $ParamPattern.Matches($Command))
    {
        Write-Verbose "Processing command [$Command]"
        $Parameters = $Matches.Groups.Where{$_.Name -eq 'Parameter'}.Captures
        $Values = $Matches.Groups.Where{$_.Name -eq 'Value'}.Captures
        [regex]$CmdletPattern = '^(?<Indent>\s*)(?<Variable>\$[^=]+)?\s*=?\s*(?<Cmdlet>\S+)'
        $CmdletMatch = $CmdletPattern.Matches($Command)
        $Cmdlet = $CmdletMatch.Groups[3].Value
        If ($Variable = $CmdletMatch.Groups[2].Value)
        {
            Write-Verbose "Found a variable: [$Variable]"
            $Variable = "$($Variable.Trim()) = "
        }
        if ($Spaces = $CmdletMatch.Groups[1].Length)
        {
            Write-Verbose "Calculating indentation"
            if ($Spaces / 4 -is [int])
            {
                $Indent = "`t" * ($Spaces / 4)
            }
            else
            {
                $Indent = " " * $Spaces
            }
        }
        else
        {
            $Indent = ''
        }
        $HashPairs = foreach ($Parameter in $Parameters)
        {
            Write-Verbose "Processing parameter [$($Parameter.Value)]"
            $FindValue = $Values.Where{$_.Index -eq ($Parameter.Index + $Parameter.Length)}
            if (!$FindValue)
            {
                Write-Verbose "Parameter is a switch"
                $Value = '$true'
            }
            elseif ($FindValue.Value -match '\d+')
            {
                Write-Verbose "Value is a number"
                $Value = $FindValue.Value
            }
            elseif ($FindValue.Value -notmatch "^\s[\$|'|""]")
            {
                Write-Verbose "Value is a string without quotes"
                $Value = "'$($FindValue.Value.Trim())'"
            }
            else
            {
                $Value = $FindValue.Value.Trim()
            }
            "$Indent`t$($Parameter.Value) = $Value"
        }
        $Splat = "`$Params = @{`n$($HashPairs -join "`n")`n$Indent}`n$Indent$Variable$Cmdlet @Params"
    }
    If (!$PSBoundParameters.Command)
    {
        Write-Verbose "Inserting splatted command in ISE editor"
        $psISE.CurrentFile.Editor.InsertText($Splat)
    }
    else
    {
        Write-Verbose "Returning splatted command to the console"
        return $Splat
    }
}
