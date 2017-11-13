<#
.SYNOPSIS
   Create multiple outlook contacts using a CSV file
.DESCRIPTION
   This Powershell function will allow you to create outlook contacts using a csv file as input.
   The csv has to contain headers that match the properties for the contact objects.
.EXAMPLE
   Import-OutlookContacts -FilePath "C:\Users\Pete\Documents\Contacts.csv"

   This will create Outlook contacts based on the Contacts.csv file.
.EXAMPLE
   Import-OutlookContacts -FilePath "C:\Users\Pete\Documents\Contacts.csv" -SubFolder NewContacts\Test

   This will create Outlook contacts based on the Contacts.csv file in the subfolder NewContacts\Test
.EXAMPLE
   Import-OutlookContacts -ListAvailableHeaders

   This will generate a list of possible headers to use for your csv file.
.EXAMPLE
   Import-OutlookContacts -GenerateEmptyCSV -FilePath "C:\Users\Ryan\Documents\Contacts.csv"

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
        $ListPossibleHeaders
    )

    #region Functions

    function Add-Contact 
    {
        param ($folder,$user,$properties)

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
            $SubFolder.Split('\').ForEach({
                try
                {
                    $Folder = $Folder.Folders.Item($_)
                }
                catch
                {
                    throw "Path [$SubFolder] is incorrect."
                }
            })
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
    for ($i = 0; $i -lt $csv.count; $i++)
    { 
        [int]$Completion = $i/$csv.count*100
        Write-Progress -Activity "Adding contacts to outlook" -Status "$Completion% complete" -PercentComplete $Completion
        Add-Contact $folder $csv[$i] $properties
    }
    #endregion Main Script
}
