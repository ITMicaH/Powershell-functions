<#
.SYNOPSIS
   Create multiple outlook contacts using a CSV file

.DESCRIPTION
   This Powershell script will allow you to create outlook contacts using a csv file as input.
   The csv has to contain headers that match the properties for the contact objects.

.PARAMETER FilePath
   This is the path to the CSV file containing the contact you wish to add.
   (see description for details)

.PARAMETER ListPossibleHeaders
   This will generate a list of possible headers to use for your csv file.

.PARAMETER GenerateEmptyCSV
   This will generate an empty CSV file with all the possible headers.

.EXAMPLE
   .\Import-OutlookContacts.ps1 -FilePath "C:\Users\Pete\Documents\Contacts.csv"

   This will create Outlook contacts based on the Contacts.csv file.

.EXAMPLE
   .\Import-OutlookContacts.ps1 -FilePath "C:\Users\Duncan\Documents\Contacts.csv"

   This will create Outlook content based on the Contacts.csv file.

.EXAMPLE
   .\Import-OutlookContacts.ps1 -ListAvailableHeaders

   This will generate a list of possible headers to use for your csv file.

.EXAMPLE
   .\Import-OutlookContacts.ps1 -GenerateEmptyCSV "C:\Users\Ryan\Documents\Contacts.csv"

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

        # Create an empty CSV
        [Parameter(ParameterSetName='Default')]
        [switch]
        $GenerateEmptyCSV,

        # Only list the possible headers
        [Parameter(ParameterSetName='ListOnly')]
        [switch]
        $ListPossibleHeaders
    )

    #region Functions

    function Add-Contact 
    {
        param ($user,$properties)

        $newcontact = $contacts.Items.Add()

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
    $contacts = $outlook.session.GetDefaultFolder(10)

    If (!$contacts) {
        throw 'Unable to get addressbook information'
    }

    $properties = Get-ContactProperties

    IF ($ListPossibleHeaders){
        Write-Host ""
        Write-Host "---------------------------------------"
        Write-Host "Available headers for the CSV file are:"
        Write-Host "---------------------------------------"
        Write-Host ""
        Write-Output $properties
        return
    }

    IF ($GenerateEmptyCSV) {
        $properties | select $properties | Export-Csv $FilePath -UseCulture -NoTypeInformation
        return
    }

    # Import CSV
    $csv = Import-Csv $FilePath -UseCulture

    # Add contacts
    foreach ($user in $csv) {
        Add-Contact $user $properties
    }
    #endregion Main Script
}
