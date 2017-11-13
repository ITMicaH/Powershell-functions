#ImportContacts.ps1
## Functions
### Import-OutlookContacts
This Powershell function will allow you to create outlook contacts using a csv file as input. The csv has to contain headers that match the properties for the contact objects.

EXAMPLE:

`PS\> Import-OutlookContacts.ps1 -FilePath "C:\Users\Pete\Documents\Contacts.csv"`

This will create Outlook contacts based on the Contacts.csv file.

EXAMPLE:

`PS\> Import-OutlookContacts.ps1 -FilePath "C:\Users\Pete\Documents\Contacts.csv" -SubFolder NewContacts\Test`

This will create Outlook contacts based on the Contacts.csv file in the existing subfolder NewContacts\Test.

EXAMPLE:

`PS\> Import-OutlookContacts.ps1 -ListAvailableHeaders`

This will generate a list of possible headers to use for your csv file.

EXAMPLE:

`PS\> Import-OutlookContacts.ps1 -GenerateEmptyCSV -FilePath "C:\Users\Ryan\Documents\Contacts.csv"`

This will create an empty CSV file with all possible headers.

