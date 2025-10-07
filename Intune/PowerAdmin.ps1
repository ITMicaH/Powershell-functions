#Start command (default PowerShell) as local admin with LAPS password in clipboard
function PowerAdmin
{
    [CmdletBinding()]
    [Alias('Admin')]
    Param(
        #Name of the local admin account
        [Parameter()]
        [string]
        $UserName = 'Administrator',

        #Command to run using 
        [Parameter(ValueFromRemainingArguments)]
        [string]
        $Command = 'PowerShell.exe'
    )
    If ($RootCreds)
    {
        Write-Verbose 'Using Root Creds'
        $Credential = $RootCreds
    }
    else
    {
        Write-Verbose 'Trying clipboard'
        $PW = Get-Clipboard | ConvertTo-SecureString -AsPlainText -Force
        $Credential = New-Object System.Management.Automation.PSCredential("$env:COMPUTERNAME\$UserName", $PW)
    }
    
    Write-Verbose "Handling command [$Command]"
    If ($Command -match '\s')
    {
        $Arguments = $Command.Split(' ') | select -Skip 1
        $Command = $Command.Split(' ')[0]
    }
    $Params = @{
        FilePath = $Command
    }
    If ($Arguments)
    {
        $Params.Add('ArgumentList',$Arguments)
    }
    Try
    {
        Start-Process @Params -Credential $Credential -ErrorAction Stop
    }
    catch
    {
        If ($_.Exception.Message -like '*De gebruikersnaam of het wachtwoord is onjuist.')
        {
            $Credential = Get-Credential -Message 'Plak je wachtwoord' -UserName "$env:COMPUTERNAME\$UserName"
            Start-Process @Params -Credential $Credential
        }
        else
        {
            Write-Error $_
        }
    }
    If (!$RootCreds -and $?)
    {
        New-Variable -Name RootCreds -Value $Credential -Visibility Private -Scope script -Force
    }
}
