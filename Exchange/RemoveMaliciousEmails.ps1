<#
.Synopsis
   Search and delete malicious emails
.DESCRIPTION
   Searches for emails with by subject, attachment or sender address, logs detailed information to a target mailbox
   in a folder called 'SearchAndDeleteLog' and asks permission per mailbox to delete the malicious email.

   IMPORTANT: Always check the contents of the csv file that was mailed to you if only actual malicious mails where detected!
.EXAMPLE
   Remove-MaliciousEmails -From suspicious.name@malicious.com -StartDate (Get-Date).AddDays(-2) -EndDate (Get-Date) -Server 'vsw-exc-001' -TargetMailbox User21
   Searches for emails from suspicious.name@malicious.com over the last two days. If found, permission will be asked to remove them.
.EXAMPLE
   Remove-MaliciousEmails -Subject malware -StartDate (Get-Date).AddDays(-2) -Server 'vsw-exc-001' -TargetMailbox User21
   Searches for emails with the word 'malware' in the subject over the last two days. If found, permission will be asked to remove them.
#>
function Remove-MaliciousEmails
{
    [CmdletBinding()]
    Param
    (
        # Direction of the email
        [ValidateSet('Sent','Received')]
        [string]
        $Direction = 'Received',

        # Name of the senders address
        [string]
        $From,

        # Subject of the email
        [string]
        $Subject,

        # Attachment name
        [string]
        $Attachment,

        # Start search from this date
        [DateTime]
        $StartDate,

        # End search by this date
        [DateTime]
        $EndDate,

        # Name of the exchange server
        [Parameter(mandatory)]
        [string]
        $Server,

        # Name of the target mailbox
        [Parameter(mandatory)]
        [string]
        $TargetMailbox
    )

    Begin
    {
        $SearchQuery = @('Kind:email')
        If ($DateKey = $PSBoundParameters.Keys | ?{$_ -like '*Date'})
        {
            If ($DateKey.Count -eq 2)
            {
                $SearchQuery += "$Direction`:`"$($StartDate.ToShortDateString())..$($EndDate.ToShortDateString())`""
            }
            else
            {
                switch ($DateKey)
                {
                    StartDate {$SearchQuery += "$Direction>=$($StartDate.ToShortDateString())"}
                    EndDate   {$SearchQuery += "$Direction<=$($EndDate.ToShortDateString())"}
                }
            }
        }
        switch -Wildcard ($PSBoundParameters.Keys)
        {
            Subject     {$SearchQuery += "Subject:`"$Subject`""}
            Attachment  {$SearchQuery += "Attachment:`"$Attachment`""}
            From        {$SearchQuery += "From:$From"}
        }

        $oExchange = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri "http://$($Server)/PowerShell" -Authentication Kerberos
        $Commands = @(
            'Get-MailBox'
            'Set-ADServerSettings'
            'Search-Mailbox'
            'New-MailboxSearch'
        )
        try
        {
            Import-PSSession -Session $oExchange -CommandName $Commands | Out-Null
            Set-ADServerSettings -ViewEntireForest:$True
        }
        catch{}
    }
    Process
    {
        $QueryResult = Get-Mailbox -ResultSize unlimited | 
            Search-Mailbox -SearchQuery $SearchQuery -TargetMailbox $TargetMailbox -TargetFolder "SearchAndDeleteLog" -LogLevel full -LogOnly -WarningAction 0
        $Mailboxes = $QueryResult | ?{$_.ResultItemsCount -gt 0} | Get-Mailbox
        $Mailboxes | select Name,DisplayName,@{name='Domain';expression={$_.Id.Split('.')[0]}},WindowsEmailAddress | sort Name | ogv -Title 'List of affected mailboxes'
        $Mailboxes | Search-Mailbox -SearchQuery $SearchQuery -TargetMailbox $TargetMailbox -TargetFolder "SearchAndDeleteLog" -DeleteContent -WarningAction 0
    }
    End
    {
        $oExchange | Remove-PSSession
    }
}
