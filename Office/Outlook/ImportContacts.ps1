<#
.SYNOPSIS
   Create multiple outlook contacts using a CSV file
.DESCRIPTION
   This Powershell function will allow you to create outlook contacts using a csv file as input.
   The csv has to contain headers that match the properties for the contact objects.
.EXAMPLE
   Import-OutlookContacts -FilePath "$([Environment]::GetFolderPath('MyDocuments'))\Contacts.csv"

   This will create Outlook contacts based on the Contacts.csv file.
.EXAMPLE
   Import-OutlookContacts -FilePath "$([Environment]::GetFolderPath('MyDocuments'))\Contacts.csv" -Overwrite

   This will create Outlook contacts based on the Contacts.csv file and overwrite existing contacts
.EXAMPLE
   Import-OutlookContacts -FilePath "$([Environment]::GetFolderPath('MyDocuments'))\Contacts.csv" -SubFolder NewContacts\Test

   This will create Outlook contacts based on the Contacts.csv file in the subfolder NewContacts\Test.
.EXAMPLE
   Import-OutlookContacts -ListAvailableHeaders

   This will generate a list of possible headers to use for your csv file.
.EXAMPLE
   Import-OutlookContacts -GenerateEmptyCSV -FilePath "$([Environment]::GetFolderPath('MyDocuments'))\Contacts.csv"

   This will create an empty CSV file with all possible headers.
.LINK
   http://itmicah.wordpress.com
#>

function Import-OutlookContacts
{
    [CmdletBinding(DefaultParameterSetName='Default')]
    Param(
        # Path to the csv file for import/export
        [Parameter(Mandatory=$true,
                   HelpMessage='Please enter the path to the CSV file',
                   ParameterSetName='Default')]
        [string]
        $FilePath,

        # Existing subfolder for saving contacts
        [Parameter(Mandatory=$false,
                   ParameterSetName='Default')]
        [string]
        $SubFolder,

        # Create an empty CSV
        [Parameter(ParameterSetName='Default')]
        [switch]
        $GenerateEmptyCSV,

        # Only list the possible headers
        [Parameter(ParameterSetName='ListOnly')]
        [switch]
        $ListPossibleHeaders,

        # Overwrite existing contacts based on the email address
        [switch]
        $Overwrite
    )

    #region Functions

    function Add-Contact 
    {
        param ($folder,$user,$properties,[switch]$Overwrite)

        $OldContact = @($folder.Items).Where{$_.Email1Address -eq $user.Email1Address}
        if ($OldContact -and $PSBoundParameters.Overwrite)
        {
            $OldContact.Delete()
        }
        elseif ($OldContact)
        {
            Write-Warning "Skipping contact with email address $($user.Email1Address)"
            return
        }
        
        $newcontact = $folder.Items.Add()
        Foreach ($property in $properties){
            IF ($user.$property) {
                $newcontact.$property = $user.$property
            }
        }
        $newcontact.Save()
    }

    function Get-ContactProperties 
    {
        $newcontact = $contacts.Items.Add()
        $Props = $newcontact | gm -MemberType property | ?{$_.definition -like 'string*{set}*'}
        $newcontact.Delete()
        $Props | ForEach-Object {$_.Name}
    }

    #endregion Functions

    #region Main Script

    # Open Outlook and get contactlist
    $outlook = new-object -com Outlook.Application -ea 1
    

    If ($contacts = $outlook.session.GetDefaultFolder(10)) 
    {
        If ($PSBoundParameters['SubFolder'])
        {
            $Folder = $contacts
            ForEach ($Item in $SubFolder.Split('\'))
            {
                try
                {
                    $Folder = $Folder.Folders.Item($Item)
                }
                catch
                {
                    throw "Path [$SubFolder] is incorrect. Folder [$Item] is not present."
                }
            }
        }
        else
        {
            $Folder = $contacts
        }
    }
    else
    {
        throw 'Unable to get addressbook information'
    }

    $properties = Get-ContactProperties

    IF ($PSBoundParameters.ListPossibleHeaders)
    {
        Write-Host ""
        Write-Host "---------------------------------------"
        Write-Host "Available headers for the CSV file are:"
        Write-Host "---------------------------------------"
        Write-Host ""
        Write-Output $properties
        return
    }

    IF ($PSBoundParameters.GenerateEmptyCSV) 
    {
        $properties | select $properties | Export-Csv $FilePath -UseCulture -NoTypeInformation
        return
    }

    # Import CSV
    $csv = @(Import-Csv $FilePath -UseCulture)

    # Add contacts
    for ($i = 0; $i -lt $csv.count; $i++)
    { 
        [int]$Completion = $i/$csv.count*100
        Write-Progress -Activity "Adding contacts to outlook" -Status "$Completion% complete" -PercentComplete $Completion
        Add-Contact $folder $csv[$i] $properties -Overwrite:$Overwrite
    }
    #endregion Main Script
}
